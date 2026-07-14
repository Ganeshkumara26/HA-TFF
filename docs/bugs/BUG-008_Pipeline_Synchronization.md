# BUG-008: Pipeline Synchronization

## Description
The top-level integration (`ha_tff_system_top.v`) suffered from a severe pipeline synchronization issue. The datapath decision (forward vs drop) emerged from the Matcher as a single-cycle pulse. The packet payload was delayed by a 6-cycle `axi_stream_delay_line`. However, the full datapath latency (Parser + Hash + BRAM + Matcher) was approximately 11-13 cycles. Consequently, the delay line was too short, and the 1-cycle decision pulse could not properly gate multi-cycle AXI-Stream packets, leading to dropped frames and protocol corruption.

## Root Cause
- The `axi_stream_delay_line` was parameterized to 6 cycles, which was shorter than the actual Cuckoo-hash pipeline depth.
- The `pkt_active` and `pkt_forward` state machines relied on catching a 1-cycle `dp_match_valid` pulse precisely when the first word of the packet emerged from the delay line. This brittle timing caused the firewall to inadvertently drop trailing words of packets.

## Fix
- Increased the `axi_stream_delay_line` parameter to 16 cycles to comfortably cover the maximum datapath latency.
- Introduced a 32-entry **Decision FIFO** (`decision_fifo`) in the top-level module. The 1-cycle `dp_match_valid` pulse (or `parse_error`) writes a 1-bit decision (forward or drop) into the FIFO.
- As the packet's first word emerges from the 16-cycle delay line, the state machine pops the decision from the FIFO and holds it for the entire duration of the packet (until `delayed_tlast`). This guarantees robust, clock-domain-safe framing alignment.
