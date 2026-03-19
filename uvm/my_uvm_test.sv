class my_uvm_test extends uvm_test;
    `uvm_component_utils(my_uvm_test)

    my_uvm_env      env;
    my_uvm_sequence seq;

    function new(string name = "my_uvm_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = my_uvm_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        seq = my_uvm_sequence::type_id::create("seq");
        seq.start(env.agent.seqr);

        wait (env.scb.is_done());
        repeat (50) @(posedge env.agent.mon.vif.clock);

        phase.drop_objection(this);
    endtask
endclass