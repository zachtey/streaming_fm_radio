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

    logic signed [DATA_W-1:0] x_reg  [0:TAPS-1];
    logic signed [DATA_W-1:0] x_next [0:TAPS-1];

    logic [DECIM_W-1:0] decim_cnt_reg, decim_cnt_next;

    logic signed [DATA_W-1:0] out_data_reg, out_data_next;
    logic                     out_valid_reg, out_valid_next;
    logic                     out_last_reg,  out_last_next;

    logic signed [ACC_W-1:0] acc_sum;
    logic signed [ACC_W-1:0] prod_full;
    logic signed [ACC_W-1:0] prod_scaled;

    logic signed [DATA_W-1:0] max_pos_data;
    logic signed [DATA_W-1:0] min_neg_data;
    logic signed [ACC_W-1:0]  max_pos_ext;
    logic signed [ACC_W-1:0]  min_neg_ext;

    logic accept_input;
    logic produce_output;

    initial begin
        $readmemh(COEFF_FILE, coeffs);
    end

    assign m_axis_tdata  = out_data_reg;
    assign m_axis_tvalid = out_valid_reg;
    assign m_axis_tlast  = out_last_reg;

    assign s_axis_tready = (~out_valid_reg) || m_axis_tready;

    // Truncation toward zero:
    // trunc(val / 2^SCALE_SHIFT)
    // Matches MATLAB fix(...) and your dequantize_i(...)
    function automatic logic signed [ACC_W-1:0] trunc_div_pow2;
        input logic signed [ACC_W-1:0] val;
        logic signed [ACC_W-1:0] bias;
        begin
            if (SCALE_SHIFT == 0) begin
                trunc_div_pow2 = val;
            end else begin
                if (val < 0)
                    bias = ({{(ACC_W-1){1'b0}},1'b1} <<< SCALE_SHIFT) - 1;
                else
                    bias = '0;

                trunc_div_pow2 = (val + bias) >>> SCALE_SHIFT;
            end
        end
    endfunction

    always_comb begin
        for (int k = 0; k < TAPS; k++) begin
            x_next[k] = x_reg[k];
        end

        decim_cnt_next = decim_cnt_reg;
        out_data_next  = out_data_reg;
        out_valid_next = out_valid_reg;
        out_last_next  = out_last_reg;

        acc_sum      = '0;
        prod_full    = '0;
        prod_scaled  = '0;

        max_pos_data = {1'b0, {(DATA_W-1){1'b1}}};
        min_neg_data = {1'b1, {(DATA_W-1){1'b0}}};

        max_pos_ext  = {{(ACC_W-DATA_W){1'b0}}, max_pos_data};
        min_neg_ext  = {{(ACC_W-DATA_W){1'b1}}, min_neg_data};

        accept_input   = s_axis_tvalid && s_axis_tready;
        produce_output = 1'b0;

        if (out_valid_reg && m_axis_tready) begin
            out_valid_next = 1'b0;
        end

        if (accept_input) begin
            x_next[0] = s_axis_tdata;
            for (int k = 1; k < TAPS; k++) begin
                x_next[k] = x_reg[k-1];
            end

            if (decim_cnt_reg == DECIM-1) begin
                decim_cnt_next = '0;
                produce_output = 1'b1;
            end else begin
                decim_cnt_next = decim_cnt_reg + 1'b1;
            end

            if (produce_output) begin
                acc_sum = '0;

                // BIT TRUE AYAYAYAYAYAYAYAYA7
                for (int k = 0; k < TAPS; k++) begin
                    if (k == 0)
                        prod_full = $signed(coeffs[k]) * $signed(s_axis_tdata);
                    else
                        prod_full = $signed(coeffs[k]) * $signed(x_reg[k-1]);

                    prod_scaled = trunc_div_pow2(prod_full);
                    acc_sum     = acc_sum + prod_scaled;
                end

                // Saturate final accumulated result to DATA_W
                if (acc_sum > max_pos_ext)
                    out_data_next = max_pos_data;
                else if (acc_sum < min_neg_ext)
                    out_data_next = min_neg_data;
                else
                    out_data_next = acc_sum[DATA_W-1:0];

                out_valid_next = 1'b1;
                out_last_next  = s_axis_tlast;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < TAPS; k++) begin
                x_reg[k] <= '0;
            end
            decim_cnt_reg <= '0;
            out_data_reg  <= '0;
            out_valid_reg <= 1'b0;
            out_last_reg  <= 1'b0;
        end else begin
            for (int k = 0; k < TAPS; k++) begin
                x_reg[k] <= x_next[k];
            end
            decim_cnt_reg <= decim_cnt_next;
            out_data_reg  <= out_data_next;
            out_valid_reg <= out_valid_next;
            out_last_reg  <= out_last_next;
        end
    end

endmodule