# ADR-008: SNN Verilog Type Architecture

**Status:** Accepted
**Date:** Week 8 (v008)

## Context
Bugs `BUG-003` and `BUG-004` revealed that relying on implicit Verilog casting for Neural Network arithmetic is catastrophic. A single unsigned comparison caused inhibitory signals to trigger massive spike cascades.

## Decision
We establish a strict type architecture for the SNN module:
1. Every mathematical wire and register MUST explicitly declare the `signed` keyword.
2. Every mathematical parameter MUST explicitly define its bit-width and sign (e.g., `16'sd1000`).
3. To prevent negative integer wrapping, we must add an explicit floor clamp: `if (u_temp < -16'sd2000) membrane_u <= -16'sd2000`.

## Dependencies
- **Derived From:** `BUG-004`
- **Implements:** `REQ-v006`
- **Creates:** `RTL-v008/snn_tff_neuron_v003.v`
- **Verified By:** Pending Simulation
