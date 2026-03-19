transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/fm_radio_pkg.sv
vlog -sv ../sv/fir.sv
vlog -sv ../sv/seq_divider.sv
vlog -sv ../sv/demod.sv
vlog -sv ../sv/mult_gain.sv
vlog -sv ../sv/add_sub.sv
vlog -sv ../sv/iir.sv
vlog -sv ../sv/fm_radio_top.sv
vlog -sv ../sv/fm_radio_top_tb.sv

vsim -voptargs=+acc work.fm_radio_top_tb
add wave -r *
run -all