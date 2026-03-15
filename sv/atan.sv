module atan #(
    parameter int INPUT_W = 33,
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

    localparam int WORK_W  = INPUT_W + 2;
    localparam int NUM_W   = WORK_W + BITS;
    localparam int DEN_W   = WORK_W;
    localparam int DIV_LAT = NUM_W;
    localparam int MUL_W   = ANG_W + NUM_W;

    localparam logic signed [ANG_W-1:0] QUAD1_Q   = 32'sd804;   // QUANTIZE_F(pi/4)
    localparam logic signed [ANG_W-1:0] QUAD3_Q   = 32'sd2413;  // QUANTIZE_F(3pi/4)
    localparam logic signed [ANG_W-1:0] HALF_PI_Q = 32'sd1608;  // QUANTIZE_F(pi/2)

    function automatic logic signed [MUL_W-1:0] trunc_div_pow2;
        input logic signed [MUL_W-1:0] val;
        logic signed [MUL_W-1:0] bias;
        begin
            if (BITS == 0) begin
                trunc_div_pow2 = val;
            end else begin
                if (val < 0)
                    bias = ({{(MUL_W-1){1'b0}},1'b1} <<< BITS) - 1;
                else
                    bias = '0;
                trunc_div_pow2 = (val + bias) >>> BITS;
            end
        end
    endfunction

    logic              div_valid_in;
    logic [NUM_W-1:0]  div_numer_in;
    logic [DEN_W-1:0]  div_denom_in;

    logic              div_valid_out;
    logic [NUM_W-1:0]  div_quot_out;

    logic                    num_neg_pipe        [0:DIV_LAT];
    logic                    num_neg_pipe_c      [0:DIV_LAT];
    logic                    special_pipe        [0:DIV_LAT];
    logic                    special_pipe_c      [0:DIV_LAT];
    logic                    negate_angle_pipe   [0:DIV_LAT];
    logic                    negate_angle_pipe_c [0:DIV_LAT];

    logic signed [ANG_W-1:0] base_angle_pipe      [0:DIV_LAT];
    logic signed [ANG_W-1:0] base_angle_pipe_c    [0:DIV_LAT];
    logic signed [ANG_W-1:0] special_angle_pipe   [0:DIV_LAT];
    logic signed [ANG_W-1:0] special_angle_pipe_c [0:DIV_LAT];

    logic                    valid_out_c;
    logic signed [ANG_W-1:0] angle_out_c;

    logic signed [WORK_W-1:0] x_ext;
    logic signed [WORK_W-1:0] y_ext;
    logic signed [WORK_W-1:0] abs_y;
    logic signed [WORK_W-1:0] abs_y_p1;
    logic signed [WORK_W-1:0] delta_num_base;
    logic signed [WORK_W-1:0] denom_signed;

    logic                    num_neg;
    logic [WORK_W-1:0]       numer_mag;
    logic [NUM_W-1:0]        numer_q;
    logic [DEN_W-1:0]        denom_u;

    logic signed [NUM_W:0]   r_signed_ext;
    logic signed [MUL_W-1:0] mult_full;
    logic signed [MUL_W-1:0] mult_deq;
    logic signed [MUL_W-1:0] angle_wide;

    div #(
        .NUM_W (NUM_W),
        .DEN_W (DEN_W),
        .QUOT_W(NUM_W)
    ) u_divider (
        .clk      (clk),
        .rst      (rst),
        .valid_in (div_valid_in),
        .numer_in (div_numer_in),
        .denom_in (div_denom_in),
        .valid_out(div_valid_out),
        .quot_out (div_quot_out)
    );

    always_comb begin
        div_valid_in = 1'b0;
        div_numer_in = '0;
        div_denom_in = '0;

        valid_out_c  = 1'b0;
        angle_out_c  = angle_out;

        x_ext          = '0;
        y_ext          = '0;
        abs_y          = '0;
        abs_y_p1       = '0;
        delta_num_base = '0;
        denom_signed   = '0;
        num_neg        = 1'b0;
        numer_mag      = '0;
        numer_q        = '0;
        denom_u        = '0;

        r_signed_ext   = '0;
        mult_full      = '0;
        mult_deq       = '0;
        angle_wide     = '0;

        for (int k = 0; k <= DIV_LAT; k++) begin
            num_neg_pipe_c[k]       = num_neg_pipe[k];
            special_pipe_c[k]       = special_pipe[k];
            negate_angle_pipe_c[k]  = negate_angle_pipe[k];
            base_angle_pipe_c[k]    = base_angle_pipe[k];
            special_angle_pipe_c[k] = special_angle_pipe[k];
        end

        for (int k = 0; k < DIV_LAT; k++) begin
            num_neg_pipe_c[k+1]       = num_neg_pipe[k];
            special_pipe_c[k+1]       = special_pipe[k];
            negate_angle_pipe_c[k+1]  = negate_angle_pipe[k];
            base_angle_pipe_c[k+1]    = base_angle_pipe[k];
            special_angle_pipe_c[k+1] = special_angle_pipe[k];
        end

        num_neg_pipe_c[0]       = 1'b0;
        special_pipe_c[0]       = 1'b0;
        negate_angle_pipe_c[0]  = 1'b0;
        base_angle_pipe_c[0]    = '0;
        special_angle_pipe_c[0] = '0;

        if (valid_in) begin
            x_ext = $signed({{(WORK_W-INPUT_W){x_in[INPUT_W-1]}}, x_in});
            y_ext = $signed({{(WORK_W-INPUT_W){y_in[INPUT_W-1]}}, y_in});

            if (y_ext < 0) abs_y = -y_ext;
            else           abs_y = y_ext;

            abs_y_p1 = abs_y + 1;
            negate_angle_pipe_c[0] = (y_ext < 0);

            if (x_ext == 0) begin
                div_valid_in         = 1'b1;
                div_numer_in         = '0;
                div_denom_in         = {{(DEN_W-1){1'b0}}, 1'b1};

                special_pipe_c[0]    = 1'b1;
                base_angle_pipe_c[0] = '0;
                num_neg_pipe_c[0]    = 1'b0;

                if (y_ext > 0)      special_angle_pipe_c[0] = HALF_PI_Q;
                else if (y_ext < 0) special_angle_pipe_c[0] = -HALF_PI_Q;
                else                special_angle_pipe_c[0] = '0;
            end else begin
                if (x_ext >= 0) begin
                    delta_num_base       = x_ext - abs_y_p1;
                    denom_signed         = x_ext + abs_y_p1;
                    base_angle_pipe_c[0] = QUAD1_Q;
                end else begin
                    delta_num_base       = x_ext + abs_y_p1;
                    denom_signed         = abs_y_p1 - x_ext;
                    base_angle_pipe_c[0] = QUAD3_Q;
                end

                num_neg = (delta_num_base < 0);
                num_neg_pipe_c[0] = num_neg;

                if (delta_num_base < 0) numer_mag = -delta_num_base;
                else                    numer_mag = delta_num_base;

                numer_q = {{(NUM_W-WORK_W){1'b0}}, numer_mag} << BITS;
                denom_u = denom_signed[DEN_W-1:0];

                div_valid_in = 1'b1;
                div_numer_in = numer_q;
                div_denom_in = denom_u;
            end
        end

        if (div_valid_out) begin
            if (special_pipe[DIV_LAT]) begin
                angle_out_c = special_angle_pipe[DIV_LAT];
            end else begin
                if (num_neg_pipe[DIV_LAT])
                    r_signed_ext = -$signed({1'b0, div_quot_out});
                else
                    r_signed_ext =  $signed({1'b0, div_quot_out});

                mult_full  = $signed(QUAD1_Q) * $signed(r_signed_ext);
                mult_deq   = trunc_div_pow2(mult_full);
                angle_wide = $signed(base_angle_pipe[DIV_LAT]) - mult_deq;

                if (negate_angle_pipe[DIV_LAT])
                    angle_wide = -angle_wide;

                angle_out_c = angle_wide[ANG_W-1:0];
            end

            valid_out_c = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            angle_out <= '0;

            for (int k = 0; k <= DIV_LAT; k++) begin
                num_neg_pipe[k]       <= 1'b0;
                special_pipe[k]       <= 1'b0;
                negate_angle_pipe[k]  <= 1'b0;
                base_angle_pipe[k]    <= '0;
                special_angle_pipe[k] <= '0;
            end
        end else begin
            valid_out <= valid_out_c;
            angle_out <= angle_out_c;

            for (int k = 0; k <= DIV_LAT; k++) begin
                num_neg_pipe[k]       <= num_neg_pipe_c[k];
                special_pipe[k]       <= special_pipe_c[k];
                negate_angle_pipe[k]  <= negate_angle_pipe_c[k];
                base_angle_pipe[k]    <= base_angle_pipe_c[k];
                special_angle_pipe[k] <= special_angle_pipe_c[k];
            end
        end
    end

endmodule