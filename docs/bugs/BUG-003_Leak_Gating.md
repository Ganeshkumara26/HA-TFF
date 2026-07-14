# BUG-003: SNN Leak Gating Error

**Date:** Week 8 (v008)
**Status:** Resolved

## Symptom
During the first simulation of `snn_tff_neuron_v001`, the membrane potential `U` would not leak back to 0. If it reached 100, it stayed at 100 indefinitely unless a new spike arrived.

## Root Cause
In `v001`, the leak calculation `(membrane_u >>> LEAK_SHIFT)` was placed *inside* the `if (valid_in)` block. This meant the neuron only leaked when an input spike was received. A LIF neuron must leak continuously every clock cycle, regardless of input.

## Resolution
Moved the leak calculation to an independent combinational wire `u_decayed` that is evaluated unconditionally. `v002` RTL fixed this.
