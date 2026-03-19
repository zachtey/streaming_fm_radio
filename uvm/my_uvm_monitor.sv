class my_uvm_monitor extends uvm_component;
    `uvm_component_utils(my_uvm_monitor)

    virtual my_uvm_if vif;
    my_uvm_config cfg;

    uvm_analysis_port #(my_uvm_transaction) ap;

    function new(string name = "my_uvm_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(my_uvm_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("MON", "Could not get my_uvm_config")
        end

        vif = cfg.vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        my_uvm_transaction tr;

        wait(vif.reset == 1'b0);

        forever begin
            @(posedge vif.clock);
            if (vif.out_valid && vif.out_ready) begin
                tr = my_uvm_transaction::type_id::create("mon_tr");
                tr.out_left  = vif.out_left;
                tr.out_right = vif.out_right;
                tr.out_valid = 1'b1;
                ap.write(tr);
            end
        end
    endtask
endclass