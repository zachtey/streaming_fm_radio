`timescale 1ns/1ps

module my_uvm_tb;

    import uvm_pkg::*;
    import my_uvm_pkg::*;
    `include "uvm_macros.svh"

    logic clock;

    my_uvm_if vif(clock);

    fm_radio_top dut (
        .clock          (clock),
        .reset          (vif.reset),

        .in_full        (vif.in_full),
        .in_wr_en       (vif.in_wr_en),
        .in_din         (vif.in_din),

        .out_left_empty (vif.out_left_empty),
        .out_left_rd_en (vif.out_left_rd_en),
        .out_left_dout  (vif.out_left_dout),

        .out_right_empty(vif.out_right_empty),
        .out_right_rd_en(vif.out_right_rd_en),
        .out_right_dout (vif.out_right_dout)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    initial begin
        vif.reset          = 1'b1;
        vif.in_wr_en       = 1'b0;
        vif.in_din         = '0;
        vif.out_left_rd_en = 1'b0;
        vif.out_right_rd_en= 1'b0;

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