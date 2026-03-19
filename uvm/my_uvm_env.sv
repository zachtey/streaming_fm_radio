class my_uvm_env extends uvm_component;
    `uvm_component_utils(my_uvm_env)

    my_uvm_agent      agent;
    my_uvm_scoreboard scb;

    function new(string name = "my_uvm_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = my_uvm_agent     ::type_id::create("agent", this);
        scb   = my_uvm_scoreboard::type_id::create("scb",   this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(scb.analysis_export);
    endfunction
endclass