transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/add_sub.sv
vlog -sv ../sv/add_sub_tb.sv

# Run simulation
vsim -voptargs=+acc work.add_sub_tb

# Waves (optional)
add wave -r *

run -all