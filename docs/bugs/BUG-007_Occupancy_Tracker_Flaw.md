# BUG-007: Occupancy Tracker Flaw

## Description
The `ha_tff_performance_monitor.v` module attempted to measure both packet latency and active packet occupancy concurrently. However, it gated the `active_packets` counter based on the latency `measuring` state flag. This prevented it from accurately counting concurrent or back-to-back packets, leading to a wildly inaccurate `stat_peak_occupancy` metric under heavy load.

## Root Cause
- The `active_packets` variable was tightly coupled to the `measuring` flag, which was designed to track the latency of a single packet at a time.
- Start-of-packet (SOP) and end-of-packet (EOP) events were only registered when `measuring` was false or true respectively, ignoring interlaced or back-to-back packet streams.

## Fix
- Decoupled the occupancy tracking logic from the latency measurement logic.
- Implemented independent edge detection for ingress SOP (via `s_axis_tvalid` rising edge) and egress EOP (via `m_axis_tvalid & m_axis_tlast`).
- The `active_packets` counter now cleanly increments on ingress and decrements on egress independently of the sampled latency tracker.
