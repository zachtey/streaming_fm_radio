`timescale 1ns/1ps
import fm_radio_pkg::*;

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

// ============================================================
// Wrap AXI-style FIR as FIFO-style block
// ============================================================
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
// Core FM radio pipeline
// ============================================================
module fm_radio (
    input  logic               clock,
    input  logic               reset,

    input  logic signed [31:0] in_i,
    input  logic signed [31:0] in_q,
    input  logic               in_valid,
    output logic               in_ready,

    output logic signed [31:0] out_left,
    output logic signed [31:0] out_right,
    output logic               out_valid,
    input  logic               out_ready
);
    logic               ch_valid, ch_ready;
    logic signed [31:0] ch_i, ch_q;

    logic               demod_valid, demod_ready;
    logic signed [31:0] demod_data;

    logic demod_lpr_full, demod_lpr_empty, demod_lpr_rd_en;
    logic demod_lmr_full, demod_lmr_empty, demod_lmr_rd_en;
    logic demod_pil_full, demod_pil_empty, demod_pil_rd_en;

    logic signed [31:0] demod_lpr_dout;
    logic signed [31:0] demod_lmr_dout;
    logic signed [31:0] demod_pil_dout;

    logic lpr_wr_en, lpr_full, lpr_empty, lpr_rd_en;
    logic bplmr_wr_en, bplmr_full, bplmr_empty, bplmr_rd_en;
    logic pilot_wr_en, pilot_full, pilot_empty, pilot_rd_en;

    logic signed [31:0] lpr_din, lpr_dout;
    logic signed [31:0] bplmr_din, bplmr_dout;
    logic signed [31:0] pilot_din, pilot_dout;

    logic sq_wr_en, sq_full, sq_empty, sq_rd_en;
    logic signed [31:0] sq_din, sq_dout;
    logic sq_a_rd_en, sq_b_rd_en;

    logic hp_wr_en, hp_full, hp_empty, hp_rd_en;
    logic signed [31:0] hp_din, hp_dout;

    logic mult_wr_en, mult_full, mult_empty, mult_rd_en;
    logic signed [31:0] mult_din, mult_dout;
    logic mult_a_rd_en, mult_b_rd_en;

    logic lmr_wr_en, lmr_full, lmr_empty, lmr_rd_en;
    logic signed [31:0] lmr_din, lmr_dout;

    logic add_wr_en, add_full, add_empty, add_rd_en;
    logic sub_wr_en, sub_full, sub_empty, sub_rd_en;
    logic signed [31:0] add_din, add_dout;
    logic signed [31:0] sub_din, sub_dout;

    logic lde_wr_en, lde_full, lde_empty, lde_rd_en;
    logic rde_wr_en, rde_full, rde_empty, rde_rd_en;
    logic signed [31:0] lde_din, lde_dout;
    logic signed [31:0] rde_din, rde_dout;

    logic lg_wr_en, lg_full, lg_empty, lg_rd_en;
    logic rg_wr_en, rg_full, rg_empty, rg_rd_en;
    logic signed [31:0] lg_din, lg_dout;
    logic signed [31:0] rg_din, rg_dout;
    logic lg_a_rd_en, lg_b_rd_en;
    logic rg_a_rd_en, rg_b_rd_en;

    // explicit merge wiring around add_sub
    logic addsub_in_a_rd_en;
    logic addsub_in_b_rd_en;
    logic addsub_in_a_empty;
    logic addsub_in_b_empty;
    logic signed [31:0] addsub_in_a_dout;
    logic signed [31:0] addsub_in_b_dout;

    channel_fir_pair u_channel (
        .clk      (clock),
        .rst      (reset),
        .in_i     (in_i),
        .in_q     (in_q),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .out_i    (ch_i),
        .out_q    (ch_q),
        .out_valid(ch_valid),
        .out_ready(ch_ready)
    );

    demod_axis_wrap u_demod (
        .clk      (clock),
        .rst      (reset),
        .in_valid (ch_valid),
        .in_ready (ch_ready),
        .in_i     (ch_i),
        .in_q     (ch_q),
        .out_valid(demod_valid),
        .out_ready(demod_ready),
        .out_data (demod_data)
    );

    assign demod_ready = !demod_lpr_full && !demod_lmr_full && !demod_pil_full;

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_demod_lpr (
        .clk(clock), .rst(reset),
        .wr_en(demod_valid && demod_ready),
        .din(demod_data),
        .full(demod_lpr_full),
        .rd_en(demod_lpr_rd_en),
        .dout(demod_lpr_dout),
        .empty(demod_lpr_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_demod_lmr (
        .clk(clock), .rst(reset),
        .wr_en(demod_valid && demod_ready),
        .din(demod_data),
        .full(demod_lmr_full),
        .rd_en(demod_lmr_rd_en),
        .dout(demod_lmr_dout),
        .empty(demod_lmr_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_demod_pilot (
        .clk(clock), .rst(reset),
        .wr_en(demod_valid && demod_ready),
        .din(demod_data),
        .full(demod_pil_full),
        .rd_en(demod_pil_rd_en),
        .dout(demod_pil_dout),
        .empty(demod_pil_empty)
    );

    fir_fifo_wrap #(
        .DATA_W(32), .COEFF_W(32), .ACC_W(48),
        .TAPS(AUDIO_LPR_COEFF_TAPS),
        .DECIM(AUDIO_DECIM),
        .SCALE_SHIFT(BITS),
        .COEFFS(AUDIO_LPR_COEFFS)
    ) u_lpr (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (demod_lpr_rd_en),
        .in_empty (demod_lpr_empty),
        .in_dout  (demod_lpr_dout),
        .out_wr_en(lpr_wr_en),
        .out_full (lpr_full),
        .out_din  (lpr_din)
    );

    fir_fifo_wrap #(
        .DATA_W(32), .COEFF_W(32), .ACC_W(48),
        .TAPS(BP_LMR_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(BP_LMR_COEFFS)
    ) u_bp_lmr (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (demod_lmr_rd_en),
        .in_empty (demod_lmr_empty),
        .in_dout  (demod_lmr_dout),
        .out_wr_en(bplmr_wr_en),
        .out_full (bplmr_full),
        .out_din  (bplmr_din)
    );

    fir_fifo_wrap #(
        .DATA_W(32), .COEFF_W(32), .ACC_W(48),
        .TAPS(BP_PILOT_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(BP_PILOT_COEFFS)
    ) u_bp_pilot (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (demod_pil_rd_en),
        .in_empty (demod_pil_empty),
        .in_dout  (demod_pil_dout),
        .out_wr_en(pilot_wr_en),
        .out_full (pilot_full),
        .out_din  (pilot_din)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_lpr (
        .clk(clock), .rst(reset),
        .wr_en(lpr_wr_en), .din(lpr_din), .full(lpr_full),
        .rd_en(lpr_rd_en), .dout(lpr_dout), .empty(lpr_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_bplmr (
        .clk(clock), .rst(reset),
        .wr_en(bplmr_wr_en), .din(bplmr_din), .full(bplmr_full),
        .rd_en(bplmr_rd_en), .dout(bplmr_dout), .empty(bplmr_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_pilot (
        .clk(clock), .rst(reset),
        .wr_en(pilot_wr_en), .din(pilot_din), .full(pilot_full),
        .rd_en(pilot_rd_en), .dout(pilot_dout), .empty(pilot_empty)
    );

    mult_gain #(
        .DATA_W(32),
        .BITS(BITS),
        .POST_SHIFT(0)
    ) u_square (
        .clock       (clock),
        .reset       (reset),
        .in_a_rd_en  (sq_a_rd_en),
        .in_a_empty  (pilot_empty),
        .in_a_dout   (pilot_dout),
        .in_b_rd_en  (sq_b_rd_en),
        .in_b_empty  (pilot_empty),
        .in_b_dout   (pilot_dout),
        .out_wr_en   (sq_wr_en),
        .out_full    (sq_full),
        .out_din     (sq_din)
    );

    assign pilot_rd_en = sq_a_rd_en & sq_b_rd_en;

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_sq (
        .clk(clock), .rst(reset),
        .wr_en(sq_wr_en), .din(sq_din), .full(sq_full),
        .rd_en(sq_rd_en), .dout(sq_dout), .empty(sq_empty)
    );

    fir_fifo_wrap #(
        .DATA_W(32), .COEFF_W(32), .ACC_W(48),
        .TAPS(HP_COEFF_TAPS),
        .DECIM(1),
        .SCALE_SHIFT(BITS),
        .COEFFS(HP_COEFFS)
    ) u_hp (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (sq_rd_en),
        .in_empty (sq_empty),
        .in_dout  (sq_dout),
        .out_wr_en(hp_wr_en),
        .out_full (hp_full),
        .out_din  (hp_din)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_hp (
        .clk(clock), .rst(reset),
        .wr_en(hp_wr_en), .din(hp_din), .full(hp_full),
        .rd_en(hp_rd_en), .dout(hp_dout), .empty(hp_empty)
    );

    mult_gain #(
        .DATA_W(32),
        .BITS(BITS),
        .POST_SHIFT(0)
    ) u_mult2 (
        .clock       (clock),
        .reset       (reset),
        .in_a_rd_en  (mult_a_rd_en),
        .in_a_empty  (hp_empty),
        .in_a_dout   (hp_dout),
        .in_b_rd_en  (mult_b_rd_en),
        .in_b_empty  (bplmr_empty),
        .in_b_dout   (bplmr_dout),
        .out_wr_en   (mult_wr_en),
        .out_full    (mult_full),
        .out_din     (mult_din)
    );

    assign hp_rd_en    = mult_a_rd_en;
    assign bplmr_rd_en = mult_b_rd_en;

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_mult (
        .clk(clock), .rst(reset),
        .wr_en(mult_wr_en), .din(mult_din), .full(mult_full),
        .rd_en(mult_rd_en), .dout(mult_dout), .empty(mult_empty)
    );

    fir_fifo_wrap #(
        .DATA_W(32), .COEFF_W(32), .ACC_W(48),
        .TAPS(AUDIO_LMR_COEFF_TAPS),
        .DECIM(AUDIO_DECIM),
        .SCALE_SHIFT(BITS),
        .COEFFS(AUDIO_LMR_COEFFS)
    ) u_lmr (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (mult_rd_en),
        .in_empty (mult_empty),
        .in_dout  (mult_dout),
        .out_wr_en(lmr_wr_en),
        .out_full (lmr_full),
        .out_din  (lmr_din)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_lmr (
        .clk(clock), .rst(reset),
        .wr_en(lmr_wr_en), .din(lmr_din), .full(lmr_full),
        .rd_en(lmr_rd_en), .dout(lmr_dout), .empty(lmr_empty)
    );

    // explicit merge wiring
    assign addsub_in_a_empty = lpr_empty;
    assign addsub_in_b_empty = lmr_empty;
    assign addsub_in_a_dout  = lpr_dout;
    assign addsub_in_b_dout  = lmr_dout;

    assign lpr_rd_en = addsub_in_a_rd_en;
    assign lmr_rd_en = addsub_in_b_rd_en;

    add_sub u_add_sub (
        .clock        (clock),
        .reset        (reset),
        .in_a_rd_en   (addsub_in_a_rd_en),
        .in_a_empty   (addsub_in_a_empty),
        .in_a_dout    (addsub_in_a_dout),
        .in_b_rd_en   (addsub_in_b_rd_en),
        .in_b_empty   (addsub_in_b_empty),
        .in_b_dout    (addsub_in_b_dout),
        .out_add_wr_en(add_wr_en),
        .out_add_full (add_full),
        .out_add_din  (add_din),
        .out_sub_wr_en(sub_wr_en),
        .out_sub_full (sub_full),
        .out_sub_din  (sub_din)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_add (
        .clk(clock), .rst(reset),
        .wr_en(add_wr_en), .din(add_din), .full(add_full),
        .rd_en(add_rd_en), .dout(add_dout), .empty(add_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_sub (
        .clk(clock), .rst(reset),
        .wr_en(sub_wr_en), .din(sub_din), .full(sub_full),
        .rd_en(sub_rd_en), .dout(sub_dout), .empty(sub_empty)
    );

    iir #(
        .DATA_W(32),
        .COEFF_W(32),
        .TAPS(IIR_COEFF_TAPS),
        .SCALE_SHIFT(IIR_SCALE_SHIFT),
        .X_COEFFS(IIR_X_COEFFS),
        .Y_COEFFS(IIR_Y_COEFFS)
    ) u_iir_left (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (add_rd_en),
        .in_empty (add_empty),
        .in_dout  (add_dout),
        .out_wr_en(lde_wr_en),
        .out_full (lde_full),
        .out_din  (lde_din)
    );

    iir #(
        .DATA_W(32),
        .COEFF_W(32),
        .TAPS(IIR_COEFF_TAPS),
        .SCALE_SHIFT(IIR_SCALE_SHIFT),
        .X_COEFFS(IIR_X_COEFFS),
        .Y_COEFFS(IIR_Y_COEFFS)
    ) u_iir_right (
        .clock    (clock),
        .reset    (reset),
        .in_rd_en (sub_rd_en),
        .in_empty (sub_empty),
        .in_dout  (sub_dout),
        .out_wr_en(rde_wr_en),
        .out_full (rde_full),
        .out_din  (rde_din)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_lde (
        .clk(clock), .rst(reset),
        .wr_en(lde_wr_en), .din(lde_din), .full(lde_full),
        .rd_en(lde_rd_en), .dout(lde_dout), .empty(lde_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_rde (
        .clk(clock), .rst(reset),
        .wr_en(rde_wr_en), .din(rde_din), .full(rde_full),
        .rd_en(rde_rd_en), .dout(rde_dout), .empty(rde_empty)
    );

    mult_gain #(
        .DATA_W(32),
        .BITS(BITS),
        .POST_SHIFT(14-BITS)
    ) u_gain_left (
        .clock       (clock),
        .reset       (reset),
        .in_a_rd_en  (lg_a_rd_en),
        .in_a_empty  (lde_empty),
        .in_a_dout   (lde_dout),
        .in_b_rd_en  (lg_b_rd_en),
        .in_b_empty  (1'b0),
        .in_b_dout   (VOLUME_LEVEL),
        .out_wr_en   (lg_wr_en),
        .out_full    (lg_full),
        .out_din     (lg_din)
    );

    mult_gain #(
        .DATA_W(32),
        .BITS(BITS),
        .POST_SHIFT(14-BITS)
    ) u_gain_right (
        .clock       (clock),
        .reset       (reset),
        .in_a_rd_en  (rg_a_rd_en),
        .in_a_empty  (rde_empty),
        .in_a_dout   (rde_dout),
        .in_b_rd_en  (rg_b_rd_en),
        .in_b_empty  (1'b0),
        .in_b_dout   (VOLUME_LEVEL),
        .out_wr_en   (rg_wr_en),
        .out_full    (rg_full),
        .out_din     (rg_din)
    );

    assign lde_rd_en = lg_a_rd_en;
    assign rde_rd_en = rg_a_rd_en;

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_lg (
        .clk(clock), .rst(reset),
        .wr_en(lg_wr_en), .din(lg_din), .full(lg_full),
        .rd_en(lg_rd_en), .dout(lg_dout), .empty(lg_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_rg (
        .clk(clock), .rst(reset),
        .wr_en(rg_wr_en), .din(rg_din), .full(rg_full),
        .rd_en(rg_rd_en), .dout(rg_dout), .empty(rg_empty)
    );

    assign out_valid = !lg_empty && !rg_empty;
    assign out_left  = lg_dout;
    assign out_right = rg_dout;

    assign lg_rd_en = out_valid && out_ready;
    assign rg_rd_en = out_valid && out_ready;
endmodule

// ============================================================
// Top-level
// ============================================================
module fm_radio_top (
    input  logic               clock,
    input  logic               reset,

    input  logic [7:0]         iq_byte,
    input  logic               iq_valid,
    output logic               iq_ready,

    output logic signed [31:0] out_left,
    output logic signed [31:0] out_right,
    output logic               out_valid,
    input  logic               out_ready
);
    logic signed [31:0] samp_i, samp_q;
    logic               samp_valid, samp_ready;

    read_iq u_read_iq (
        .clk      (clock),
        .rst      (reset),
        .in_byte  (iq_byte),
        .in_valid (iq_valid),
        .in_ready (iq_ready),
        .out_i    (samp_i),
        .out_q    (samp_q),
        .out_valid(samp_valid),
        .out_ready(samp_ready)
    );

    fm_radio u_fm_radio (
        .clock    (clock),
        .reset    (reset),
        .in_i     (samp_i),
        .in_q     (samp_q),
        .in_valid (samp_valid),
        .in_ready (samp_ready),
        .out_left (out_left),
        .out_right(out_right),
        .out_valid(out_valid),
        .out_ready(out_ready)
    );
endmodule