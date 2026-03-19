class my_uvm_driver extends uvm_driver #(my_uvm_transaction);
    `uvm_component_utils(my_uvm_driver)

    virtual my_uvm_if vif;
    my_uvm_config cfg;

    function new(string name = "my_uvm_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(my_uvm_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("DRV", "Could not get my_uvm_config")
        end

        vif = cfg.vif;
    endfunction

    virtual task run_phase(uvm_phase phase);
        my_uvm_transaction tr;

        vif.in_wr_en        <= 1'b0;
        vif.in_din          <= '0;
        vif.out_left_rd_en  <= 1'b0;
        vif.out_right_rd_en <= 1'b0;

        wait(vif.reset == 1'b0);

        forever begin
            seq_item_port.get_next_item(tr);

            @(negedge vif.clock);
            while (vif.in_full) begin
                vif.in_wr_en <= 1'b0;
                vif.in_din   <= '0;
                @(negedge vif.clock);
            end

            vif.in_din   <= {tr.in_i, tr.in_q};
            vif.in_wr_en <= 1'b1;

            @(negedge vif.clock);
            vif.in_wr_en <= 1'b0;
            vif.in_din   <= '0;

            seq_item_port.item_done();
        end
    endtask
endclass