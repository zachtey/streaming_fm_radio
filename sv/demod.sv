/*
demodulation module
1. stores current and previous samples (signed)
2. complex multiplication (signed)
3. atan
4. gain multiplication
*/
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

    localparam int BITS      = 10;
    localparam int PROD_W    = 2 * INPUT_W;
    localparam int SUM_W     = PROD_W + 1;
    localparam int ANG_W     = DATA_W;
    localparam logic signed [GAIN_W-1:0] FM_DEMOD_GAIN = 16'sd758;

    function automatic logic signed [ANG_W+GAIN_W-1:0] trunc_div_pow2;
        input logic signed [ANG_W+GAIN_W-1:0] val;
        logic signed [ANG_W+GAIN_W-1:0] bias;
        begin
            if (BITS == 0) begin
                trunc_div_pow2 = val;
            end else begin
                if (val < 0)
                    bias = ({{(ANG_W+GAIN_W-1){1'b0}},1'b1} <<< BITS) - 1;
                else
                    bias = '0;
                trunc_div_pow2 = (val + bias) >>> BITS;
            end
        end
    endfunction

    logic signed [INPUT_W-1:0] i_prev, i_prev_c;
    logic signed [INPUT_W-1:0] q_prev, q_prev_c;
    logic                      have_prev, have_prev_c;

    logic signed [PROD_W-1:0] mul_ii, mul_ii_c;
    logic signed [PROD_W-1:0] mul_qq, mul_qq_c;
    logic signed [PROD_W-1:0] mul_iq, mul_iq_c;
    logic signed [PROD_W-1:0] mul_qi, mul_qi_c;
    logic signed [SUM_W-1:0]  r_calc, r_calc_c;
    logic signed [SUM_W-1:0]  i_calc, i_calc_c;

    logic                     atan_valid_in, atan_valid_in_c;
    logic                     atan_valid_out;
    logic signed [SUM_W-1:0]  atan_x, atan_x_c;
    logic signed [SUM_W-1:0]  atan_y, atan_y_c;
    logic signed [ANG_W-1:0]  atan_angle;

    logic signed [ANG_W+GAIN_W-1:0] gain_mult, gain_mult_c;
    logic                           gain_output_valid, gain_output_valid_c;

    atan #(
        .INPUT_W (SUM_W),
        .ANG_W   (ANG_W),
        .BITS    (BITS)
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
        i_prev_c            = i_prev;
        q_prev_c            = q_prev;
        have_prev_c         = have_prev;

        mul_ii_c            = mul_ii;
        mul_qq_c            = mul_qq;
        mul_iq_c            = mul_iq;
        mul_qi_c            = mul_qi;
        r_calc_c            = r_calc;
        i_calc_c            = i_calc;

        atan_valid_in_c     = 1'b0;
        atan_x_c            = atan_x;
        atan_y_c            = atan_y;

        gain_mult_c         = gain_mult;
        gain_output_valid_c = atan_valid_out;

        demod_valid_out     = gain_output_valid;
        demod_out           = trunc_div_pow2(gain_mult)[DATA_W-1:0];

        if (valid_in) begin
            if (have_prev) begin
                mul_ii_c = i_prev * i_in;
                mul_qq_c = q_prev * q_in;
                mul_iq_c = i_prev * q_in;
                mul_qi_c = q_prev * i_in;

                r_calc_c = $signed({mul_ii_c[PROD_W-1], mul_ii_c}) +
                           $signed({mul_qq_c[PROD_W-1], mul_qq_c});

                i_calc_c = $signed({mul_iq_c[PROD_W-1], mul_iq_c}) -
                           $signed({mul_qi_c[PROD_W-1], mul_qi_c});

                atan_x_c        = r_calc_c;
                atan_y_c        = i_calc_c;
                atan_valid_in_c = 1'b1;
            end

            i_prev_c    = i_in;
            q_prev_c    = q_in;
            have_prev_c = 1'b1;
        end

        gain_mult_c = atan_angle * FM_DEMOD_GAIN;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            i_prev            <= '0;
            q_prev            <= '0;
            have_prev         <= 1'b0;
            mul_ii            <= '0;
            mul_qq            <= '0;
            mul_iq            <= '0;
            mul_qi            <= '0;
            r_calc            <= '0;
            i_calc            <= '0;
            atan_valid_in     <= 1'b0;
            atan_x            <= '0;
            atan_y            <= '0;
            gain_mult         <= '0;
            gain_output_valid <= '0;
        end else begin
            i_prev            <= i_prev_c;
            q_prev            <= q_prev_c;
            have_prev         <= have_prev_c;
            mul_ii            <= mul_ii_c;
            mul_qq            <= mul_qq_c;
            mul_iq            <= mul_iq_c;
            mul_qi            <= mul_qi_c;
            r_calc            <= r_calc_c;
            i_calc            <= i_calc_c;
            atan_valid_in     <= atan_valid_in_c;
            atan_x            <= atan_x_c;
            atan_y            <= atan_y_c;
            gain_mult         <= gain_mult_c;
            gain_output_valid <= gain_output_valid_c;
        end
    end

endmodule