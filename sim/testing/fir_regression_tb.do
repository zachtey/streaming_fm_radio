transcript on

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work


vlog -sv ../sv/fm_radio_pkg.sv
vlog -sv ../sv/fir.sv
vlog -sv ../sv/fir_regression_tb.sv


vsim -voptargs=+acc work.fir_regression_tb
add wave -r *
run -all