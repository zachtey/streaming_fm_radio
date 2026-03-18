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

    function automatic logic signed [31:0] dequantize_i32;
        input logic signed [31:0] val;
        logic signed [31:0] bias;
        begin
            // C integer division truncates toward zero
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

    logic signed [15:0] i_prev, i_prev_c;
    logic signed [15:0] q_prev, q_prev_c;
    logic               have_prev, have_prev_c;

    logic signed [31:0] prod_a, prod_a_c;
    logic signed [31:0] prod_b, prod_b_c;
    logic signed [31:0] prod_c, prod_c_c;
    logic signed [31:0] prod_d, prod_d_c;

    logic signed [31:0] deq_a, deq_a_c;
    logic signed [31:0] deq_b, deq_b_c;
    logic signed [31:0] deq_c, deq_c_c;
    logic signed [31:0] deq_d, deq_d_c;

    logic signed [31:0] r_calc, r_calc_c;
    logic signed [31:0] i_calc, i_calc_c;

    logic               atan_valid_in, atan_valid_in_c;
    logic               atan_valid_out;
    logic signed [31:0] atan_x, atan_x_c;
    logic signed [31:0] atan_y, atan_y_c;
    logic signed [31:0] atan_angle;

    logic signed [31:0] gain_prod, gain_prod_c;
    logic signed [31:0] gain_out32, gain_out32_c;
    logic               gain_valid, gain_valid_c;

    atan #(
        .INPUT_W(32),
        .ANG_W  (32),
        .BITS   (BITS)
    ) atan_inst (
        .clk      (clk),
        .rst      (rst),
        .valid_in (atan_valid_in),
        .x_in     (atan_x),
        .y_in     (atan_y),
        .valid_out(atan_valid_out),
        .angle_out(atan_angle)
    );

    always_comb begin
        i_prev_c      = i_prev;
        q_prev_c      = q_prev;
        have_prev_c   = have_prev;

        prod_a_c      = prod_a;
        prod_b_c      = prod_b;
        prod_c_c      = prod_c;
        prod_d_c      = prod_d;

        deq_a_c       = deq_a;
        deq_b_c       = deq_b;
        deq_c_c       = deq_c;
        deq_d_c       = deq_d;

        r_calc_c      = r_calc;
        i_calc_c      = i_calc;

        atan_valid_in_c = 1'b0;
        atan_x_c        = atan_x;
        atan_y_c        = atan_y;

        gain_prod_c   = gain_prod;
        gain_out32_c  = gain_out32;
        gain_valid_c  = atan_valid_out;

        demod_valid_out = gain_valid;
        demod_out       = gain_out32;

        if (valid_in) begin
            if (have_prev) begin
                // Match C demodulate():
                // r = DEQUANTIZE((*real_prev * real)) - DEQUANTIZE((-*imag_prev * imag));
                // i = DEQUANTIZE((*real_prev * imag)) + DEQUANTIZE((-*imag_prev * real));

                prod_a_c = $signed(i_prev) * $signed(i_in);
                prod_b_c = -($signed(q_prev) * $signed(q_in));
                prod_c_c = $signed(i_prev) * $signed(q_in);
                prod_d_c = -($signed(q_prev) * $signed(i_in));

                deq_a_c = dequantize_i32(prod_a_c);
                deq_b_c = dequantize_i32(prod_b_c);
                deq_c_c = dequantize_i32(prod_c_c);
                deq_d_c = dequantize_i32(prod_d_c);

                r_calc_c = deq_a_c - deq_b_c;
                i_calc_c = deq_c_c + deq_d_c;

                atan_x_c        = r_calc_c;
                atan_y_c        = i_calc_c;
                atan_valid_in_c = 1'b1;
            end

            // update previous sample
            i_prev_c    = i_in;
            q_prev_c    = q_in;
            have_prev_c = 1'b1;
        end

        // Match C:
        // *demod_out = DEQUANTIZE(gain * qarctan(i, r));
        gain_prod_c  = FM_DEMOD_GAIN * atan_angle;
        gain_out32_c = dequantize_i32(gain_prod_c);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            i_prev        <= 16'sd0;
            q_prev        <= 16'sd0;
            have_prev     <= 1'b0;

            prod_a        <= 32'sd0;
            prod_b        <= 32'sd0;
            prod_c        <= 32'sd0;
            prod_d        <= 32'sd0;

            deq_a         <= 32'sd0;
            deq_b         <= 32'sd0;
            deq_c         <= 32'sd0;
            deq_d         <= 32'sd0;

            r_calc        <= 32'sd0;
            i_calc        <= 32'sd0;

            atan_valid_in <= 1'b0;
            atan_x        <= 32'sd0;
            atan_y        <= 32'sd0;

            gain_prod     <= 32'sd0;
            gain_out32    <= 32'sd0;
            gain_valid    <= 1'b0;
        end else begin
            i_prev        <= i_prev_c;
            q_prev        <= q_prev_c;
            have_prev     <= have_prev_c;

            prod_a        <= prod_a_c;
            prod_b        <= prod_b_c;
            prod_c        <= prod_c_c;
            prod_d        <= prod_d_c;

            deq_a         <= deq_a_c;
            deq_b         <= deq_b_c;
            deq_c         <= deq_c_c;
            deq_d         <= deq_d_c;

            r_calc        <= r_calc_c;
            i_calc        <= i_calc_c;

            atan_valid_in <= atan_valid_in_c;
            atan_x        <= atan_x_c;
            atan_y        <= atan_y_c;

            gain_prod     <= gain_prod_c;
            gain_out32    <= gain_out32_c;
            gain_valid    <= gain_valid_c;
        end
    end

endmodule