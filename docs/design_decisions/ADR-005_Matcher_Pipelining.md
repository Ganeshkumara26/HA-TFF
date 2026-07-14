# ADR-005: Matcher Pipelining

**Status:** Accepted
**Date:** Week 5 (v005)

## Context
The Cuckoo Matcher receives the original 104-bit parsed tuple and four 105-bit candidates from the 4 BRAM banks. It must perform four parallel 104-bit equality comparisons to determine if the tuple is found, and if so, extract the associated 1-bit action (Drop/Forward).

## Options Considered

### Option A: Combinatorial Matcher (`ha_tff_matcher_v001`)
Perform the 4 parallel 104-bit comparisons and the priority multiplexing all in a single clock cycle.
- **Pros:** Saves 1 clock cycle of latency.
- **Cons:** (PHYSICS FIRST: Logic Depth). A 104-bit equality comparator requires a wide AND-tree. Doing 4 of them and multiplexing the result takes at least 4 logic levels. When combined with the routing from the BRAM output pins, this is a massive risk for the 6.4ns timing constraint.

### Option B: Pipelined Matcher (`ha_tff_matcher_v002`)
Register the results of the comparisons.
- **Pros:** Breaks the critical path. Almost guarantees timing closure.
- **Cons:** Adds 1 cycle of latency to the firewall decision.

## Decision
**Option B (Pipelined Matcher)** is selected.

## Engineering Justification
We originally drafted Option A (`matcher_unpipelined_v001`), but discarded it almost immediately after writing the math model. The routing delay from 4 physically distributed BRAM banks into a centralized comparator tree is too long. We accept the 1-cycle latency penalty.

## Dependencies
- **Derived From:** `ADR-004`
- **Implements:** `REQ-v005`
- **Creates:** `RTL-v005/ha_tff_matcher_v002.v`, `RTL-v005/ha_tff_datapath_top_v002.v`
- **Discarded:** `05_RTL/Discarded/historical/matcher_unpipelined_v001` (Reasoning documented, RTL not saved as it was aborted mid-write).
