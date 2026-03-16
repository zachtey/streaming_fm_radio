transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL / TB
vlog -sv ../sv/mult.sv
vlog -sv ../sv/mult_pilot_squared_tb.sv

# Run simulation
vsim -voptargs=+acc work.mult_pilot_squared_tb

# Waves
add wave sim:/mult_pilot_squared_tb/*
add wave sim:/mult_pilot_squared_tb/dut/*

run -all