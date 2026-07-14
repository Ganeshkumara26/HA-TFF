# ADR-004: Memory Primitive Selection

**Status:** Accepted
**Date:** Week 4 (v004)

## Context
The Cuckoo Hash Datapath requires 4 independent memory banks to store 104-bit tuples and a 1-bit "Action" flag (Drop/Forward). We need to store 4096 entries per bank. This requires 105 bits * 4096 entries = 430 Kbits per bank.

## Options Considered

### Option A: Distributed RAM (LUTRAM)
Synthesize the memory directly out of FPGA fabric LUTs.
- **Pros:** Asynchronous reads are possible, reducing latency to 0 cycles.
- **Cons:** (PHYSICS FIRST: LUT Utilization). 430 Kbits per bank * 4 banks = 1.7 Megabits. Implementing 1.7 Mb in LUTRAM would consume almost the entire Artix-7 logic fabric, leaving no room for the parser or datapath logic.

### Option B: Block RAM (BRAM36E1)
Instantiate Xilinx 36Kb Block RAM primitives.
- **Pros:** Extremely dense. BRAMs are hard IP blocks built exactly for this.
- **Cons:** BRAM reads are strictly synchronous. This adds 1 cycle of read latency to the datapath.

## Decision
**Option B (Block RAM)** is selected. 

## Engineering Justification
We must respect the physical silicon area. LUTRAM is for shallow FIFOs, not bulk storage. We will accept the 1-cycle latency penalty of synchronous BRAM reads. To maximize flexibility, we will write a parameterized Verilog module (`ha_tff_bram_bank.v`) so Vivado can infer the BRAMs rather than instantiating `RAMB36E1` primitives directly, making the code portable.

## Dependencies
- **Derived From:** N/A
- **Implements:** `REQ-v003`
- **Creates:** `RTL-v004/ha_tff_bram_bank.v`
- **Verified By:** Pending
