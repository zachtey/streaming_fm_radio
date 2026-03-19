#!/bin/bash
# Run UVM testbench for FM Radio

# Source QuestaSim environment
source /vol/eecs392/env/questasim.env

# Run the simulation with the UVM .do file
vsim -do fm_radio_uvm.do
