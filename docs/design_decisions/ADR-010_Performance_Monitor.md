# ADR-010: Performance Monitor Integration

## Context
The `ha_tff_performance_monitor.v` module was designed to provide in-depth telemetry regarding datapath health, specifically tracking RX/TX stalls (when AXI-Stream valid is asserted but ready is not), real-time packet occupancy, and a latency histogram. However, it was not initially integrated into the `ha_tff_system_top` or the AXI4-Lite memory map, leaving these crucial metrics inaccessible to the control plane.

## Decision
We fully integrated the Performance Monitor into the system top and AXI-Lite register map, alongside resolving the IOB overutilization constraints by targeting the larger `xc7a100tfgg484-1` package. 

- The monitor is instantiated at the top level and taps the ingress and egress AXI-Stream buses.
- The AXI4-Lite memory map in `ha_tff_axi_lite_regs.v` was expanded to expose 6 new 32-bit registers (offsets `0x64` to `0x78`) to provide software access to stalls, occupancy, and latency metrics.

## Consequences
- **Positive**: The control plane now has deep visibility into the real-time health and latency of the datapath, crucial for enterprise firewall monitoring.
- **Positive**: Resolves the open item regarding the isolated monitor module.
- **Negative (Minor)**: Slightly increases resource utilization (LUTs and Registers) to maintain the telemetry counters. The new FPGA target package natively supports the wide pinout without functional compromises.
