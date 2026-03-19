`timescale 1ns/1ps
import fm_radio_pkg::*;

// ============================================================
// Read raw byte stream: I_lo, I_hi, Q_lo, Q_hi -> 32-bit quantized I/Q
// ============================================================
module read_iq (
    input  logic               clk,
    input  logic               rst,

    input  logic [7:0]         in_byte,
    input  logic               in_valid,
    output logic               in_ready,

    output logic signed [31:0] out_i,
    output logic signed [31:0] out_q,
    output logic               out_valid,
    input  logic               out_ready
);
    typedef enum logic [2:0] {
        ST_B0,
        ST_B1,
        ST_B2,
        ST_B3,
        ST_HOLD
    } state_t;

    state_t state, state_n;

    logic [7:0] i_lo_r, i_lo_n;
    logic [7:0] i_hi_r, i_hi_n;
    logic [7:0] q_lo_r, q_lo_n;

    logic signed [31:0] out_i_r, out_i_n;
    logic signed [31:0] out_q_r, out_q_n;

    logic signed [15:0] i_short_now;
    logic signed [15:0] q_short_now;

    assign i_short_now = $signed({i_hi_r, i_lo_r});
    assign q_short_now = $signed({in_byte, q_lo_r});

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= ST_B0;
            i_lo_r  <= '0;
            i_hi_r  <= '0;
            q_lo_r  <= '0;
            out_i_r <= '0;
            out_q_r <= '0;
        end else begin
            state   <= state_n;
            i_lo_r  <= i_lo_n;
            i_hi_r  <= i_hi_n;
            q_lo_r  <= q_lo_n;
            out_i_r <= out_i_n;
            out_q_r <= out_q_n;
        end
    end

    always_comb begin
        state_n = state;
        i_lo_n  = i_lo_r;
        i_hi_n  = i_hi_r;
        q_lo_n  = q_lo_r;
        out_i_n = out_i_r;
        out_q_n = out_q_r;

        in_ready  = 1'b0;
        out_valid = 1'b0;
        out_i     = out_i_r;
        out_q     = out_q_r;

        case (state)
            ST_B0: begin
                in_ready = 1'b1;
                if (in_valid) begin
                    i_lo_n  = in_byte;
                    state_n = ST_B1;
                end
            end

            ST_B1: begin
                in_ready = 1'b1;
                if (in_valid) begin
                    i_hi_n  = in_byte;
                    state_n = ST_B2;
                end
            end

            ST_B2: begin
                in_ready = 1'b1;
                if (in_valid) begin
                    q_lo_n  = in_byte;
                    state_n = ST_B3;
                end
            end

            ST_B3: begin
                in_ready = 1'b1;
                if (in_valid) begin
                    out_i_n = $signed(i_short_now) <<< BITS;
                    out_q_n = $signed(q_short_now) <<< BITS;
                    state_n = ST_HOLD;
                end
            end

            ST_HOLD: begin
                out_valid = 1'b1;
                out_i     = out_i_r;
                out_q     = out_q_r;
                if (out_ready)
                    state_n = ST_B0;
            end

            default: begin
                state_n = ST_B0;
            end
        endcase
    end
endmodule