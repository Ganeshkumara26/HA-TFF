# Makefile for Verilator testbenches
#
# sept 28, 2026
#
# i finally learned how to write a Makefile. the ones in the rvfpga
# labs were huge and incomprehensible. this one is simple.
# 
# targets:
#   make parser  - build and run eth_parser unit test
#   make filter  - build and run mav_filter unit test
#   make top     - build and run top-level integration test
#   make clean   - remove build artifacts

VERILATOR = verilator
VFLAGS = -Wno-fatal -Wno-lint -Wno-style --trace --cc -I../rtl

# RTL source files
PKG_SRC = ../rtl/ha_tff_pkg.sv
PARSER_SRC = ../rtl/eth_parser.sv
FILTER_SRC = ../rtl/mav_filter.sv
FIFO_SRC = ../rtl/telem_fifo.sv
WB_SRC = ../rtl/wb_slave.sv
TOP_SRC = ../rtl/ha_tff_top.sv

.PHONY: all clean parser filter top

all: top

parser:
	$(VERILATOR) $(VFLAGS) --top-module eth_parser $(PKG_SRC) $(PARSER_SRC) --exe ../tb/tb_eth_parser.cpp
	make -j -C obj_dir -f Veth_parser.mk Veth_parser
	./obj_dir/Veth_parser

filter:
	$(VERILATOR) $(VFLAGS) --top-module mav_filter $(PKG_SRC) $(FILTER_SRC) --exe ../tb/tb_mav_filter.cpp
	make -j -C obj_dir -f Vmav_filter.mk Vmav_filter
	./obj_dir/Vmav_filter

top:
	$(VERILATOR) $(VFLAGS) --top-module ha_tff_top $(PKG_SRC) $(PARSER_SRC) $(FILTER_SRC) $(FIFO_SRC) $(WB_SRC) $(TOP_SRC) --exe ../tb/tb_ha_tff_top.cpp
	make -j -C obj_dir -f Vha_tff_top.mk Vha_tff_top
	./obj_dir/Vha_tff_top

clean:
	rm -rf obj_dir
	rm -f *.vcd
