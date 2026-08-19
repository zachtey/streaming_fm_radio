class my_uvm_transaction extends uvm_sequence_item;
    `uvm_object_utils(my_uvm_transaction)

    rand bit signed [31:0] in_i;
    rand bit signed [31:0] in_q;

    bit signed [31:0] out_left;
    bit signed [31:0] out_right;

    function new(string name = "my_uvm_transaction");
        super.new(name);
    endfunction
endclass