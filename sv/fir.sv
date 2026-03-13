`timescale 1ns/1ps

module fir #(
    parameter int DATA_W      = 16,
    parameter int COEFF_W     = 16,
    parameter int ACC_W       = 48,
    parameter int TAPS        = 20,
    parameter int DECIM       = 1,
    parameter int SCALE_SHIFT = 15,
    parameter string COEFF_FILE = "../src/channel_lpf_20tap.mem"
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic signed [DATA_W-1:0]     s_axis_tdata,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    output logic signed [DATA_W-1:0]     m_axis_tdata,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic                         m_axis_tlast
);

    localparam int DECIM_W = (DECIM <= 1) ? 1 : $clog2(DECIM);

    logic signed [COEFF_W-1:0] coeffs [0:TAPS-1];
    logic signed [DATA_W-1:0]  x      [0:TAPS-1];

    logic [DECIM_W-1:0] decim_cnt;

    logic signed [DATA_W-1:0] out_data_reg;
    logic                     out_valid_reg;
    logic                     out_last_reg;

    integer i;
    logic signed [ACC_W-1:0] prod;
    logic signed [ACC_W-1:0] acc_next;
    logic signed [ACC_W-1:0] shifted_acc;

    initial begin
        $readmemh(COEFF_FILE, coeffs);
    end

    assign m_axis_tdata  = out_data_reg;
    assign m_axis_tvalid = out_valid_reg;
    assign m_axis_tlast  = out_last_reg;

    assign s_axis_tready = (~out_valid_reg) || m_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TAPS; i++) begin
                x[i] <= '0;
            end
            decim_cnt     <= '0;
            out_data_reg  <= '0;
            out_valid_reg <= 1'b0;
            out_last_reg  <= 1'b0;
        end else begin
            if (out_valid_reg && m_axis_tready) begin
                out_valid_reg <= 1'b0;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                for (i = TAPS-1; i > 0; i--) begin
                    x[i] <= x[i-1];
                end
                x[0] <= s_axis_tdata;

                if (decim_cnt == DECIM-1) begin
                    decim_cnt <= '0;

                    acc_next = '0;
                    for (i = 0; i < TAPS; i++) begin
                        prod = $signed(coeffs[i]) * $signed((i == 0) ? s_axis_tdata : x[i-1]);
                        acc_next = acc_next + prod;
                    end

                    shifted_acc = acc_next >>> SCALE_SHIFT;

                    if (shifted_acc > 32767)
                        out_data_reg <= 16'sd32767;
                    else if (shifted_acc < -32768)
                        out_data_reg <= -16'sd32768;
                    else
                        out_data_reg <= shifted_acc[DATA_W-1:0];

                    out_valid_reg <= 1'b1;
                    out_last_reg  <= s_axis_tlast;
                end else begin
                    decim_cnt <= decim_cnt + 1'b1;
                end
            end
        end
    end

endmodule