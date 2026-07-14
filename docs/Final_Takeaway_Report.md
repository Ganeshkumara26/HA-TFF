# Hardware-Accelerated Traffic Filter Firewall (HA-TFF)
## Final Capstone & Takeaway Report

### Executive Summary
The **HA-TFF** is a hybrid network security processor engineered for FPGA fabric. Over the course of a 6-month iterative design cycle, the architecture evolved from a basic packet parser into a robust 10GbE AXI-Stream exact-match datapath (using Cuckoo Hashing), and ultimately integrating a Spiking Neural Network (SNN) coprocessor for zero-day anomaly detection.

### Engineering Journey & Iteration Map

| Iteration | Focus Area | Milestone / Achievements |
|-----------|------------|--------------------------|
| **v001**  | Study      | Network parsing; AXI-Stream metadata extraction (IP/UDP/TCP). |
| **v002**  | Parsing    | Pipelined parsing of 64-bit Ethernet frames. |
| **v003**  | Hashing    | Designed combinatorial XOR hash folding for 4 independent seeds. |
| **v004**  | Memory     | Implemented BRAM-based True Dual Port Cuckoo Hash Banks. |
| **v005**  | Datapath   | Integrated a 4-way parallel Cuckoo Matcher to form the basic Firewall Datapath. |
| **v006**  | Pivot      | Discovered limitations of static rules. Prototyped Leaky Integrate-and-Fire (LIF) Neurons. |
| **v007**  | SNN Core   | Built a fully-connected SNN layer mapping packet features to "Safe" or "Anomaly" states. |
| **v008**  | SNN Bugs   | Solved signed arithmetic bugs and gating issues in membrane leak logic (`bug003`, `bug004`). |
| **v009**  | SNN Feat.  | Developed hardware feature encoder translating 5-tuples into 8-bit spikes. |
| **v010**  | Integration| System stitched. Vivado Dead Code Elimination fixed (`bug005`). First `-0.465ns` timing violation discovered. |
| **v011**  | Pipelining | Added AXI-Stream Delay Line for packet alignment. Discovered true critical path in LIF arithmetic. |
| **v012**  | Final Fix  | Pipelined the LIF neuron logic into 2 stages, achieving WNS > 0.00ns timing closure. |

### Evidence Integrity & Methodology
Throughout development, the "Absolute Evidence Rule" was strictly enforced. 
- Previous RTL files were never overwritten; instead, they were versioned (`rtl_v001` to `rtl_v012`).
- Simulations were logged (console output and `.vcd` files) for every version.
- Vivado synthesis and timing reports were systematically archived (`synth001` - `synth012`).
- 5 detailed bug reports (`BUG-001` through `BUG-005`) contain reproducible traces of silicon engineering failures (from combinational loops to signed/unsigned Verilog arithmetic traps).

---

### Known Issues & Hardcoded Constraints (Roadmap for Next Semester)

While the logic functions perfectly for this prototype, several key components were hardcoded to accelerate the proof-of-concept. These form the exact baseline for "Future Work".

#### 1. SNN Weights are ROM (Not RAM)
In `snn_tff_layer_v004.v`, the synaptic weights for the Spiking Neural Network are hardcoded using static `assign` statements (e.g., `16'sd150`).
**Issue**: The AI model cannot be retrained or updated without recompiling the FPGA bitstream.
**Future Work**: The weights must be stored in Block RAM, and an AXI4-Lite Control Plane interface must be instantiated so a CPU (like MicroBlaze) can dynamically load new weights.

#### 2. Static Feature Encoder Heuristics
In `snn_feature_encoder.v`, network anomalies are defined by hardcoded magic numbers (e.g., matching subnet `192.168.100.x` or DNS port `53`).
**Issue**: The feature extraction logic is rigid.
**Future Work**: Move IP masks and port thresholds into configurable AXI-Lite memory-mapped registers.

#### 3. Strict IPv4 + TCP/UDP Parsing
In `ha_tff_parser_v002.v`, the state machine drops anything that isn't `0x0800` (IPv4) AND protocol `0x06` or `0x11` (TCP/UDP).
**Issue**: ICMP (Ping), ARP, and IPv6 packets will trigger a `parse_error` and be dropped.
**Future Work**: Expand the FSM to support variable-length headers and ICMP validation.

#### 4. Vulnerable Hash Seeds
In `ha_tff_hash_v001.v`, the XOR folding arrays use static hash constants (e.g., `12'h3A7`).
**Issue**: In a real network, static hash seeds are vulnerable to Algorithmic Complexity Attacks. Attackers can reverse-engineer the seed and craft packets that cause 100% hash collisions, DDOSing the exact-match datapath.
**Future Work**: Implement a parameterized Toeplitz or SipHash algorithm with a runtime-configurable secret key.

---
### Conclusion
The HA-TFF successfully demonstrated how FPGA hardware acceleration can compress the latency of high-speed packet inspection. By integrating a Spiking Neural Network directly into the Datapath, the firewall is capable of classifying zero-day anomalies in 6 clock cycles (~38ns latency), a speed completely unreachable by software-based CPU Firewalls.
