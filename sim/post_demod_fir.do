transcript on

if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -sv ../sv/fir.sv
vlog -sv ../sv/post_demod_fir_top.sv
vlog -sv ../sv/post_demod_fir_tb.sv

vsim -c work.post_demod_fir_tb
run -all
quit -f