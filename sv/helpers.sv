`timescale 1ns/1ps
import fm_radio_pkg::*;

module fir_fifo_wrap #(
    parameter int DATA_W      = 32,
    parameter int COEFF_W     = 32,
    parameter int ACC_W       = 48,
    parameter int TAPS        = 32,
    parameter int DECIM       = 1,
    parameter int SCALE_SHIFT = 10,
    parameter logic signed [COEFF_W-1:0] COEFFS [0:TAPS-1] = '{default:'0}
) (
    input  logic                     clock,
    input  logic                     reset,

    output logic                     in_rd_en,
    input  logic                     in_empty,
    input  logic signed [DATA_W-1:0] in_dout,

    output logic                     out_wr_en,
    input  logic                     out_full,
    output logic signed [DATA_W-1:0] out_din
);
    logic signed [DATA_W-1:0] s_axis_tdata;
    logic                     s_axis_tvalid;
    logic                     s_axis_tready;
    logic                     s_axis_tlast;

    logic signed [DATA_W-1:0] m_axis_tdata;
    logic                     m_axis_tvalid;
    logic                     m_axis_tready;
    logic                     m_axis_tlast;

    assign s_axis_tdata  = in_dout;
    assign s_axis_tvalid = !in_empty;
    assign s_axis_tlast  = 1'b0;
    assign in_rd_en      = (!in_empty) && s_axis_tready;

    assign m_axis_tready = !out_full;
    assign out_wr_en     = m_axis_tvalid && !out_full;
    assign out_din       = m_axis_tdata;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(DECIM),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFFS(COEFFS)
    ) u_fir (
        .clk          (clock),
        .rst_n        (~reset),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );
endmodule

// ============================================================
// First stage: paired channel FIR on quantized 32-bit I/Q
// ============================================================
module channel_fir_pair (
    input  logic               clk,
    input  logic               rst,

    input  logic signed [31:0] in_i,
    input  logic signed [31:0] in_q,
    input  logic               in_valid,
    output logic               in_ready,

    output logic signed [31:0] out_i,
    output logic signed [31:0] out_q,
    output logic               out_valid,
    input  logic               out_ready
);
    logic i_ready, q_ready;
    logic i_valid, q_valid;
    logic i_last,  q_last;

    assign in_ready  = i_ready & q_ready;
    assign out_valid = i_valid & q_valid;

    fir #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(CHANNEL_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(CHANNEL_COEFFS_REAL)
    ) u_fir_i (
        .clk          (clk),
        .rst_n        (~rst),
        .s_axis_tdata (in_i),
        .s_axis_tvalid(in_valid),
        .s_axis_tready(i_ready),
        .s_axis_tlast (1'b0),
        .m_axis_tdata (out_i),
        .m_axis_tvalid(i_valid),
        .m_axis_tready(out_ready),
        .m_axis_tlast (i_last)
    );

    fir #(
        .DATA_W(32),
        .COEFF_W(32),
        .ACC_W(48),
        .TAPS(CHANNEL_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(CHANNEL_COEFFS_REAL)
    ) u_fir_q (
        .clk          (clk),
        .rst_n        (~rst),
        .s_axis_tdata (in_q),
        .s_axis_tvalid(in_valid),
        .s_axis_tready(q_ready),
        .s_axis_tlast (1'b0),
        .m_axis_tdata (out_q),
        .m_axis_tvalid(q_valid),
        .m_axis_tready(out_ready),
        .m_axis_tlast (q_last)
    );
endmodule

// ============================================================
// Wrap demod into valid/ready stream
// ============================================================
module demod_axis_wrap (
    input  logic               clk,
    input  logic               rst,

    input  logic               in_valid,
    output logic               in_ready,
    input  logic signed [31:0] in_i,
    input  logic signed [31:0] in_q,

    output logic               out_valid,
    input  logic               out_ready,
    output logic signed [31:0] out_data
);
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_BUSY,
        ST_HOLD
    } state_t;

    state_t state, state_n;

    logic signed [31:0] out_reg, out_reg_n;
    logic               fire_demod;

    logic signed [31:0] demod_out_i;
    logic               demod_out_valid;

    demod u_demod (
        .clk            (clk),
        .rst            (rst),
        .valid_in       (fire_demod),
        .i_in           (in_i),
        .q_in           (in_q),
        .demod_out      (demod_out_i),
        .demod_valid_out(demod_out_valid)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= ST_IDLE;
            out_reg <= '0;
        end else begin
            state   <= state_n;
            out_reg <= out_reg_n;
        end
    end

    always_comb begin
        state_n    = state;
        out_reg_n  = out_reg;
        fire_demod = 1'b0;

        in_ready  = 1'b0;
        out_valid = 1'b0;
        out_data  = out_reg;

        case (state)
            ST_IDLE: begin
                in_ready = 1'b1;
                if (in_valid) begin
                    fire_demod = 1'b1;
                    state_n    = ST_BUSY;
                end
            end

            ST_BUSY: begin
                if (demod_out_valid) begin
                    out_reg_n = demod_out_i;
                    state_n   = ST_HOLD;
                end
            end

            ST_HOLD: begin
                out_valid = 1'b1;
                out_data  = out_reg;
                if (out_ready)
                    state_n = ST_IDLE;
            end

            default: begin
                state_n = ST_IDLE;
            end
        endcase
    end
endmodule


// ============================================================
// Simple synchronous FIFO with visible head element
// ============================================================
module sync_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 64
) (
    input  logic             clk,
    input  logic             rst,

    input  logic             wr_en,
    input  logic [WIDTH-1:0] din,
    output logic             full,

    input  logic             rd_en,
    output logic [WIDTH-1:0] dout,
    output logic             empty
);
    localparam int ADDR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_W-1:0] rd_ptr, wr_ptr;
    logic [ADDR_W:0]   count;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);
    assign dout  = mem[rd_ptr];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            count  <= '0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : (wr_ptr + 1'b1);
                    count  <= count + 1'b1;
                end
                2'b01: begin
                    rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : (rd_ptr + 1'b1);
                    count  <= count - 1'b1;
                end
                2'b11: begin
                    mem[wr_ptr] <= din;
                    wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : (wr_ptr + 1'b1);
                    rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : (rd_ptr + 1'b1);
                end
                default: begin
                end
            endcase
        end
    end
endmodule

