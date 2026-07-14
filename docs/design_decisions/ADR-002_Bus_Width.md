# ADR-002: Parser Bus Width (8-bit vs 64-bit)

**Status:** Accepted
**Date:** Week 2 (v002)

## Context
The v001 parser was built around an 8-bit `s_axis_tdata` interface. While it successfully extracted the 5-tuple in simulation (`SIM-001`), the mathematical model revealed a fatal flaw: it requires a 1.25 GHz clock to process a 10Gbps stream.

## Options Considered

### Option A: Clock Domain Crossing (CDC) with Gearbox
Keep the 8-bit parser and use an asymmetric FIFO to convert the 64-bit/156.25MHz input into an 8-bit/1.25GHz output.
- **Pros:** Preserves the existing v001 RTL state machine.
- **Cons:** Violates fundamental silicon constraints (PHYSICS FIRST). The Artix-7 cannot route logic at 1.25 GHz. This option is physically impossible on our target hardware.

### Option B: Word-Aligned 64-bit FSM
Rewrite the parser to process 64-bits (8 bytes) simultaneously per clock cycle. The FSM will count 64-bit words rather than individual bytes.
- **Pros:** Drops the required clock frequency to 156.25 MHz, which is easily achievable on Artix-7.
- **Cons:** The slicing logic becomes wider and slightly more complex, as multiple bytes of a specific header field (e.g., Source IP) might be split across a 64-bit word boundary.

## Decision
**Option B (Word-Aligned 64-bit FSM)** is selected.

## Engineering Justification (Physics First)
We are physically bound by the $F_{max}$ of the FPGA fabric. To achieve 10GbE throughput, we must increase the datapath width to lower the clock frequency. `10Gbps / 64-bits = 156.25 MHz`.

## Dependencies
- **Derived From:** `ADR-001` (Supersedes it)
- **Implements:** `REQ-v002`
- **Creates:** `RTL-v002/ha_tff_parser.v`
- **Verified By:** N/A (Simulations pending)
- **Synthesized By:** N/A
