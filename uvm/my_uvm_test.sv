
import uvm_pkg::*;

// UVM test for FFT streaming
class my_uvm_test extends uvm_test;

    `uvm_component_utils(my_uvm_test)

    my_uvm_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = my_uvm_env::type_id::create(.name("env"), .parent(this));
    endfunction: build_phase

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction: end_of_elaboration_phase

    virtual task run_phase(uvm_phase phase);
        // objections are managed by compare monitor
        // just wait - monitor will end simulation when done
        #(CLOCK_PERIOD * 10000);  // 100us max timeout as safety
    endtask

endclass: my_uvm_test
