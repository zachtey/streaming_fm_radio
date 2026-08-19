transcript on

# Clean
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL from ../sv
vlog -sv ../sv/fir.sv
vlog -sv ../sv/channel_fir_top.sv
vlog -sv ../sv/channel_fir_tb.sv

# Run simulation
vsim -voptargs=+acc work.channel_fir_tb

# Waves (optional)
add wave -r *

run -all