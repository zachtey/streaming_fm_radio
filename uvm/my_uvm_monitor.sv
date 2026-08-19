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

        vif.out_left_rd_en  <= 1'b0;
        vif.out_right_rd_en <= 1'b0;

        wait(vif.reset == 1'b0);

        forever begin
            @(negedge vif.clock);

            if (!vif.out_left_empty && !vif.out_right_empty) begin
                vif.out_left_rd_en  <= 1'b1;
                vif.out_right_rd_en <= 1'b1;
            end else begin
                vif.out_left_rd_en  <= 1'b0;
                vif.out_right_rd_en <= 1'b0;
            end

            @(posedge vif.clock);
            if (vif.out_left_rd_en && vif.out_right_rd_en &&
                !vif.out_left_empty && !vif.out_right_empty) begin
                tr = my_uvm_transaction::type_id::create("mon_tr");
                tr.out_left  = vif.out_left_dout;
                tr.out_right = vif.out_right_dout;
                ap.write(tr);
            end
        end
    endtask
endclass