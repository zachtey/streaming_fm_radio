import uvm_pkg::*;

// transaction for FFT input/output samples
class my_uvm_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_uvm_transaction)

  logic [31:0] real_data;  // real part
  logic [31:0] imag_data;  // imaginary part

  function new(string name="my_uvm_transaction");
    super.new(name);
  endfunction
  
  function string convert2string();
    return $sformatf("real=%08x imag=%08x", real_data, imag_data);
  endfunction
endclass