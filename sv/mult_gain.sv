`timescale 1ns/1ps

module mult_gain #(
    parameter int DATA_W      = 32,
    parameter int BITS        = 10,
    parameter int POST_SHIFT  = 0
) (
    input  logic                      clock,
    input  logic                      reset,

    output logic                      in_a_rd_en,
    input  logic                      in_a_empty,
    input  logic signed [DATA_W-1:0]  in_a_dout,

    output logic                      in_b_rd_en,
    input  logic                      in_b_empty,
    input  logic signed [DATA_W-1:0]  in_b_dout,

    output logic                      out_wr_en,
    input  logic                      out_full,
    output logic signed [DATA_W-1:0]  out_din
);

    typedef enum logic [1:0] {
        ST_FETCH,
        ST_CALC,
        ST_PUSH
    } state_t;

    state_t curr_state, next_state;

    logic signed [DATA_W-1:0] a_reg, a_next;
    logic signed [DATA_W-1:0] b_reg, b_next;
    logic signed [DATA_W-1:0] y_reg, y_next;

    logic signed [63:0] raw_prod;
    logic signed [63:0] biased_prod;
    logic signed [63:0] deq_val;
    logic signed [63:0] shifted_val;

    function automatic logic signed [DATA_W-1:0] trunc_div_pow2;
        input logic signed [63:0] val;
        logic signed [63:0] bias;
        begin
            if (BITS == 0) begin
                trunc_div_pow2 = val[DATA_W-1:0];
            end else begin
                if (val < 0)
                    bias = (64'sd1 <<< BITS) - 1;
                else
                    bias = 64'sd0;

                trunc_div_pow2 = (val + bias) >>> BITS;
            end
        end
    endfunction

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            curr_state <= ST_FETCH;
            a_reg      <= '0;
            b_reg      <= '0;
            y_reg      <= '0;
        end else begin
            curr_state <= next_state;
            a_reg      <= a_next;
            b_reg      <= b_next;
            y_reg      <= y_next;
        end
    end

    always_comb begin
        next_state = curr_state;
        a_next     = a_reg;
        b_next     = b_reg;
        y_next     = y_reg;

        in_a_rd_en = 1'b0;
        in_b_rd_en = 1'b0;
        out_wr_en  = 1'b0;
        out_din    = y_reg;

        raw_prod    = $signed(a_reg) * $signed(b_reg);
        deq_val     = trunc_div_pow2(raw_prod);
        shifted_val = deq_val <<< POST_SHIFT;

        case (curr_state)
            ST_FETCH: begin
                if (!in_a_empty && !in_b_empty) begin
                    a_next     = in_a_dout;
                    b_next     = in_b_dout;
                    in_a_rd_en = 1'b1;
                    in_b_rd_en = 1'b1;
                    next_state = ST_CALC;
                end
            end

            ST_CALC: begin
                y_next     = shifted_val[DATA_W-1:0];
                next_state = ST_PUSH;
            end

            ST_PUSH: begin
                if (!out_full) begin
                    out_wr_en  = 1'b1;
                    out_din    = y_reg;
                    next_state = ST_FETCH;
                end
            end

            default: begin
                next_state = ST_FETCH;
            end
        endcase
    end

endmodule