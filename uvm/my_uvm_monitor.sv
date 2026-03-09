import uvm_pkg::*;

// monitor that reads actual DUT outputs from FIFOs
class my_uvm_monitor_output extends uvm_monitor;
  `uvm_component_utils(my_uvm_monitor_output)

  uvm_analysis_port#(my_uvm_transaction) mon_ap_output;
  virtual my_uvm_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_resource_db#(virtual my_uvm_if)::read_by_name(
        .scope("ifs"), .name("vif"), .val(vif)));
    mon_ap_output = new(.name("mon_ap_output"), .parent(this));
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_uvm_transaction tx;
    logic read_pending;

    @(posedge vif.reset);
    @(negedge vif.reset);

    vif.out_r_rd_en = 1'b0;
    vif.out_i_rd_en = 1'b0;
    read_pending = 1'b0;

    forever begin
      @(negedge vif.clock);
      
      // read when both FIFOs have data
      if (!vif.out_r_empty && !vif.out_i_empty) begin
        vif.out_r_rd_en = 1'b1;
        vif.out_i_rd_en = 1'b1;
        read_pending = 1'b1;
      end else begin
        vif.out_r_rd_en = 1'b0;
        vif.out_i_rd_en = 1'b0;
        read_pending = 1'b0;
      end
      
      @(posedge vif.clock);
      
      if (read_pending) begin
        tx = my_uvm_transaction::type_id::create(.name("tx_out"), .contxt(get_full_name()));
        tx.real_data = vif.out_r_dout;
        tx.imag_data = vif.out_i_dout;
        mon_ap_output.write(tx);
        `uvm_info("MON_OUT", $sformatf("[%0t] Got output: %s", $time, tx.convert2string()), UVM_LOW)
        
        vif.out_r_rd_en = 1'b0;
        vif.out_i_rd_en = 1'b0;
        read_pending = 1'b0;
      end
    end
  endtask
endclass

// monitor that reads expected outputs from files
class my_uvm_monitor_compare extends uvm_monitor;
  `uvm_component_utils(my_uvm_monitor_compare)

  uvm_analysis_port#(my_uvm_transaction) mon_ap_compare;
  virtual my_uvm_if vif;

  logic [31:0] exp_real[16];  // expected outputs
  logic [31:0] exp_imag[16];
  int idx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_resource_db#(virtual my_uvm_if)::read_by_name(
      .scope("ifs"), .name("vif"), .val(vif)));
    mon_ap_compare = new("mon_ap_compare", this);
    
    // load expected outputs
    $readmemh("../source/fft_out_real.txt", exp_real);
    $readmemh("../source/fft_out_imag.txt", exp_imag);
    idx = 0;
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_uvm_transaction tx;

    phase.phase_done.set_drain_time(this, 2000);  // 2000ns drain for pipeline
    phase.raise_objection(this);

    @(posedge vif.reset);
    @(negedge vif.reset);

    forever begin
      @(negedge vif.clock);  // sample when output monitor sets rd_en
      
      // Check if we've sent all expected values
      if (idx >= 16) begin
        `uvm_info("MON_CMP", $sformatf("[%0t] All 16 expected outputs sent", $time), UVM_LOW)
        phase.drop_objection(this);
        break;
      end
      
      // send expected value whenever we see a read
      if (vif.out_r_rd_en && vif.out_i_rd_en) begin
        tx = my_uvm_transaction::type_id::create(.name("tx_cmp"), .contxt(get_full_name()));
        tx.real_data = exp_real[idx];
        tx.imag_data = exp_imag[idx];
        mon_ap_compare.write(tx);
        `uvm_info("MON_CMP", $sformatf("[%0t] Expected[%0d]: %s", $time, idx, tx.convert2string()), UVM_LOW)
        idx = idx + 1;
      end
    end
  endtask
endclass