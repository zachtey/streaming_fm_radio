`timescale 1ns/1ps

module iir #(
    parameter int DATA_W      = 32,
    parameter int COEFF_W     = 32,
    parameter int TAPS        = 2,
    parameter int SCALE_SHIFT = 10,

    parameter logic signed [COEFF_W-1:0] X_COEFFS [0:TAPS-1] = '{default:'0},
    parameter logic signed [COEFF_W-1:0] Y_COEFFS [0:TAPS-1] = '{default:'0}
) (
    input  logic                      clock,
    input  logic                      reset,

    output logic                      in_rd_en,
    input  logic                      in_empty,
    input  logic signed [DATA_W-1:0]  in_dout,

    output logic                      out_wr_en,
    input  logic                      out_full,
    output logic signed [DATA_W-1:0]  out_din
);

    localparam int PROD_W = DATA_W + COEFF_W;

    typedef enum logic [1:0] {
        ST_WAIT,
        ST_CALC,
        ST_SEND
    } state_t;

    state_t curr_state, next_state;

    logic signed [DATA_W-1:0] sample_reg, sample_next;
    logic signed [DATA_W-1:0] out_reg,    out_next;

    logic signed [DATA_W-1:0] x_hist [0:TAPS-1];
    logic signed [DATA_W-1:0] y_hist [0:TAPS-1];

    logic signed [DATA_W-1:0] x_hist_next [0:TAPS-1];
    logic signed [DATA_W-1:0] y_hist_next [0:TAPS-1];

    logic signed [DATA_W-1:0] x_work [0:TAPS-1];
    logic signed [DATA_W-1:0] y_work [0:TAPS-1];

    logic signed [DATA_W-1:0] ff_sum;
    logic signed [DATA_W-1:0] fb_sum;
    logic signed [DATA_W-1:0] y_new0;

    function automatic logic signed [DATA_W-1:0] trunc_div_pow2;
        input logic signed [PROD_W-1:0] val;
        logic signed [PROD_W-1:0] bias;
        begin
            if (SCALE_SHIFT == 0) begin
                trunc_div_pow2 = val[DATA_W-1:0];
            end else begin
                if (val < 0)
                    bias = ({{(PROD_W-1){1'b0}},1'b1} <<< SCALE_SHIFT) - 1;
                else
                    bias = '0;

                trunc_div_pow2 = (val + bias) >>> SCALE_SHIFT;
            end
        end
    endfunction

    always_ff @(posedge clock or posedge reset) begin
        integer i;
        if (reset) begin
            curr_state <= ST_WAIT;
            sample_reg <= '0;
            out_reg    <= '0;

            for (i = 0; i < TAPS; i = i + 1) begin
                x_hist[i] <= '0;
                y_hist[i] <= '0;
            end
        end
        else begin
            curr_state <= next_state;
            sample_reg <= sample_next;
            out_reg    <= out_next;

            for (i = 0; i < TAPS; i = i + 1) begin
                x_hist[i] <= x_hist_next[i];
                y_hist[i] <= y_hist_next[i];
            end
        end
    end

    always_comb begin
        integer j;

        next_state = curr_state;
        sample_next = sample_reg;
        out_next    = out_reg;

        for (j = 0; j < TAPS; j = j + 1) begin
            x_hist_next[j] = x_hist[j];
            y_hist_next[j] = y_hist[j];
            x_work[j]      = x_hist[j];
            y_work[j]      = y_hist[j];
        end

        in_rd_en   = 1'b0;
        out_wr_en  = 1'b0;
        out_din    = out_reg;

        ff_sum = '0;
        fb_sum = '0;
        y_new0 = '0;

        case (curr_state)
            ST_WAIT: begin
                if (!in_empty) begin
                    sample_next = in_dout;
                    in_rd_en    = 1'b1;
                    next_state  = ST_CALC;
                end
            end

            ST_CALC: begin
                // shift/build x history like C
                x_work[0] = sample_reg;
                for (j = 1; j < TAPS; j = j + 1) begin
                    x_work[j] = x_hist[j-1];
                end

                // shift/build y history like C
                y_work[0] = y_hist[0];
                for (j = 1; j < TAPS; j = j + 1) begin
                    y_work[j] = y_hist[j-1];
                end

                // accumulate
                for (j = 0; j < TAPS; j = j + 1) begin
                    ff_sum = ff_sum
                           + trunc_div_pow2($signed(X_COEFFS[j]) * $signed(x_work[j]));
                    fb_sum = fb_sum
                           + trunc_div_pow2($signed(Y_COEFFS[j]) * $signed(y_work[j]));
                end

                y_new0 = ff_sum + fb_sum;

                x_hist_next[0] = x_work[0];
                for (j = 1; j < TAPS; j = j + 1) begin
                    x_hist_next[j] = x_work[j];
                end

                y_hist_next[0] = y_new0;
                for (j = 1; j < TAPS; j = j + 1) begin
                    y_hist_next[j] = y_work[j];
                end

                // match C: output y[taps-1] after update
                out_next   = (TAPS == 1) ? y_new0 : y_work[TAPS-1];
                next_state = ST_SEND;
            end

            ST_SEND: begin
                if (!out_full) begin
                    out_wr_en = 1'b1;
                    out_din   = out_reg;
                    next_state = ST_WAIT;
                end
            end

            default: begin
                next_state = ST_WAIT;
            end
        endcase
    end

endmodule


