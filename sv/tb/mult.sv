`timescale 1ns/1ps

module mult #(
    parameter int DATA_W      = 32,
    parameter int OUT_W       = 32,
    parameter int PROD_W      = 64,
    parameter int SCALE_SHIFT = 10
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic signed [DATA_W-1:0]     s_axis_a_tdata,
    input  logic signed [DATA_W-1:0]     s_axis_b_tdata,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    output logic signed [OUT_W-1:0]      m_axis_tdata,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic                         m_axis_tlast
);

    logic signed [OUT_W-1:0] out_data_reg, out_data_next;
    logic                    out_valid_reg, out_valid_next;
    logic                    out_last_reg,  out_last_next;

    logic signed [PROD_W-1:0] prod_full;
    logic signed [PROD_W-1:0] prod_scaled;

    logic signed [OUT_W-1:0] max_pos_data;
    logic signed [OUT_W-1:0] min_neg_data;
    logic signed [PROD_W-1:0] max_pos_ext;
    logic signed [PROD_W-1:0] min_neg_ext;

    logic accept_input;

    assign m_axis_tdata  = out_data_reg;
    assign m_axis_tvalid = out_valid_reg;
    assign m_axis_tlast  = out_last_reg;

    assign s_axis_tready = (~out_valid_reg) || m_axis_tready;

    function automatic logic signed [PROD_W-1:0] trunc_div_pow2;
        input logic signed [PROD_W-1:0] val;
        logic signed [PROD_W-1:0] bias;
        begin
            if (SCALE_SHIFT == 0) begin
                trunc_div_pow2 = val;
            end else begin
                if (val < 0)
                    bias = ({{(PROD_W-1){1'b0}},1'b1} <<< SCALE_SHIFT) - 1;
                else
                    bias = '0;

                trunc_div_pow2 = (val + bias) >>> SCALE_SHIFT;
            end
        end
    endfunction

    always_comb begin
        out_data_next  = out_data_reg;
        out_valid_next = out_valid_reg;
        out_last_next  = out_last_reg;

        prod_full   = '0;

        prod_scaled = '0;

        max_pos_data = {1'b0, {(OUT_W-1){1'b1}}};
        min_neg_data = {1'b1, {(OUT_W-1){1'b0}}};

        max_pos_ext = {{(PROD_W-OUT_W){1'b0}}, max_pos_data};
        min_neg_ext = {{(PROD_W-OUT_W){1'b1}}, min_neg_data};

        accept_input = s_axis_tvalid && s_axis_tready;

        if (out_valid_reg && m_axis_tready)
            out_valid_next = 1'b0;

        if (accept_input) begin
            prod_full   = $signed(s_axis_a_tdata) * $signed(s_axis_b_tdata);
            prod_scaled = trunc_div_pow2(prod_full);

            if (prod_scaled > max_pos_ext)
                out_data_next = max_pos_data;
            else if (prod_scaled < min_neg_ext)
                out_data_next = min_neg_data;
            else
                out_data_next = prod_scaled[OUT_W-1:0];

            out_valid_next = 1'b1;
            out_last_next  = s_axis_tlast;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data_reg  <= '0;
            out_valid_reg <= 1'b0;
            out_last_reg  <= 1'b0;
        end else begin
            out_data_reg  <= out_data_next;
            out_valid_reg <= out_valid_next;
            out_last_reg  <= out_last_next;
        end
    end

endmodule