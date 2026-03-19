// `timescale 1ns/1ps
// import fm_radio_pkg::*;

// // Top-level module: read raw I/Q bytes, run through FM radio, output left/right audio
// module fm_radio_top (
//     input  logic               clock,
//     input  logic               reset,

//     input  logic [7:0]         iq_byte,
//     input  logic               iq_valid,
//     output logic               iq_ready,

//     output logic signed [31:0] out_left,
//     output logic signed [31:0] out_right,
//     output logic               out_valid,
//     input  logic               out_ready
// );
//     logic signed [31:0] samp_i, samp_q;
//     logic               samp_valid, samp_ready;

//     read_iq u_read_iq (
//         .clk      (clock),
//         .rst      (reset),
//         .in_byte  (iq_byte),
//         .in_valid (iq_valid),
//         .in_ready (iq_ready),
//         .out_i    (samp_i),
//         .out_q    (samp_q),
//         .out_valid(samp_valid),
//         .out_ready(samp_ready)
//     );

//     fm_radio u_fm_radio (
//         .clock    (clock),
//         .reset    (reset),
//         .in_i     (samp_i),
//         .in_q     (samp_q),
//         .in_valid (samp_valid),
//         .in_ready (samp_ready),
//         .out_left (out_left),
//         .out_right(out_right),
//         .out_valid(out_valid),
//         .out_ready(out_ready)
//     );
// endmodule

`timescale 1ns/1ps
import fm_radio_pkg::*;

module fm_radio_top (
    input  logic        clock,
    input  logic        reset,

    // Input IQ data (64-bit: {I[63:32], Q[31:0]} pre-quantized)
    output logic        in_full,
    input  logic        in_wr_en,
    input  logic [63:0] in_din,

    // Left audio output (32-bit signed)
    output logic        out_left_empty,
    input  logic        out_left_rd_en,
    output logic signed [31:0] out_left_dout,

    // Right audio output (32-bit signed)
    output logic        out_right_empty,
    input  logic        out_right_rd_en,
    output logic signed [31:0] out_right_dout
);

    // ============================================================
    // Input FIFO (64-bit: upper 32 = I, lower 32 = Q)
    // ============================================================
    logic        in_rd_en;
    logic        in_empty;
    logic [63:0] in_dout;

    sync_fifo #(.WIDTH(64), .DEPTH(128)) fifo_in (
        .clk   (clock),
        .rst   (reset),
        .wr_en (in_wr_en),
        .din   (in_din),
        .full  (in_full),
        .rd_en (in_rd_en),
        .dout  (in_dout),
        .empty (in_empty)
    );

    // ============================================================
    // Input adapter: FIFO read → valid/ready for fm_radio
    // ============================================================
    logic signed [31:0] samp_i, samp_q;
    logic               samp_valid, samp_ready;

    assign samp_i     = $signed(in_dout[63:32]);
    assign samp_q     = $signed(in_dout[31:0]);
    assign samp_valid = !in_empty;
    assign in_rd_en   = !in_empty && samp_ready;

    // ============================================================
    // Core FM radio pipeline
    // ============================================================
    logic signed [31:0] radio_left, radio_right;
    logic               radio_valid, radio_ready;

    fm_radio u_fm_radio (
        .clock    (clock),
        .reset    (reset),
        .in_i     (samp_i),
        .in_q     (samp_q),
        .in_valid (samp_valid),
        .in_ready (samp_ready),
        .out_left (radio_left),
        .out_right(radio_right),
        .out_valid(radio_valid),
        .out_ready(radio_ready)
    );

    // ============================================================
    // Output FIFOs (left and right)
    // ============================================================
    logic left_full, right_full;

    assign radio_ready = !left_full && !right_full;

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_out_left (
        .clk   (clock),
        .rst   (reset),
        .wr_en (radio_valid && radio_ready),
        .din   (radio_left),
        .full  (left_full),
        .rd_en (out_left_rd_en),
        .dout  (out_left_dout),
        .empty (out_left_empty)
    );

    sync_fifo #(.WIDTH(32), .DEPTH(128)) fifo_out_right (
        .clk   (clock),
        .rst   (reset),
        .wr_en (radio_valid && radio_ready),
        .din   (radio_right),
        .full  (right_full),
        .rd_en (out_right_rd_en),
        .dout  (out_right_dout),
        .empty (out_right_empty)
    );

endmodule