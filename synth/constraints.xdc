## constraints.xdc - Nexys A7 100T pin assignments for HA-TFF
##
## oct 2, 2026
##
## i copied these from the digilent master xdc file. the nexys a7
## has an SMSC 10/100 Ethernet PHY connected via RMII.
##
## NOTE: in the final system (bharatedge-soc), these constraints are
## managed by fusesoc/veerwolf. this file is just for synthesizing
## the filter alone to get resource/timing estimates.

## Clock signal (100 MHz from board oscillator)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## Reset (CPU_RESET push button, active low)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

## SMSC Ethernet PHY (RMII interface)
## these map to the AXI-Stream inputs in our top level, though we
## need a small RMII-to-AXIS wrapper to actually use them on hardware.
## for synthesis estimates, we just map them directly to prevent them
## from being optimized away.
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { s_tdata[0] }]; # ETH_MDC
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { s_tdata[1] }]; # ETH_MDIO
set_property -dict { PACKAGE_PIN B3    IOSTANDARD LVCMOS33 } [get_ports { s_tdata[2] }]; # ETH_RSTN
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { s_tdata[3] }]; # ETH_CRSDV
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { s_tdata[4] }]; # ETH_RXERR
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { s_tdata[5] }]; # ETH_RXD0
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { s_tdata[6] }]; # ETH_RXD1
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { s_tdata[7] }]; # ETH_TXEN
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { s_tvalid }];   # ETH_TXD0
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { s_tlast }];    # ETH_TXD1

## Virtual clock for the Wishbone interface (assuming it runs synchronously)
## Vivado will complain if we don't constrain the WB inputs, but since
## we are just synthesizing for area estimates, we use false paths to
## ignore IO timing on the WB bus.
set_false_path -from [get_ports {wb_*}]
set_false_path -to [get_ports {wb_*}]
