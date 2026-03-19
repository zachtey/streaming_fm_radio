class my_uvm_transaction extends uvm_sequence_item;
    `uvm_object_utils(my_uvm_transaction)

    rand bit [7:0] iq_byte;

    bit signed [31:0] out_left;
    bit signed [31:0] out_right;
    bit               out_valid;

    function new(string name = "my_uvm_transaction");
        super.new(name);
    endfunction
endclass