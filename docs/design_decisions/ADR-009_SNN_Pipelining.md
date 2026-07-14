# ADR-012: SNN Arithmetic Pipelining

**Status:** Accepted
**Date:** Week 12 (v012)

## Context
In `v011`, we discovered that the system failed timing (`WNS = -0.400ns`). The critical path (`BUG-006`) traced through the `snn_tff_layer` sum, directly into the `snn_tff_neuron` leak logic (Right Shift), then into the membrane adder, and finally into the threshold comparator. This logic depth (Sum + Shift + Add + Compare) cannot physically complete in 6.4ns on an Artix-7.

## Options Considered

### Option A: Retiming / Logic Optimization
Rely on Vivado `phys_opt_design` to aggressively retime the registers backwards.
- **Pros:** No RTL changes required.
- **Cons:** Synthesis proved it was not enough. The logic depth is simply too deep.

### Option B: 2-Stage Neuron Pipeline
Break the `snn_tff_neuron` into two clock cycles.
- Stage 1: Calculate `u_decayed` and perform the synaptic addition (`u_temp`). Register the result.
- Stage 2: Compare `u_temp` against `THRESHOLD` to generate the spike, and update the final membrane potential.
- **Pros:** Slices the critical path exactly in half. Guarantees timing closure.
- **Cons:** Increases the SNN latency from 3 cycles to 5 cycles. Because the Datapath decision only takes 4 cycles, we will have to add a 1-cycle delay register to the Datapath output so that both decisions arrive at the top-level AND gate simultaneously.

## Decision
**Option B (2-Stage Neuron Pipeline)** is selected.

## Engineering Justification (Physics First)
To close timing on an FPGA, you must pipeline. We accept the 1-cycle latency penalty. Aligning the Datapath requires just one extra Flip-Flop, which is practically free in the fabric.

## Dependencies
- **Derived From:** `BUG-006`
- **Implements:** Timing Closure
- **Creates:** `RTL-v012/snn_tff_neuron_v004.v`
- **Verified By:** `TIM-012` (WNS = +0.517ns)
