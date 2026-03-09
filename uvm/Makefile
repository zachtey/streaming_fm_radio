# Makefile for UVM DPI library
# Based on Questa UVM setup

UVM_HOME = /vol/mentor/questa_sim-2019.3_2/questasim/verilog_src/uvm-1.2
QUESTA_HOME = /vol/mentor/questa_sim-2019.3_2/questasim
LIB_DIR = ../sim/lib

all: $(LIB_DIR)/uvm_dpi.so

$(LIB_DIR):
	mkdir -p $(LIB_DIR)

$(LIB_DIR)/uvm_dpi.so: $(LIB_DIR)
	g++ -m64 -fPIC -shared \
		-I$(UVM_HOME)/src/dpi \
		-I$(QUESTA_HOME)/include \
		-DQUESTA -DQUESTA_UVM \
		-o $(LIB_DIR)/uvm_dpi.so \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc

clean:
	rm -rf $(LIB_DIR)

.PHONY: all clean
