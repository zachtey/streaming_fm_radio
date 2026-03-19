class my_uvm_agent extends uvm_component;
    `uvm_component_utils(my_uvm_agent)

    my_uvm_driver    drv;
    uvm_sequencer #(my_uvm_transaction) seqr;
    my_uvm_monitor   mon;

    function new(string name = "my_uvm_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        drv  = my_uvm_driver   ::type_id::create("drv",  this);
        seqr = uvm_sequencer#(my_uvm_transaction)::type_id::create("seqr", this);
        mon  = my_uvm_monitor  ::type_id::create("mon",  this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass