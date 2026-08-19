transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/fm_radio_pkg.sv
vlog -sv ../sv/iir.sv
vlog -sv ../sv/iir_tb.sv

# Run simulation
vsim -voptargs=+acc work.iir_tb

# Waves (optional)
add wave -r *

run -all