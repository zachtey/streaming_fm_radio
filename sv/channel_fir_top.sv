`timescale 1ns/1ps

module channel_fir_top #(
    parameter int DATA_W      = 16,
    parameter int COEFF_W     = 16,
    parameter int ACC_W       = 48,
    parameter int TAPS        = 20,
    parameter int DECIM       = 1,
    parameter int SCALE_SHIFT = 15,
    parameter string COEFF_FILE = "channel_lpf_20tap.mem"
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic signed [DATA_W-1:0]     in_i,
    input  logic signed [DATA_W-1:0]     in_q,
    input  logic                         in_valid,
    output logic                         in_ready,
    input  logic                         in_last,

    output logic signed [DATA_W-1:0]     out_i,
    output logic signed [DATA_W-1:0]     out_q,
    output logic                         out_valid,
    input  logic                         out_ready,
    output logic                         out_last
);

    logic i_ready, q_ready;
    logic i_valid, q_valid;
    logic i_last,  q_last;

    assign in_ready  = i_ready & q_ready;
    assign out_valid = i_valid & q_valid;
    assign out_last  = i_last & q_last;

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(DECIM),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE(COEFF_FILE)
    ) u_fir_i (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(in_i),
        .s_axis_tvalid(in_valid),
        .s_axis_tready(i_ready),
        .s_axis_tlast(in_last),
        .m_axis_tdata(out_i),
        .m_axis_tvalid(i_valid),
        .m_axis_tready(out_ready),
        .m_axis_tlast(i_last)
    );

    fir #(
        .DATA_W(DATA_W),
        .COEFF_W(COEFF_W),
        .ACC_W(ACC_W),
        .TAPS(TAPS),
        .DECIM(DECIM),
        .SCALE_SHIFT(SCALE_SHIFT),
        .COEFF_FILE(COEFF_FILE)
    ) u_fir_q (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(in_q),
        .s_axis_tvalid(in_valid),
        .s_axis_tready(q_ready),
        .s_axis_tlast(in_last),
        .m_axis_tdata(out_q),
        .m_axis_tvalid(q_valid),
        .m_axis_tready(out_ready),
        .m_axis_tlast(q_last)
    );

endmodule