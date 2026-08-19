transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/fm_radio_pkg.sv
vlog -sv ../sv/mult_gain.sv
vlog -sv ../sv/mult_gain_tb.sv

# Run simulation
vsim -voptargs=+acc work.mult_gain_tb

# Waves (optional)
add wave -r *

run -all