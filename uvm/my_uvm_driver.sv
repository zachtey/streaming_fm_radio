// my_uvm_driver.sv - drives input FIFOs with test vectors
import uvm_pkg::*;

class my_uvm_driver extends uvm_driver#(my_uvm_transaction);
  `uvm_component_utils(my_uvm_driver)

  virtual my_uvm_if vif;
  int real_fd, imag_fd;
  logic [31:0] in_real[16];  // N=16 samples
  logic [31:0] in_imag[16];
  int idx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_resource_db#(virtual my_uvm_if)::read_by_name(.scope("ifs"), .name("vif"), .val(vif)));
  endfunction

  virtual task run_phase(uvm_phase phase);
    drive();
  endtask

  virtual task drive();
    // load test vectors
    $readmemh("../source/fft_in_real.txt", in_real);
    $readmemh("../source/fft_in_imag.txt", in_imag);
    
    `uvm_info("DRV", $sformatf("Loaded vectors: real[0]=%08x imag[0]=%08x", in_real[0], in_imag[0]), UVM_LOW)

    // wait for reset
    @(posedge vif.reset);
    @(negedge vif.reset);

    vif.in_r_wr_en = 1'b0;
    vif.in_i_wr_en = 1'b0;
    vif.in_r_din = 32'd0;
    vif.in_i_din = 32'd0;
    idx = 0;

    // write all 16 samples to input FIFOs
    forever begin
      @(negedge vif.clock);
      
      if (idx < 16 && !vif.in_r_full && !vif.in_i_full) begin
        vif.in_r_din = in_real[idx];
        vif.in_i_din = in_imag[idx];
        vif.in_r_wr_en = 1'b1;
        vif.in_i_wr_en = 1'b1;
        `uvm_info("DRV", $sformatf("[%0t] Writing sample %0d: real=%08x imag=%08x", $time, idx, in_real[idx], in_imag[idx]), UVM_LOW)
        idx = idx + 1;
      end else begin
        vif.in_r_wr_en = 1'b0;
        vif.in_i_wr_en = 1'b0;
        if (idx >= 16 && idx == 16) begin
          `uvm_info("DRV", $sformatf("[%0t] All 16 inputs written", $time), UVM_LOW)
          idx = 17; // mark done
        end
      end
    end
  endtask

endclass