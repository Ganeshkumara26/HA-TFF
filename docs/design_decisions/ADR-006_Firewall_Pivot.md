# ADR-006: Anomaly Detection Architecture (DNN vs SNN)

**Status:** Accepted
**Date:** Week 6 (v006)

## Context
We need to add AI-based anomaly detection to the firewall. The Artix-7 100T has only 240 DSP slices.

## Options Considered

### Option A: Standard Deep Neural Network (DNN / MLP)
Use a standard Multi-Layer Perceptron trained on network features.
- **Pros:** Easy to train in PyTorch. High accuracy.
- **Cons:** (PHYSICS FIRST: DSP Utilization). A single layer of 16 neurons with 8 inputs requires 128 multipliers. Running this at 156.25 MHz without heavy pipelining is impossible. Floating point or even 8-bit integer MAC operations consume too much power and area.

### Option B: Spiking Neural Network (SNN)
Use Leaky Integrate-and-Fire (LIF) neurons that process binary spikes.
- **Pros:** Spike-based multiplication is just addition (if spike=1, add weight; if spike=0, add 0). This completely eliminates the need for hardware multipliers (DSP slices). We only need adders and registers.
- **Cons:** Extremely difficult to train. Requires translating network packets into binary "spikes" over time.

## Decision
**Option B (Spiking Neural Network)** is selected.

## Engineering Justification (Physics First)
To build an AI coprocessor that runs at 156.25 MHz alongside a full Cuckoo Hash datapath, we must eliminate multipliers. The SNN translates MAC operations into simple accumulators. We will accept the research debt of figuring out how to train and encode spikes.

## Dependencies
- **Derived From:** N/A
- **Implements:** `REQ-v006`
- **Creates:** `ARCH-v006`
- **Verified By:** Pending
- **Supersedes:** `REQ-v003` (Exact-match alone is no longer the sole goal).
