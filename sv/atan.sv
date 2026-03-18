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

    localparam int DIV_LAT = 32;

    // Q10 constants
    localparam logic signed [31:0] QUAD1_Q = 32'sd804;   // QUANTIZE_F(pi/4)
    localparam logic signed [31:0] QUAD3_Q = 32'sd2413;  // QUANTIZE_F(3pi/4)

    // ------------------------------------------------------------
    // Inline functions matching C macros / behavior
    // ------------------------------------------------------------
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

    // divider I/O
    logic        div_valid_in;
    logic [31:0] div_numer_in;
    logic [31:0] div_denom_in;
    logic        div_valid_out;
    logic [31:0] div_quot_out;

    // metadata pipeline aligned to divider latency
    logic               r_neg_pipe      [0:DIV_LAT];
    logic               r_neg_pipe_c    [0:DIV_LAT];
    logic               negate_pipe     [0:DIV_LAT];
    logic               negate_pipe_c   [0:DIV_LAT];
    logic signed [31:0] base_pipe       [0:DIV_LAT];
    logic signed [31:0] base_pipe_c     [0:DIV_LAT];

    // outputs next-state
    logic               valid_out_c;
    logic signed [31:0] angle_out_c;

    // temps
    logic signed [31:0] x32, y32;
    logic signed [31:0] abs_y;
    logic signed [31:0] abs_y_p1;
    logic signed [31:0] delta;
    logic signed [31:0] denom_s;
    logic               r_neg;
    logic [31:0]        numer_mag;
    logic [31:0]        denom_u;
    logic signed [31:0] r_signed;
    logic signed [31:0] mult32;
    logic signed [31:0] mult_deq32;
    logic signed [31:0] angle32;

    div #(
        .W(32)
    ) u_div (
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
        div_numer_in = 32'd0;
        div_denom_in = 32'd0;

        valid_out_c  = 1'b0;
        angle_out_c  = angle_out;

        x32        = x_in;
        y32        = y_in;
        abs_y      = 32'sd0;
        abs_y_p1   = 32'sd0;
        delta      = 32'sd0;
        denom_s    = 32'sd0;
        r_neg      = 1'b0;
        numer_mag  = 32'd0;
        denom_u    = 32'd0;
        r_signed   = 32'sd0;
        mult32     = 32'sd0;
        mult_deq32 = 32'sd0;
        angle32    = 32'sd0;

        for (int k = 0; k <= DIV_LAT; k++) begin
            r_neg_pipe_c[k]  = r_neg_pipe[k];
            negate_pipe_c[k] = negate_pipe[k];
            base_pipe_c[k]   = base_pipe[k];
        end

        for (int k = 0; k < DIV_LAT; k++) begin
            r_neg_pipe_c[k+1]  = r_neg_pipe[k];
            negate_pipe_c[k+1] = negate_pipe[k];
            base_pipe_c[k+1]   = base_pipe[k];
        end

        r_neg_pipe_c[0]  = 1'b0;
        negate_pipe_c[0] = (y32 < 0);
        base_pipe_c[0]   = 32'sd0;

        // abs_y = abs(y) + 1
        if (y32 < 0)
            abs_y = -y32;
        else
            abs_y = y32;

        abs_y_p1 = abs_y + 32'sd1;

        if (valid_in) begin
            if (x32 >= 0) begin
                delta          = x32 - abs_y_p1;
                denom_s        = x32 + abs_y_p1;
                base_pipe_c[0] = QUAD1_Q;
            end else begin
                delta          = x32 + abs_y_p1;
                denom_s        = abs_y_p1 - x32;
                base_pipe_c[0] = QUAD3_Q;
            end

            r_neg = (delta < 0);
            r_neg_pipe_c[0] = r_neg;

            if (delta < 0)
                numer_mag = -delta;
            else
                numer_mag = delta;

            div_numer_in = quantize_i32($signed(numer_mag));
            div_denom_in = denom_s[31:0];
            div_valid_in = 1'b1;
        end

        if (div_valid_out) begin
            if (r_neg_pipe[DIV_LAT])
                r_signed = -$signed(div_quot_out);
            else
                r_signed =  $signed(div_quot_out);

            // C int multiplication is 32-bit int behavior
            mult32     = $signed(QUAD1_Q) * $signed(r_signed);
            mult_deq32 = dequantize_i32(mult32);
            angle32    = base_pipe[DIV_LAT] - mult_deq32;

            if (negate_pipe[DIV_LAT])
                angle32 = -angle32;

            angle_out_c = angle32;
            valid_out_c = 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            angle_out <= 32'sd0;

            for (int k = 0; k <= DIV_LAT; k++) begin
                r_neg_pipe[k]  <= 1'b0;
                negate_pipe[k] <= 1'b0;
                base_pipe[k]   <= 32'sd0;
            end
        end else begin
            valid_out <= valid_out_c;
            angle_out <= angle_out_c;

            for (int k = 0; k <= DIV_LAT; k++) begin
                r_neg_pipe[k]  <= r_neg_pipe_c[k];
                negate_pipe[k] <= negate_pipe_c[k];
                base_pipe[k]   <= base_pipe_c[k];
            end
        end
    end

endmodule