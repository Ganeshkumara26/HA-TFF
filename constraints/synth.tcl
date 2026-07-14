# Vivado Synthesis Script for HA-TFF System (Final Release)
# Target: Xilinx Artix-7 xc7a100tcsg324-1
# Clock: 156.25 MHz (6.4ns period) — 10GbE line rate

create_project -in_memory -part xc7a100tcsg324-1

# Read all RTL source files
read_verilog ../rtl/ha_tff_parser_v002.v
read_verilog ../rtl/ha_tff_hash_v002.v
read_verilog ../rtl/ha_tff_bram_bank.v
read_verilog ../rtl/ha_tff_matcher_v002.v
read_verilog ../rtl/ha_tff_datapath_top_v003.v
read_verilog ../rtl/ha_tff_axi_lite_regs.v
read_verilog ../rtl/snn_feature_encoder.v
read_verilog ../rtl/snn_tff_neuron_v004.v
read_verilog ../rtl/snn_tff_layer_v005.v
read_verilog ../rtl/axi_stream_delay_line.v
read_verilog ../rtl/ha_tff_system_top_v005.v

synth_design -top ha_tff_system_top_v005 -part xc7a100tcsg324-1

# Timing constraints for 156.25 MHz clock
create_clock -period 6.400 -name clk [get_ports clk]

# Reports
report_utilization -file ../reports/utilization_report.txt
report_timing_summary -file ../reports/timing_summary.txt
report_power -file ../reports/power_report.txt

# Save checkpoint
write_checkpoint -force ../reports/ha_tff_system_top_v005_synth.dcp
