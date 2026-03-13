/*
atan2 via CORDIC, vectoring mode
- one always_comb
- one always_ff
- pipelined
- angle output is Q10 radians

*/

module atan #(
    parameter int INPUT_W = 33,
    parameter int ANG_W   = 32,
    parameter int BITS    = 10,
    parameter int ITER    = 11
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       valid_in,
    input  logic signed [INPUT_W-1:0]  x_in,
    input  logic signed [INPUT_W-1:0]  y_in,
    output logic                       valid_out,
    output logic signed [ANG_W-1:0]    angle_out
);

    //localparams
    localparam int XY_W = INPUT_W + 1;
    // Q10 radians
    localparam logic signed [ANG_W-1:0] PI_Q      = 32'sd3217;
    localparam logic signed [ANG_W-1:0] HALF_PI_Q = 32'sd1608;
    
    //local variables + variables
    // state registers
    logic signed [XY_W-1:0]  x_pipe   [0:ITER];
    logic signed [XY_W-1:0]  y_pipe   [0:ITER];
    logic signed [ANG_W-1:0] z_pipe   [0:ITER];
    logic                    valid_pipe[0:ITER];
    logic                    special_pipe[0:ITER];
    logic signed [ANG_W-1:0] special_angle_pipe[0:ITER];
    // next-state signals
    logic signed [XY_W-1:0]  x_pipe_c   [0:ITER];
    logic signed [XY_W-1:0]  y_pipe_c   [0:ITER];
    logic signed [ANG_W-1:0] z_pipe_c   [0:ITER];
    logic                    valid_pipe_c[0:ITER];
    logic                    special_pipe_c[0:ITER];
    logic signed [ANG_W-1:0] special_angle_pipe_c[0:ITER];

    integer k;
    function automatic logic signed [ANG_W-1:0] cordic_angle(input int idx);
        begin
            case (idx)
                0:  cordic_angle = 32'sd804; // atan(1)      * 1024
                1:  cordic_angle = 32'sd475; // atan(1/2)
                2:  cordic_angle = 32'sd251; // atan(1/4)
                3:  cordic_angle = 32'sd127; // atan(1/8)
                4:  cordic_angle = 32'sd64;
                5:  cordic_angle = 32'sd32;
                6:  cordic_angle = 32'sd16;
                7:  cordic_angle = 32'sd8;
                8:  cordic_angle = 32'sd4;
                9:  cordic_angle = 32'sd2;
                10: cordic_angle = 32'sd1;
                default: cordic_angle = '0;
            endcase
        end
    endfunction

    // combinational process
    always_comb begin
        // defaults: hold current state
        for (k = 0; k <= ITER; k = k + 1) begin
            x_pipe_c[k]             = x_pipe[k];
            y_pipe_c[k]             = y_pipe[k];
            z_pipe_c[k]             = z_pipe[k];
            valid_pipe_c[k]         = valid_pipe[k];
            special_pipe_c[k]       = special_pipe[k];
            special_angle_pipe_c[k] = special_angle_pipe[k];
        end

        // stage 0: load new input
        valid_pipe_c[0] = valid_in;

        if (valid_in) begin
            if (x_in == '0) begin
                x_pipe_c[0]       = '0;
                y_pipe_c[0]       = '0;
                z_pipe_c[0]       = '0;
                special_pipe_c[0] = 1'b1;

                if (y_in > 0)
                    special_angle_pipe_c[0] = HALF_PI_Q;
                else if (y_in < 0)
                    special_angle_pipe_c[0] = -HALF_PI_Q;
                else
                    special_angle_pipe_c[0] = '0;
            end else begin
                special_pipe_c[0]       = 1'b0;
                special_angle_pipe_c[0] = '0;

                // quadrant preprocessing
                if (x_in < 0) begin
                    x_pipe_c[0] = -$signed({x_in[INPUT_W-1], x_in});
                    y_pipe_c[0] = -$signed({y_in[INPUT_W-1], y_in});
                    z_pipe_c[0] = (y_in >= 0) ? PI_Q : -PI_Q;
                end else begin
                    x_pipe_c[0] = $signed({x_in[INPUT_W-1], x_in});
                    y_pipe_c[0] = $signed({y_in[INPUT_W-1], y_in});
                    z_pipe_c[0] = '0;
                end
            end
        end else begin
            x_pipe_c[0]             = '0;
            y_pipe_c[0]             = '0;
            z_pipe_c[0]             = '0;
            special_pipe_c[0]       = 1'b0;
            special_angle_pipe_c[0] = '0;
        end

        // stages 1..ITER
        for (k = 0; k < ITER; k = k + 1) begin
            valid_pipe_c[k+1]         = valid_pipe[k];
            special_pipe_c[k+1]       = special_pipe[k];
            special_angle_pipe_c[k+1] = special_angle_pipe[k];

            if (special_pipe[k]) begin
                x_pipe_c[k+1] = x_pipe[k];
                y_pipe_c[k+1] = y_pipe[k];
                z_pipe_c[k+1] = special_angle_pipe[k];
            end else if (valid_pipe[k]) begin
                if (y_pipe[k] >= 0) begin
                    x_pipe_c[k+1] = x_pipe[k] + (y_pipe[k] >>> k);
                    y_pipe_c[k+1] = y_pipe[k] - (x_pipe[k] >>> k);
                    z_pipe_c[k+1] = z_pipe[k] + cordic_angle(k);
                end else begin
                    x_pipe_c[k+1] = x_pipe[k] - (y_pipe[k] >>> k);
                    y_pipe_c[k+1] = y_pipe[k] + (x_pipe[k] >>> k);
                    z_pipe_c[k+1] = z_pipe[k] - cordic_angle(k);
                end
            end else begin
                x_pipe_c[k+1] = '0;
                y_pipe_c[k+1] = '0;
                z_pipe_c[k+1] = '0;
            end
        end

        valid_out = valid_pipe[ITER];
        angle_out = z_pipe[ITER];
    end

    // sequential process
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k <= ITER; k = k + 1) begin
                x_pipe[k]             <= '0;
                y_pipe[k]             <= '0;
                z_pipe[k]             <= '0;
                valid_pipe[k]         <= 1'b0;
                special_pipe[k]       <= 1'b0;
                special_angle_pipe[k] <= '0;
            end
        end else begin
            for (k = 0; k <= ITER; k = k + 1) begin
                x_pipe[k]             <= x_pipe_c[k];
                y_pipe[k]             <= y_pipe_c[k];
                z_pipe[k]             <= z_pipe_c[k];
                valid_pipe[k]         <= valid_pipe_c[k];
                special_pipe[k]       <= special_pipe_c[k];
                special_angle_pipe[k] <= special_angle_pipe_c[k];
            end
        end
    end

endmodule