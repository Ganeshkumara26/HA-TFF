# ADR-007: SNN Topology (Fully Connected vs Convolutional)

**Status:** Accepted
**Date:** Week 7 (v007)

## Context
We are designing the AI Coprocessor. We need a network topology that translates extracted packet features into an Anomaly classification.

## Options Considered

### Option A: Convolutional SNN (CSNN)
Slide a spike filter over the packet payload over time.
- **Pros:** Excellent for temporal pattern recognition (like finding a specific malware signature inside a payload).
- **Cons:** Requires buffering the entire packet payload, massive shift registers, and huge routing congestion.

### Option B: Fully Connected SNN (Shallow)
Use a single, shallow dense layer mapping 8 input "Features" to 2 output Neurons ("Safe" and "Anomaly").
- **Pros:** Extremely fast. Low logic utilization (16 weights total). 
- **Cons:** Cannot "scan" the payload. Must rely on a separate Feature Encoder to summarize the packet into 8 spikes before feeding the SNN.

## Decision
**Option B (Fully Connected Shallow SNN)** is selected.

## Engineering Justification (Physics First)
We do not have the fabric area or the BRAM to buffer entire 1500-byte Jumbo frames for convolutional sliding windows. We must summarize the packet immediately and feed it into a lightweight, fully connected layer to meet our 6.4ns timing and area constraints.

## Dependencies
- **Derived From:** `ADR-006`
- **Implements:** `REQ-v006`
- **Creates:** `RTL-v007/snn_tff_layer_v001.v`
- **Verified By:** Pending
