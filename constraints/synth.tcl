# Vivado Synthesis Script for HA-TFF System (Telemetry Firewall revision)
# Target: Xilinx Artix-7 xc7a100tfgg484-1
# Clock: 156.25 MHz (6.4ns period) — 10GbE line rate

create_project -in_memory -part xc7a100tfgg484-1

# Read all RTL source files
read_verilog ../rtl/ha_tff_parser.v
read_verilog ../rtl/ha_tff_hash.v
read_verilog ../rtl/ha_tff_bram_bank.v
read_verilog ../rtl/ha_tff_matcher.v
read_verilog ../rtl/ha_tff_datapath_top.v
read_verilog ../rtl/ha_tff_axi_lite_regs.v
read_verilog ../rtl/ha_tff_statistics.v
read_verilog ../rtl/ha_tff_performance_monitor.v
read_verilog ../rtl/axi_stream_delay_line.v
read_verilog ../rtl/ha_tff_system_top.v

synth_design -top ha_tff_system_top -part xc7a100tfgg484-1

# Timing constraints for 156.25 MHz clock
create_clock -period 6.400 -name clk [get_ports clk]

# Reports
report_utilization -file ../reports/utilization_report.txt
report_timing_summary -file ../reports/timing_summary.txt
report_power -file ../reports/power_report.txt

# Save checkpoint
write_checkpoint -force ../reports/ha_tff_system_top_synth.dcp
