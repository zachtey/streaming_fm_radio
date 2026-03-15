transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/atan.sv
vlog -sv ../sv/demod.sv
vlog -sv ../sv/demod_tb.sv

# Run simulation
vsim -voptargs=+acc work.demod_tb

# Waves (optional)
add wave -r *

run -all