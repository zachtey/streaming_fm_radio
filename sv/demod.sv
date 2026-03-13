/*
demodulation module
1. stores current and previous samples (signed)
2. complex multiplication (signed)
3. atan
4. gain multiplication
*/

module demod #(
    //param
    parameter int INPUT_W = 16,
    parameter int DATA_W  = 32,
    parameter int GAIN_W  = 16
) (
    //ports
    //admin
    input  logic clk,
    input  logic rst,
    //inputs
    input  logic valid_in,
    input  logic signed [INPUT_W-1:0] i_in,
    input  logic signed [INPUT_W-1:0] q_in,
    //outputs
    output logic signed [DATA_W-1:0] demod_out,
    output logic demod_valid_out
);

    //localparams
    localparam int BITS = 10;
    localparam int QUANT_VAL = 1 << BITS;
    localparam int QUAD_RATE = 256000;
    localparam int MAX_DEV = 55000;
    localparam int PROD_W = 2 * INPUT_W;
    localparam int SUM_W  = PROD_W + 1;
    localparam int ANG_W  = DATA_W;
    localparam int OUT_W  = DATA_W;
    // gain precomputed following C header:
    // QUANTIZE_F(QUAD_RATE / (2*pi*MAX_DEV)) ≈ 758
    localparam logic signed [GAIN_W-1:0] FM_DEMOD_GAIN = 16'sd758;

    // local variables + logics
    // 1) previous-sample storage
    logic signed [INPUT_W-1:0] i_prev, i_prev_c;
    logic signed [INPUT_W-1:0] q_prev, q_prev_c;
    logic                      have_prev, have_prev_c;
    // 2) complex multiplication path
    logic signed [PROD_W-1:0] mul_ii, mul_ii_c;
    logic signed [PROD_W-1:0] mul_qq, mul_qq_c;
    logic signed [PROD_W-1:0] mul_iq, mul_iq_c;
    logic signed [PROD_W-1:0] mul_qi, mul_qi_c;
    logic signed [SUM_W-1:0]  r_calc, r_calc_c;
    logic signed [SUM_W-1:0]  i_calc, i_calc_c;
    // 3) atan interface
    logic atan_valid_in,  atan_valid_in_c;
    logic atan_valid_out;
    logic signed [SUM_W-1:0]  atan_x, atan_x_c; // r
    logic signed [SUM_W-1:0]  atan_y, atan_y_c; // i
    logic signed [ANG_W-1:0]  atan_angle;
    // 4) gain stage
    logic signed [ANG_W+GAIN_W-1:0] gain_mult, gain_mult_c;
    logic gain_output_valid, gain_output_valid_c;

    //instantiate atan module
    atan #(
        .INPUT_W (SUM_W),
        .ANG_W   (ANG_W)
    ) atan_inst (
        .clk (clk),
        .rst (rst),
        .valid_in (atan_valid_in),
        .x_in (atan_x),
        .y_in (atan_y),
        .valid_out(atan_valid_out),
        .angle_out(atan_angle)
    );

    // combinational process
    always_comb begin
        // defaults: hold state
        i_prev_c = i_prev;
        q_prev_c = q_prev;
        have_prev_c = have_prev;
        mul_ii_c = mul_ii;
        mul_qq_c = mul_qq;
        mul_iq_c = mul_iq;
        mul_qi_c = mul_qi;
        r_calc_c = r_calc;
        i_calc_c = i_calc;
        atan_valid_in_c  = 1'b0; // pulse when a new r/i pair is ready
        atan_x_c = atan_x;
        atan_y_c = atan_y;
        gain_mult_c = gain_mult;
        gain_output_valid_c = gain_output_valid;
        
        //outputs
        demod_valid_out = gain_output_valid;
        demod_out = gain_mult[ANG_W+GAIN_W-1 -: OUT_W];

        // new input sample - three things we must do!
        if (valid_in) begin
            // only compute a valid phase difference once we already have a previous sample
            if (have_prev) begin
                // 1) complex multiply pieces
                mul_ii_c = i_prev * i_in;
                mul_qq_c = q_prev * q_in;
                mul_iq_c = i_prev * q_in;
                mul_qi_c = q_prev * i_in;
                // r = I_prev*I + Q_prev*Q
                r_calc_c =  $signed({mul_ii_c[PROD_W-1], mul_ii_c}) +
                            $signed({mul_qq_c[PROD_W-1], mul_qq_c});
                // i = I_prev*Q - Q_prev*I
                i_calc_c =  $signed({mul_iq_c[PROD_W-1], mul_iq_c}) -
                            $signed({mul_qi_c[PROD_W-1], mul_qi_c});
                // 2) feed atan block
                atan_x_c = r_calc_c;
                atan_y_c = i_calc_c;
                atan_valid_in_c = 1'b1;
            end

            // update previous sample after using old previous sample
            i_prev_c    = i_in;
            q_prev_c    = q_in;
            have_prev_c = 1'b1;
        end

        // 3) gain stage
        gain_mult_c = atan_angle * FM_DEMOD_GAIN;
        gain_output_valid_c = atan_valid_out;
    end

    // sequential process
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            i_prev <= '0;
            q_prev <= '0;
            have_prev <= 1'b0;
            mul_ii <= '0;
            mul_qq <= '0;
            mul_iq <= '0;
            mul_qi <= '0;
            r_calc <= '0;
            i_calc <= '0;
            atan_valid_in <= 1'b0;
            atan_x <= '0;
            atan_y <= '0;
            gain_mult <= '0;
            gain_output_valid <= '0;
        end else begin
            i_prev <= i_prev_c;
            q_prev <= q_prev_c;
            have_prev <= have_prev_c;
            mul_ii <= mul_ii_c;
            mul_qq <= mul_qq_c;
            mul_iq <= mul_iq_c;
            mul_qi <= mul_qi_c;
            r_calc <= r_calc_c;
            i_calc <= i_calc_c;
            atan_valid_in <= atan_valid_in_c;
            atan_x <= atan_x_c;
            atan_y <= atan_y_c;
            gain_mult <= gain_mult_c;
            gain_output_valid <= gain_output_valid_c;
        end
    end

endmodule