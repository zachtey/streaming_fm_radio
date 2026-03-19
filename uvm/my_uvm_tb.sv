`timescale 1ns/1ps

module my_uvm_tb;

    import uvm_pkg::*;
    import my_uvm_pkg::*;
    `include "uvm_macros.svh"

    logic clock;

    my_uvm_if vif(clock);

    fm_radio_top dut (
        .clock    (clock),
        .reset    (vif.reset),
        .iq_byte  (vif.iq_byte),
        .iq_valid (vif.iq_valid),
        .iq_ready (vif.iq_ready),
        .out_left (vif.out_left),
        .out_right(vif.out_right),
        .out_valid(vif.out_valid),
        .out_ready(vif.out_ready)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    initial begin
        vif.reset     = 1'b1;
        vif.iq_byte   = '0;
        vif.iq_valid  = 1'b0;
        vif.out_ready = 1'b1;

        repeat (5) @(posedge clock);
        vif.reset = 1'b0;
    end

    initial begin
        my_uvm_config cfg;

        cfg = my_uvm_config::type_id::create("cfg");
        cfg.vif             = vif;
        cfg.usrp_file       = "usrp.txt";
        cfg.left_gold_file  = "gold_12_left_gain.txt";
        cfg.right_gold_file = "gold_12_right_gain.txt";
        cfg.left_out_file   = "sv_left_audio_out.txt";
        cfg.right_out_file  = "sv_right_audio_out.txt";

        uvm_config_db#(my_uvm_config)::set(null, "*", "cfg", cfg);

        run_test("my_uvm_test");
    end

endmodule