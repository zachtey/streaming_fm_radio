import uvm_pkg::*;
import my_uvm_package::*;
`include "my_uvm_if.sv"

`timescale 1 ns / 1 ns

module my_uvm_tb;

  localparam integer N = 16;
  localparam integer W = 32;
  localparam integer FRAC = 14;
  localparam integer FIFO_DEPTH = 16;

  my_uvm_if vif();

  // intermediate signals between FIFOs and DUT
  wire in_rd_en;
  wire [W-1:0] in_r_dout, in_i_dout;
  wire in_r_empty, in_i_empty;

  wire out_wr_en;
  wire [W-1:0] out_r_din, out_i_din;
  wire out_r_full, out_i_full;

  // input FIFOs (testbench writes, DUT reads)
  fifo #(.FIFO_DATA_WIDTH(W), .FIFO_BUFFER_SIZE(FIFO_DEPTH)) fifo_in_r (
    .reset(vif.reset),
    .wr_clk(vif.clock), .wr_en(vif.in_r_wr_en), .din(vif.in_r_din), .full(vif.in_r_full),
    .rd_clk(vif.clock), .rd_en(in_rd_en), .dout(in_r_dout), .empty(in_r_empty)
  );

  fifo #(.FIFO_DATA_WIDTH(W), .FIFO_BUFFER_SIZE(FIFO_DEPTH)) fifo_in_i (
    .reset(vif.reset),
    .wr_clk(vif.clock), .wr_en(vif.in_i_wr_en), .din(vif.in_i_din), .full(vif.in_i_full),
    .rd_clk(vif.clock), .rd_en(in_rd_en), .dout(in_i_dout), .empty(in_i_empty)
  );

  // output FIFOs (DUT writes, testbench reads)
  fifo #(.FIFO_DATA_WIDTH(W), .FIFO_BUFFER_SIZE(FIFO_DEPTH)) fifo_out_r (
    .reset(vif.reset),
    .wr_clk(vif.clock), .wr_en(out_wr_en), .din(out_r_din), .full(out_r_full),
    .rd_clk(vif.clock), .rd_en(vif.out_r_rd_en), .dout(vif.out_r_dout), .empty(vif.out_r_empty)
  );

  fifo #(.FIFO_DATA_WIDTH(W), .FIFO_BUFFER_SIZE(FIFO_DEPTH)) fifo_out_i (
    .reset(vif.reset),
    .wr_clk(vif.clock), .wr_en(out_wr_en), .din(out_i_din), .full(out_i_full),
    .rd_clk(vif.clock), .rd_en(vif.out_i_rd_en), .dout(vif.out_i_dout), .empty(vif.out_i_empty)
  );

  // DUT - FFT with FIFO interface
  fft_top_stream_fifo #(.N(N), .W(W), .FRAC(FRAC)) dut (
    .clk(vif.clock),
    .reset(vif.reset),
    
    .in_rd_en(in_rd_en),
    .in_real_empty(in_r_empty),
    .in_real_dout(in_r_dout),
    .in_imag_empty(in_i_empty),
    .in_imag_dout(in_i_dout),
    
    .out_wr_en(out_wr_en),
    .out_real_full(out_r_full),
    .out_real_din(out_r_din),
    .out_imag_full(out_i_full),
    .out_imag_din(out_i_din)
  );

  initial begin
    uvm_resource_db#(virtual my_uvm_if)::set(.scope("ifs"), .name("vif"), .val(vif));
    run_test("my_uvm_test");
  end

  // reset sequence
  initial begin
    vif.clock <= 1'b1;
    vif.reset <= 1'b0;
    @(posedge vif.clock);
    vif.reset <= 1'b1;
    repeat(5) @(posedge vif.clock);
    vif.reset <= 1'b0;
  end

  // 10ns clock period
  always #(CLOCK_PERIOD/2) vif.clock = ~vif.clock;

endmodule