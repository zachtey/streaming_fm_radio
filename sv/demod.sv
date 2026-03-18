`timescale 1ns/1ps

module demod #(
    parameter int INPUT_W = 16,
    parameter int DATA_W  = 32,
    parameter int GAIN_W  = 16
) (
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic signed [INPUT_W-1:0] i_in,
    input  logic signed [INPUT_W-1:0] q_in,
    output logic signed [DATA_W-1:0] demod_out,
    output logic demod_valid_out
);

    localparam int BITS = 10;

    // From C header:
    // FM_DEMOD_GAIN = QUANTIZE_F(QUAD_RATE / (2*pi*MAX_DEV)) ≈ 758
    localparam logic signed [31:0] FM_DEMOD_GAIN = 32'sd758;
    localparam logic signed [31:0] QUAD1_Q       = 32'sd804;
    localparam logic signed [31:0] QUAD3_Q       = 32'sd2413;

    logic signed [INPUT_W-1:0] i_prev, i_prev_c;
    logic signed [INPUT_W-1:0] q_prev, q_prev_c;
    logic                      have_prev, have_prev_c;

    logic signed [31:0] demod_out_c;
    logic               demod_valid_out_c;

    // Re-quantized Q10 versions of the 16-bit FIR outputs
    logic signed [31:0] i_prev_q10, q_prev_q10, i_in_q10, q_in_q10;

    // 64-bit products because we re-quantize inputs before multiplying
    logic signed [63:0] prod_a, prod_b, prod_c, prod_d;
    logic signed [31:0] deq_a, deq_b, deq_c, deq_d;
    logic signed [31:0] r_now, i_now;
    logic signed [31:0] angle_now;
    logic signed [63:0] gain_prod64;

    function automatic logic signed [31:0] quantize_i32;
        input logic signed [31:0] val;
        begin
            quantize_i32 = val <<< BITS;
        end
    endfunction

    function automatic logic signed [31:0] dequantize_i32;
        input logic signed [31:0] val;
        logic signed [31:0] bias;
        begin
            if (BITS == 0) begin
                dequantize_i32 = val;
            end else begin
                if (val < 0)
                    bias = (32'sd1 <<< BITS) - 1;
                else
                    bias = 32'sd0;
                dequantize_i32 = (val + bias) >>> BITS;
            end
        end
    endfunction

    function automatic logic signed [31:0] dequantize_i64_to_32;
        input logic signed [63:0] val;
        logic signed [63:0] bias;
        logic signed [63:0] tmp;
        begin
            if (BITS == 0) begin
                tmp = val;
            end else begin
                if (val < 0)
                    bias = (64'sd1 <<< BITS) - 1;
                else
                    bias = 64'sd0;
                tmp = (val + bias) >>> BITS;
            end
            dequantize_i64_to_32 = tmp[31:0];
        end
    endfunction

    // Unsigned restoring divide, no "/" operator
    function automatic logic [31:0] udiv_u32;
        input logic [31:0] numer;
        input logic [31:0] denom;
        logic [32:0] rem;
        logic [31:0] quot;
        begin
            rem  = 33'd0;
            quot = 32'd0;

            if (denom == 32'd0) begin
                quot = 32'd0;
            end else begin
                for (int k = 31; k >= 0; k--) begin
                    rem = {rem[31:0], numer[k]};
                    if (rem >= {1'b0, denom}) begin
                        rem     = rem - {1'b0, denom};
                        quot[k] = 1'b1;
                    end
                end
            end

            udiv_u32 = quot;
        end
    endfunction

    function automatic logic signed [31:0] sdiv_trunc0_num_by_posden;
        input logic signed [31:0] numer;
        input logic [31:0]        denom;
        logic [31:0] qmag;
        begin
            if (denom == 32'd0) begin
                sdiv_trunc0_num_by_posden = 32'sd0;
            end else if (numer < 0) begin
                qmag = udiv_u32($unsigned(-numer), denom);
                sdiv_trunc0_num_by_posden = -$signed(qmag);
            end else begin
                qmag = udiv_u32($unsigned(numer), denom);
                sdiv_trunc0_num_by_posden = $signed(qmag);
            end
        end
    endfunction

    function automatic logic signed [31:0] qarctan32;
        input logic signed [31:0] y;
        input logic signed [31:0] x;
        logic signed [31:0] abs_y;
        logic signed [31:0] abs_y_p1;
        logic signed [31:0] delta;
        logic signed [31:0] denom_s;
        logic signed [31:0] r_signed;
        logic signed [31:0] mult32;
        logic signed [31:0] mult_deq32;
        logic signed [31:0] angle32;
        begin
            if (y < 0)
                abs_y = -y;
            else
                abs_y = y;

            abs_y_p1 = abs_y + 32'sd1;

            if (x >= 0) begin
                delta      = x - abs_y_p1;
                denom_s    = x + abs_y_p1;
                r_signed   = sdiv_trunc0_num_by_posden(quantize_i32(delta), $unsigned(denom_s));
                mult32     = QUAD1_Q * r_signed;
                mult_deq32 = dequantize_i32(mult32);
                angle32    = QUAD1_Q - mult_deq32;
            end else begin
                delta      = x + abs_y_p1;
                denom_s    = abs_y_p1 - x;
                r_signed   = sdiv_trunc0_num_by_posden(quantize_i32(delta), $unsigned(denom_s));
                mult32     = QUAD1_Q * r_signed;
                mult_deq32 = dequantize_i32(mult32);
                angle32    = QUAD3_Q - mult_deq32;
            end

            if (y < 0)
                angle32 = -angle32;

            qarctan32 = angle32;
        end
    endfunction

    always_comb begin
        i_prev_c          = i_prev;
        q_prev_c          = q_prev;
        have_prev_c       = have_prev;
        demod_out_c       = demod_out;
        demod_valid_out_c = 1'b0;

        // Re-quantize 16-bit FIR outputs back to Q10 before demod math
        i_prev_q10 = {{16{i_prev[INPUT_W-1]}}, i_prev} <<< BITS;
        q_prev_q10 = {{16{q_prev[INPUT_W-1]}}, q_prev} <<< BITS;
        i_in_q10   = {{16{i_in[INPUT_W-1]}},   i_in}   <<< BITS;
        q_in_q10   = {{16{q_in[INPUT_W-1]}},   q_in}   <<< BITS;

        prod_a    = 64'sd0;
        prod_b    = 64'sd0;
        prod_c    = 64'sd0;
        prod_d    = 64'sd0;
        deq_a     = 32'sd0;
        deq_b     = 32'sd0;
        deq_c     = 32'sd0;
        deq_d     = 32'sd0;
        r_now     = 32'sd0;
        i_now     = 32'sd0;
        angle_now = 32'sd0;
        gain_prod64 = 64'sd0;

        if (valid_in) begin
            if (have_prev) begin
                // Demod on re-quantized Q10 FIR outputs
                prod_a = i_prev_q10 * i_in_q10;
                prod_b = -(q_prev_q10 * q_in_q10);
                prod_c = i_prev_q10 * q_in_q10;
                prod_d = -(q_prev_q10 * i_in_q10);

                deq_a = dequantize_i64_to_32(prod_a);
                deq_b = dequantize_i64_to_32(prod_b);
                deq_c = dequantize_i64_to_32(prod_c);
                deq_d = dequantize_i64_to_32(prod_d);

                r_now = deq_a - deq_b;
                i_now = deq_c + deq_d;

                angle_now = qarctan32(i_now, r_now);

                gain_prod64         = $signed(FM_DEMOD_GAIN) * $signed(angle_now);
                demod_out_c         = dequantize_i64_to_32(gain_prod64);
                demod_valid_out_c   = 1'b1;
            end

            i_prev_c    = i_in;
            q_prev_c    = q_in;
            have_prev_c = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            i_prev          <= '0;
            q_prev          <= '0;
            have_prev       <= 1'b0;
            demod_out       <= 32'sd0;
            demod_valid_out <= 1'b0;
        end else begin
            i_prev          <= i_prev_c;
            q_prev          <= q_prev_c;
            have_prev       <= have_prev_c;
            demod_out       <= demod_out_c;
            demod_valid_out <= demod_valid_out_c;
        end
    end

endmodule