`timescale 1ns/1ps
import fm_radio_pkg::*;

module add_sub (
    input  logic        clock,
    input  logic        reset,

    // Input A (audio_lpr)
    output logic        in_a_rd_en,
    input  logic        in_a_empty,
    input  logic signed [31:0] in_a_dout,

    // Input B (audio_lmr)
    output logic        in_b_rd_en,
    input  logic        in_b_empty,
    input  logic signed [31:0] in_b_dout,

    // Output Add (left = a + b)
    output logic        out_add_wr_en,
    input  logic        out_add_full,
    output logic signed [31:0] out_add_din,

    // Output Sub (right = a - b)
    output logic        out_sub_wr_en,
    input  logic        out_sub_full,
    output logic signed [31:0] out_sub_din
);

    typedef enum logic [1:0] {
        ST_FETCH,
        ST_PUSH
    } fsm_t;

    fsm_t curr_state, next_state;

    logic signed [31:0] sum_reg,  sum_next;
    logic signed [31:0] diff_reg, diff_next;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            curr_state <= ST_FETCH;
            sum_reg    <= 32'sd0;
            diff_reg   <= 32'sd0;
        end
        else begin
            curr_state <= next_state;
            sum_reg    <= sum_next;
            diff_reg   <= diff_next;
        end
    end

    always_comb begin
        next_state    = curr_state;
        sum_next      = sum_reg;
        diff_next     = diff_reg;

        in_a_rd_en    = 1'b0;
        in_b_rd_en    = 1'b0;
        out_add_wr_en = 1'b0;
        out_sub_wr_en = 1'b0;

        out_add_din   = sum_reg;
        out_sub_din   = diff_reg;

        unique case (curr_state)
            ST_FETCH: begin
                if ((in_a_empty == 1'b0) && (in_b_empty == 1'b0)) begin
                    sum_next   = in_a_dout + in_b_dout;
                    diff_next  = in_a_dout - in_b_dout;
                    in_a_rd_en = 1'b1;
                    in_b_rd_en = 1'b1;
                    next_state = ST_PUSH;
                end
            end

            ST_PUSH: begin
                if ((out_add_full == 1'b0) && (out_sub_full == 1'b0)) begin
                    out_add_wr_en = 1'b1;
                    out_sub_wr_en = 1'b1;
                    next_state    = ST_FETCH;
                end
            end

            default: begin
                next_state = ST_FETCH;
            end
        endcase
    end

endmodule