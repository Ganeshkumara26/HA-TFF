# synth.tcl - Vivado synthesis script for ha-tff-rtl
# 
# Usage: vivado -mode batch -source synth.tcl

# create project in a temp directory so we don't pollute the repo
create_project -force ha_tff_synth ./vivado_project -part xc7a100tcsg324-1

# add RTL files
add_files ../rtl/ha_tff_pkg.sv
add_files ../rtl/eth_parser.sv
add_files ../rtl/mav_filter.sv
add_files ../rtl/telem_fifo.sv
add_files ../rtl/wb_slave.sv
add_files ../rtl/ha_tff_top.sv

# add constraints
add_files constraints.xdc

# set top module
set_property top ha_tff_top [current_fileset]

# run synthesis
synth_design -top ha_tff_top -part xc7a100tcsg324-1

# report utilization
report_utilization -file utilization.rpt

# report timing
report_timing_summary -file timing.rpt

# clean up project
close_project
