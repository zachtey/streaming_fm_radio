class my_uvm_config extends uvm_object;
    `uvm_object_utils(my_uvm_config)

    virtual my_uvm_if vif;

    string usrp_file;
    string left_gold_file;
    string right_gold_file;
    string left_out_file;
    string right_out_file;

    function new(string name = "my_uvm_config");
        super.new(name);
    endfunction
endclass