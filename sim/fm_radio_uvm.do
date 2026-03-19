transcript on

if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Match built-in Questa UVM
set UVM_INC /vol/mentor/questa_sim-2019.3_2/questasim/verilog_src/uvm-1.1d/src

# RTL
vlog -64 -sv ../sv/fm_radio_pkg.sv
vlog -64 -sv ../sv/fir.sv
vlog -64 -sv ../sv/seq_divider.sv
vlog -64 -sv ../sv/demod.sv
vlog -64 -sv ../sv/mult_gain.sv
vlog -64 -sv ../sv/add_sub.sv
vlog -64 -sv ../sv/iir.sv
vlog -64 -sv ../sv/helpers.sv
vlog -64 -sv ../sv/fm_radio.sv
vlog -64 -sv ../sv/fm_radio_top.sv

# Interface
vlog -64 -sv +incdir+../uvm +incdir+$UVM_INC ../uvm/my_uvm_if.sv

# UVM package + TB
vlog -64 -sv +incdir+../uvm +incdir+$UVM_INC \
    ../uvm/my_uvm_pkg.sv \
    ../uvm/my_uvm_tb.sv

# Run
vsim -64 -c -voptargs=+acc work.my_uvm_tb

run -all
quit -f