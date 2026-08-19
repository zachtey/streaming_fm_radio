`timescale 1ns/1ps
import fm_radio_pkg::*;

module fir #(
    parameter int DATA_W      = 32,
    parameter int COEFF_W     = 32,
    parameter int ACC_W       = 48,
    parameter int TAPS        = 32,
    parameter int DECIM       = 1,
    parameter int SCALE_SHIFT = 10,
    parameter logic signed [COEFF_W-1:0] COEFFS [0:TAPS-1] = '{default:'0}
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
    localparam int TAP_W   = (TAPS <= 1)  ? 1 : $clog2(TAPS);

    typedef enum logic [1:0] {
        ST_WAIT,   // wait for input sample
        ST_MAC,    // iterative multiply-accumulate
        ST_HOLD    // hold output until downstream ready
    } state_t;

    state_t state_reg, state_next;

    logic signed [DATA_W-1:0] x_reg [0:TAPS-1];
    logic [DECIM_W-1:0]       decim_cnt_reg, decim_cnt_next;
    logic [TAP_W-1:0]         tap_idx_reg, tap_idx_next;

    logic signed [ACC_W-1:0]  acc_reg, acc_next;

    logic signed [DATA_W-1:0] out_data_reg, out_data_next;
    logic                     out_valid_reg, out_valid_next;
    logic                     out_last_reg,  out_last_next;

    logic                     mac_active_reg, mac_active_next;
    logic                     sampled_last_reg, sampled_last_next;

    logic signed [DATA_W-1:0] max_pos_data;
    logic signed [DATA_W-1:0] min_neg_data;
    logic signed [ACC_W-1:0]  max_pos_ext;
    logic signed [ACC_W-1:0]  min_neg_ext;

    logic accept_input;
    logic produce_output_now;

    logic signed [DATA_W-1:0] prod_32;
    logic signed [ACC_W-1:0]  prod_scaled;
    logic signed [ACC_W-1:0]  acc_candidate;

    integer k;

    assign m_axis_tdata  = out_data_reg;
    assign m_axis_tvalid = out_valid_reg;
    assign m_axis_tlast  = out_last_reg;

    // Backpressure: only accept a new sample when idle and not holding output
    assign s_axis_tready = (state_reg == ST_WAIT) && !out_valid_reg;

    assign accept_input = s_axis_tvalid && s_axis_tready;

    function automatic logic signed [ACC_W-1:0] trunc_div_pow2;
        input logic signed [ACC_W-1:0] val;
        logic signed [ACC_W-1:0] bias;
        begin
            if (SCALE_SHIFT == 0) begin
                trunc_div_pow2 = val;
            end else begin
                if (val < 0)
                    bias = ({{(ACC_W-1){1'b0}}, 1'b1} <<< SCALE_SHIFT) - 1;
                else
                    bias = '0;

                trunc_div_pow2 = (val + bias) >>> SCALE_SHIFT;
            end
        end
    endfunction

    always_comb begin
        max_pos_data = {1'b0, {(DATA_W-1){1'b1}}};
        min_neg_data = {1'b1, {(DATA_W-1){1'b0}}};

        max_pos_ext  = {{(ACC_W-DATA_W){1'b0}}, max_pos_data};
        min_neg_ext  = {{(ACC_W-DATA_W){1'b1}}, min_neg_data};
    end

    always_comb begin
        state_next        = state_reg;
        decim_cnt_next    = decim_cnt_reg;
        tap_idx_next      = tap_idx_reg;
        acc_next          = acc_reg;
        out_data_next     = out_data_reg;
        out_valid_next    = out_valid_reg;
        out_last_next     = out_last_reg;
        mac_active_next   = mac_active_reg;
        sampled_last_next = sampled_last_reg;

        prod_32       = '0;
        prod_scaled   = '0;
        acc_candidate = acc_reg;

        produce_output_now = 1'b0;

        // consume held output
        if (out_valid_reg && m_axis_tready) begin
            out_valid_next = 1'b0;
        end

        case (state_reg)

            ST_WAIT: begin
                if (accept_input) begin
                    sampled_last_next = s_axis_tlast;

                    if (decim_cnt_reg == DECIM-1) begin
                        decim_cnt_next    = '0;
                        tap_idx_next      = '0;
                        acc_next          = '0;
                        mac_active_next   = 1'b1;
                        state_next        = ST_MAC;
                    end else begin
                        decim_cnt_next    = decim_cnt_reg + 1'b1;
                        mac_active_next   = 1'b0;
                    end
                end
            end

            ST_MAC: begin
                // 32-bit wrapping multiply first, then sign-extend and dequantize
                prod_32     = COEFFS[tap_idx_reg] * x_reg[tap_idx_reg];
                prod_scaled = trunc_div_pow2({{(ACC_W-DATA_W){prod_32[DATA_W-1]}}, prod_32});

                acc_candidate = acc_reg + prod_scaled;
                acc_next      = acc_candidate;

                if (tap_idx_reg == TAPS-1) begin
                    // Final saturation after the last MAC term
                    if (acc_candidate > max_pos_ext)
                        out_data_next = max_pos_data;
                    else if (acc_candidate < min_neg_ext)
                        out_data_next = min_neg_data;
                    else
                        out_data_next = acc_candidate[DATA_W-1:0];

                    out_valid_next  = 1'b1;
                    out_last_next   = sampled_last_reg;
                    mac_active_next = 1'b0;
                    state_next      = ST_HOLD;
                end else begin
                    tap_idx_next = tap_idx_reg + 1'b1;
                end
            end

            ST_HOLD: begin
                if (out_valid_reg && m_axis_tready) begin
                    state_next = ST_WAIT;
                end
            end

            default: begin
                state_next = ST_WAIT;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg        <= ST_WAIT;
            decim_cnt_reg    <= '0;
            tap_idx_reg      <= '0;
            acc_reg          <= '0;
            out_data_reg     <= '0;
            out_valid_reg    <= 1'b0;
            out_last_reg     <= 1'b0;
            mac_active_reg   <= 1'b0;
            sampled_last_reg <= 1'b0;

            for (k = 0; k < TAPS; k = k + 1) begin
                x_reg[k] <= '0;
            end
        end else begin
            state_reg        <= state_next;
            decim_cnt_reg    <= decim_cnt_next;
            tap_idx_reg      <= tap_idx_next;
            acc_reg          <= acc_next;
            out_data_reg     <= out_data_next;
            out_valid_reg    <= out_valid_next;
            out_last_reg     <= out_last_next;
            mac_active_reg   <= mac_active_next;
            sampled_last_reg <= sampled_last_next;

            // Shift input history only when a new sample is accepted
            if (accept_input) begin
                x_reg[0] <= s_axis_tdata;
                for (k = 1; k < TAPS; k = k + 1) begin
                    x_reg[k] <= x_reg[k-1];
                end
            end
        end
    end

endmodule