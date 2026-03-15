/*
Unsigned pipelined restoring divider
- one quotient bit per stage
- accepts one input per cycle
- no use of / operator
- quotient width = numerator width
*/

module div #(
    parameter int NUM_W  = 45,
    parameter int DEN_W  = 35,
    parameter int QUOT_W = NUM_W
) (
    input  logic              clk,
    input  logic              rst,
    input  logic              valid_in,
    input  logic [NUM_W-1:0]  numer_in,
    input  logic [DEN_W-1:0]  denom_in,
    output logic              valid_out,
    output logic [QUOT_W-1:0] quot_out
);

    logic [NUM_W-1:0]  dividend_pipe   [0:NUM_W];
    logic [DEN_W:0]    rem_pipe        [0:NUM_W];
    logic [DEN_W-1:0]  denom_pipe      [0:NUM_W];
    logic [QUOT_W-1:0] quot_pipe       [0:NUM_W];
    logic              valid_pipe      [0:NUM_W];

    logic [NUM_W-1:0]  dividend_pipe_c [0:NUM_W];
    logic [DEN_W:0]    rem_pipe_c      [0:NUM_W];
    logic [DEN_W-1:0]  denom_pipe_c    [0:NUM_W];
    logic [QUOT_W-1:0] quot_pipe_c     [0:NUM_W];
    logic              valid_pipe_c    [0:NUM_W];

    logic [DEN_W:0] rem_trial;
    logic [DEN_W:0] denom_ext;

    always_comb begin
        for (int s = 0; s <= NUM_W; s++) begin
            dividend_pipe_c[s] = dividend_pipe[s];
            rem_pipe_c[s]      = rem_pipe[s];
            denom_pipe_c[s]    = denom_pipe[s];
            quot_pipe_c[s]     = quot_pipe[s];
            valid_pipe_c[s]    = valid_pipe[s];
        end

        dividend_pipe_c[0] = numer_in;
        rem_pipe_c[0]      = '0;
        denom_pipe_c[0]    = denom_in;
        quot_pipe_c[0]     = '0;
        valid_pipe_c[0]    = valid_in;

        for (int s = 0; s < NUM_W; s++) begin
            valid_pipe_c[s+1]    = valid_pipe[s];
            denom_pipe_c[s+1]    = denom_pipe[s];
            dividend_pipe_c[s+1] = {dividend_pipe[s][NUM_W-2:0], 1'b0};

            rem_trial = {rem_pipe[s][DEN_W-1:0], dividend_pipe[s][NUM_W-1]};
            denom_ext = {1'b0, denom_pipe[s]};

            if (valid_pipe[s]) begin
                if ((denom_pipe[s] != '0) && (rem_trial >= denom_ext)) begin
                    rem_pipe_c[s+1]  = rem_trial - denom_ext;
                    quot_pipe_c[s+1] = {quot_pipe[s][QUOT_W-2:0], 1'b1};
                end else begin
                    rem_pipe_c[s+1]  = rem_trial;
                    quot_pipe_c[s+1] = {quot_pipe[s][QUOT_W-2:0], 1'b0};
                end
            end else begin
                rem_pipe_c[s+1]  = '0;
                quot_pipe_c[s+1] = '0;
            end
        end

        valid_out = valid_pipe[NUM_W];
        quot_out  = quot_pipe[NUM_W];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int s = 0; s <= NUM_W; s++) begin
                dividend_pipe[s] <= '0;
                rem_pipe[s]      <= '0;
                denom_pipe[s]    <= '0;
                quot_pipe[s]     <= '0;
                valid_pipe[s]    <= 1'b0;
            end
        end else begin
            for (int s = 0; s <= NUM_W; s++) begin
                dividend_pipe[s] <= dividend_pipe_c[s];
                rem_pipe[s]      <= rem_pipe_c[s];
                denom_pipe[s]    <= denom_pipe_c[s];
                quot_pipe[s]     <= quot_pipe_c[s];
                valid_pipe[s]    <= valid_pipe_c[s];
            end
        end
    end

endmodule