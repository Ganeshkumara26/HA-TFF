# ADR-003: Exact Match Datapath & Hashing Algorithm

**Status:** Accepted
**Date:** Week 3 (v003)

## Context
To achieve exact-match lookups using BRAM instead of TCAM, we must map the 104-bit 5-tuple into a smaller memory address (e.g., 12-bit address for 4096 entries). This requires a Hash Table. Standard hash tables suffer from collisions, which ruin deterministic latency. 

We will adopt a **4-way Cuckoo Hash** architecture, which guarantees O(1) deterministic lookup time. However, Cuckoo Hashing requires 4 *independent* hash functions to calculate 4 different memory addresses simultaneously.

## Options Considered for the Hash Functions

### Option A: Cryptographic Hashing (SipHash / Toeplitz)
Use standardized, mathematically secure hash functions.
- **Pros:** Excellent avalanche effect. Cryptographically secure against Algorithmic Complexity Attacks (where an attacker crafts packets to intentionally cause hash collisions).
- **Cons:** Very deep logic. Requires multiple clock cycles to compute, which violates our 1-cycle throughput constraint unless heavily pipelined, costing massive amounts of DSP slices and LUTs. (PHYSICS FIRST: Logic depth and Resource limits).

### Option B: CRC32
Use 4 parallel CRC32 generators with different polynomials.
- **Pros:** Standard networking approach. Good spatial distribution.
- **Cons:** Calculating a 104-bit CRC in a single clock cycle requires a massive XOR tree. 4 parallel CRCs would consume a large percentage of the Artix-7 LUTs and likely fail 156.25 MHz timing.

### Option C: Custom Combinatorial XOR Folding
Divide the 104-bit tuple into 12-bit chunks and XOR them together. Create 4 variations using bit-reversal, static shifting, and different seed constants.
- **Pros:** Extremely fast (1 logic level of 9-input XOR gates). Minimal LUT utilization.
- **Cons:** Very weak cryptographic properties. Highly vulnerable to adversarial collision attacks.

## Decision
**Option C (Custom Combinatorial XOR Folding)** is selected.

## Engineering Justification (Physics First)
To maintain the required 156.25 MHz clock frequency and minimize LUT usage on the Artix-7, we must sacrifice cryptographic security for speed. The logic depth of a 9-input XOR tree is easily absorbed by 2 LUT6s in series. We accept the risk of adversarial collisions as an "Engineering Debt" for this prototype.

## Dependencies
- **Derived From:** N/A
- **Implements:** `REQ-v003`
- **Creates:** `RTL-v003/ha_tff_hash_v001.v`
- **Verified By:** Pending
- **Synthesized By:** Pending
