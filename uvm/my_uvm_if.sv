// my_uvm_if.sv - interface for FFT streaming with FIFOs
import uvm_pkg::*;

interface my_uvm_if;
  logic        clock;
  logic        reset;

  // input FIFOs (testbench writes, DUT reads)
  logic        in_r_full;
  logic        in_r_wr_en;
  logic [31:0] in_r_din;
  
  logic        in_i_full;
  logic        in_i_wr_en;
  logic [31:0] in_i_din;

  // output FIFOs (DUT writes, testbench reads)
  logic        out_r_empty;
  logic        out_r_rd_en;
  logic [31:0] out_r_dout;
  
  logic        out_i_empty;
  logic        out_i_rd_en;
  logic [31:0] out_i_dout;
endinterface