`timescale 1ns/1ps

module atan #(
    parameter int INPUT_W = 32,
    parameter int ANG_W   = 32,
    parameter int BITS    = 10,
    parameter int ITER    = 11   // unused, kept for drop-in compatibility
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       valid_in,
    input  logic signed [INPUT_W-1:0]  x_in,
    input  logic signed [INPUT_W-1:0]  y_in,
    output logic                       valid_out,
    output logic signed [ANG_W-1:0]    angle_out
);

    // C: QUANTIZE_F(PI/4), QUANTIZE_F(3PI/4) with BITS=10
    localparam logic signed [31:0] QUAD1_Q = 32'sd804;
    localparam logic signed [31:0] QUAD3_Q = 32'sd2413;

    logic               valid_out_c;
    logic signed [31:0] angle_out_c;

    logic signed [31:0] x32, y32;
    logic signed [31:0] abs_y;
    logic signed [31:0] abs_y_p1;
    logic signed [31:0] delta;
    logic signed [31:0] denom_s;
    logic signed [31:0] r_signed;
    logic signed [31:0] mult32;
    logic signed [31:0] mult_deq32;
    logic signed [31:0] angle32;

    // -----------------------------
    // C macro equivalents
    // -----------------------------
    function automatic logic signed [31:0] quantize_i32;
        input logic signed [31:0] val;
        begin
            // C macro: ((int)(i) * (int)QUANT_VAL)
            quantize_i32 = val * 32'sd1024;
        end
    endfunction

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

    // Unsigned restoring division, fully unrolled in function.
    // Returns floor(numer/denom) for unsigned values.
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
                for (int i = 31; i >= 0; i--) begin
                    rem = {rem[31:0], numer[i]};
                    if (rem >= {1'b0, denom}) begin
                        rem     = rem - {1'b0, denom};
                        quot[i] = 1'b1;
                    end
                end
            end

            udiv_u32 = quot;
        end
    endfunction

    // Signed divide with truncation toward zero, denominator assumed positive.
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

    // -----------------------------
    // Bit-true C qarctan()
    // -----------------------------
    always_comb begin
        valid_out_c = 1'b0;
        angle_out_c = angle_out;

        x32        = x_in;
        y32        = y_in;
        abs_y      = 32'sd0;
        abs_y_p1   = 32'sd0;
        delta      = 32'sd0;
        denom_s    = 32'sd0;
        r_signed   = 32'sd0;
        mult32     = 32'sd0;
        mult_deq32 = 32'sd0;
        angle32    = 32'sd0;

        if (valid_in) begin
            // C: int abs_y = abs(y) + 1;
            if (y32 < 0)
                abs_y = -y32;
            else
                abs_y = y32;

            abs_y_p1 = abs_y + 32'sd1;

            // C:
            // if (x >= 0) {
            //   r = QUANTIZE_I(x - abs_y) / (x + abs_y);
            //   angle = quad1 - DEQUANTIZE(quad1 * r);
            // } else {
            //   r = QUANTIZE_I(x + abs_y) / (abs_y - x);
            //   angle = quad3 - DEQUANTIZE(quad1 * r);
            // }
            if (x32 >= 0) begin
                delta      = x32 - abs_y_p1;
                denom_s    = x32 + abs_y_p1;
                r_signed   = sdiv_trunc0_num_by_posden(quantize_i32(delta), $unsigned(denom_s));
                mult32     = QUAD1_Q * r_signed;
                mult_deq32 = dequantize_i32(mult32);
                angle32    = QUAD1_Q - mult_deq32;
            end else begin
                delta      = x32 + abs_y_p1;
                denom_s    = abs_y_p1 - x32;
                r_signed   = sdiv_trunc0_num_by_posden(quantize_i32(delta), $unsigned(denom_s));
                mult32     = QUAD1_Q * r_signed;
                mult_deq32 = dequantize_i32(mult32);
                angle32    = QUAD3_Q - mult_deq32;
            end

            // C: return ((y < 0) ? -angle : angle);
            if (y32 < 0)
                angle32 = -angle32;

            angle_out_c = angle32;
            valid_out_c = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            angle_out <= 32'sd0;
        end else begin
            valid_out <= valid_out_c;
            angle_out <= angle_out_c;
        end
    end

endmodule