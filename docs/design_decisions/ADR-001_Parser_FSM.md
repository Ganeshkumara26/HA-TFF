# ADR-001: Parser Architecture (FSM vs Combinatorial Shift)

**Status:** Accepted
**Date:** Week 1 (v001)

## Context
We need to parse 64-bit AXI-Stream data arriving at 156.25 MHz to extract a 104-bit 5-tuple. The Ethernet/IPv4/UDP headers span across approximately 42 bytes (6 clock cycles).

## Options Considered

### Option A: Fully Combinatorial Shift Register (Wide Bus)
Buffer the entire 42-byte header into a massive 336-bit register, and then use combinatorial slicing to extract the fields all at once.
- **Pros:** Conceptually simple. Output is available on a single cycle.
- **Cons:** Extremely high fanout and routing congestion. The Artix-7 fabric will struggle to meet 6.4ns timing with 336-bit wide multiplexers. (PHYSICS FIRST: Routing delay).

### Option B: Word-by-Word FSM (Fixed Offset)
Use a 4-state state machine. As each 64-bit word arrives, directly latch the relevant bytes into the output registers.
- **Pros:** Minimal routing congestion. Each 64-bit word is processed immediately without buffering the entire header. Timing closure is almost guaranteed.
- **Cons:** Rigid. Assumes fixed offsets (cannot handle IP Options easily, see Q001).

## Decision
**Option B (Word-by-Word FSM)** is selected.

## Engineering Justification (Physics First)
To sustain a 6.4ns clock period, we cannot afford the massive routing delays associated with a 336-bit wide shift-and-slice architecture. A finite state machine matching the word arrival pattern minimizes logic levels. 

## Dependencies
- **Derived From:** N/A
- **Implements:** `REQ-v001`
- **Creates:** `RTL-v001/ha_tff_parser_v001.v`
- **Verified By:** `SIM-001`
- **Synthesized By:** `SYNTH-001`
