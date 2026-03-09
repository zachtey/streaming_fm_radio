import uvm_pkg::*;

class my_uvm_sequence extends uvm_sequence#(my_uvm_transaction);
  `uvm_object_utils(my_uvm_sequence)

  function new(string name="");
    super.new(name);
  endfunction

  task body();
  endtask
endclass

typedef uvm_sequencer#(my_uvm_transaction) my_uvm_sequencer;