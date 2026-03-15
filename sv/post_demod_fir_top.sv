`timescale 1ns/1ps

module post_demod_fir_top #(
    parameter int DATA_W      = 32,
    parameter int COEFF_W     = 16,
    parameter int ACC_W       = 56,
    parameter int TAPS        = 32,
    parameter int SCALE_SHIFT = 10
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic signed [DATA_W-1:0]     demod_data,
    input  logic                         demod_valid,
    output logic                         demod_ready,
    input  logic                         demod_last,

    output logic signed [DATA_W-1:0]     audio_lpr_data,
    output logic                         audio_lpr_valid,
    input  logic                         audio_lpr_ready,
    output logic                         audio_lpr_last,

    output logic signed [DATA_W-1:0]     bp_pilot_data,
    output logic                         bp_pilot_valid,
    input  logic                         bp_pilot_ready,
    output logic                         bp_pilot_last,

    output logic signed [DATA_W-1:0]     bp_lmr_data,
    output logic                         bp_lmr_valid,
    input  logic                         bp_lmr_ready,
    output logic                         bp_lmr_last
);

    logic lpr_in_ready;
    logic pilot_in_ready;
    logic lmr_in_ready;

    // Fanout input stream to all three FIR branches.
    // For this first version, only accept a new input when all three can accept it.
    assign demod_ready = lpr_in_ready & pilot_in_ready & lmr_in_ready;

    // L+R low-pass + decimate by 8
    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(8),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE("audio_lpr_32tap.mem")
    ) u_audio_lpr (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(demod_data),
        .s_axis_tvalid(demod_valid),
        .s_axis_tready(lpr_in_ready),
        .s_axis_tlast(demod_last),
        .m_axis_tdata(audio_lpr_data),
        .m_axis_tvalid(audio_lpr_valid),
        .m_axis_tready(audio_lpr_ready),
        .m_axis_tlast(audio_lpr_last)
    );

    // Pilot band-pass
    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(1),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE("bp_pilot_32tap.mem")
    ) u_bp_pilot (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(demod_data),
        .s_axis_tvalid(demod_valid),
        .s_axis_tready(pilot_in_ready),
        .s_axis_tlast(demod_last),
        .m_axis_tdata(bp_pilot_data),
        .m_axis_tvalid(bp_pilot_valid),
        .m_axis_tready(bp_pilot_ready),
        .m_axis_tlast(bp_pilot_last)
    );

    // L-R band-pass
    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(1),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE("bp_lmr_32tap.mem")
    ) u_bp_lmr (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(demod_data),
        .s_axis_tvalid(demod_valid),
        .s_axis_tready(lmr_in_ready),
        .s_axis_tlast(demod_last),
        .m_axis_tdata(bp_lmr_data),
        .m_axis_tvalid(bp_lmr_valid),
        .m_axis_tready(bp_lmr_ready),
        .m_axis_tlast(bp_lmr_last)
    );

endmodule