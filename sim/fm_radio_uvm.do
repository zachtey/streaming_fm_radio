transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

set UVM_INC /vol/mentor/questa_sim-2019.3_2/questasim/verilog_src/uvm-1.1d/src

vlog -64 -sv -cover bcst ../sv/fm_radio_pkg.sv
vlog -64 -sv -cover bcst ../sv/fir.sv
vlog -64 -sv -cover bcst ../sv/seq_divider.sv
vlog -64 -sv -cover bcst ../sv/demod.sv
vlog -64 -sv -cover bcst ../sv/mult_gain.sv
vlog -64 -sv -cover bcst ../sv/add_sub.sv
vlog -64 -sv -cover bcst ../sv/iir.sv
vlog -64 -sv -cover bcst ../sv/helpers.sv
vlog -64 -sv -cover bcst ../sv/fm_radio.sv
vlog -64 -sv -cover bcst ../sv/fm_radio_top.sv

vlog -64 -sv +incdir+../uvm +incdir+$UVM_INC ../uvm/my_uvm_if.sv
vlog -64 -sv +incdir+../uvm +incdir+$UVM_INC \
    ../uvm/my_uvm_pkg.sv \
    ../uvm/my_uvm_tb.sv

vsim -64 -c -coverage -voptargs=+acc work.my_uvm_tb

run -all
coverage save -onexit fm_radio.ucdb
quit -f