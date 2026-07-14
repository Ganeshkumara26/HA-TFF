# HA-TFF: Hardware-Accelerated Traffic Filter Firewall

A hybrid FPGA-based network security processor combining **line-rate exact-match packet inspection** with a **Spiking Neural Network (SNN) coprocessor** for zero-day anomaly detection. Designed for the Xilinx Artix-7 (xc7a100t) at 156.25 MHz (10GbE line rate).

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │            ha_tff_system_top_v005               │
                    │                                                 │
  AXI4-Lite ──────►│  ┌─────────────────┐                            │
  (CPU Control)     │  │ AXI-Lite Regs   │──► Hash Key + SNN Weights │
                    │  └─────────────────┘                            │
                    │                                                 │
                    │  ┌─────────────────────────────────────┐        │
  AXI4-Stream ────►│  │        Firewall Datapath             │        │
  (10GbE MAC)       │  │  Parser → Hash → BRAM → Matcher     │        │
                    │  └────────────────────┬────────────────┘        │
                    │                       │ match result            │
                    │  ┌────────────────────┤                        │
                    │  │   SNN Coprocessor  │                        │
                    │  │  Encoder → LIF     │                        │
                    │  │  Neurons → Spike   │                        │
                    │  └────────────────────┤                        │
                    │                       ▼                        │
                    │  ┌─────────────────────────────────────┐        │
                    │  │  Decision: forward = match AND       │───────►│ AXI4-Stream
                    │  │            !anomaly_detected         │        │ (To Network)
                    │  └─────────────────────────────────────┘        │
                    │                                                 │
                    │  ┌─────────────────────────────────────┐        │
                    │  │  AXI-Stream Delay Line (6 cycles)   │        │
                    │  │  Synchronizes data with decision    │        │
                    │  └─────────────────────────────────────┘        │
                    └─────────────────────────────────────────────────┘
```

## Key Features

| Feature | Implementation | Details |
|---------|---------------|---------|
| **Packet Parsing** | 64-bit AXI4-Stream FSM | Extracts 5-tuple (src/dst IP, src/dst port, protocol) from Ethernet/IPv4/UDP/TCP frames |
| **Exact-Match Lookup** | 4-bank Cuckoo Hash | Parallel BRAM-based lookup with XOR-folding hash, keyed with 128-bit secret (anti-DDoS) |
| **Anomaly Detection** | Spiking Neural Network | 2-neuron LIF layer with bit-shift leak (zero DSP slices), dynamic weights via AXI-Lite |
| **Control Plane** | AXI4-Lite Register File | Runtime-configurable SNN weights and hash secret key from a CPU |
| **Pipeline Sync** | Parameterized Delay Line | 6-cycle shift register aligns packet data with the combined rule + SNN decision |
| **Decision Latency** | 6 clock cycles | ~38 ns at 156.25 MHz |

## Synthesis Results (Vivado 2026.1, Artix-7 xc7a100t)

| Resource | Used | Available | Utilization |
|----------|------|-----------|:-----------:|
| Slice LUTs | 505 | 63,400 | 0.80% |
| Slice Registers | 799 | 126,800 | 0.63% |
| Block RAM (36Kb) | 23 | 135 | 17.04% |
| Block RAM (18Kb) | 3 | 270 | 1.11% |
| DSP Slices | **0** | 240 | **0.00%** |
| IOBs | 151 | 210 | 71.90% |

> **Zero DSP slices**: The SNN uses bit-shift arithmetic (`>>>`) instead of multipliers, making it massively scalable.

## Repository Structure

```
ha-tff-fpga/
├── rtl/                          # Synthesizable Verilog RTL
│   ├── ha_tff_system_top_v005.v  # Top-level system integration
│   ├── ha_tff_datapath_top_v003.v# Firewall datapath wrapper
│   ├── ha_tff_parser_v002.v      # Ethernet/IPv4/UDP parser FSM
│   ├── ha_tff_hash_v002.v        # Keyed XOR-fold hash (4 seeds)
│   ├── ha_tff_bram_bank.v        # Parameterized BRAM bank (4096×128b)
│   ├── ha_tff_matcher_v002.v     # 4-way pipelined exact-match engine
│   ├── ha_tff_axi_lite_regs.v    # AXI4-Lite slave register file
│   ├── axi_stream_delay_line.v   # Parameterized pipeline delay
│   ├── snn_feature_encoder.v     # Packet metadata → spike vector
│   ├── snn_tff_layer_v005.v      # SNN layer with dynamic weights
│   └── snn_tff_neuron_v004.v     # Pipelined LIF neuron
├── tb/                           # Testbenches
│   └── tb_ha_tff_system_top.v    # System-level testbench
├── sim/                          # Simulation data
│   ├── bank0.mem                 # BRAM initialization (Cuckoo table)
│   ├── bank1.mem
│   ├── bank2.mem
│   └── bank3.mem
├── constraints/                  # Synthesis scripts
│   └── synth.tcl                 # Vivado synthesis TCL
├── reports/                      # Synthesis reports
│   └── utilization_report.txt    # Vivado resource utilization
├── docs/                         # Documentation
│   ├── chronicle.pdf             # Full engineering thesis
│   ├── LIF_Neuron_Formulation.md # Math: ODE → discrete → bit-shift
│   ├── Final_Takeaway_Report.md  # Project summary
│   ├── design_decisions/         # Architecture Decision Records
│   └── bugs/                     # Documented bug reports
├── LICENSE
├── .gitignore
└── README.md
```

## Engineering History

This project went through **12 design iterations** with **5 documented bug reports**. The version numbers in module names are intentional — they reflect the engineering evolution:

| Iteration | Focus | Key Decision |
|:---------:|-------|-------------|
| v001 | Parsing | AXI4-Stream metadata extraction |
| v002 | Parser | Pipeline stage added for timing closure at 6.4ns |
| v003–v004 | Hashing | Cuckoo Hash with BRAM banks; eviction limit for deadlock prevention |
| v005 | Datapath | Integrated 4-way parallel matcher with delay line synchronization |
| v006 | Pivot | Static rules insufficient → designed LIF neuron for anomaly detection |
| v007–v009 | SNN | Built LIF neuron, SNN layer, feature encoder |
| v010 | Integration | System stitched; Vivado dead code elimination bug found (BUG-005) |
| v011 | Timing | Discovered -0.465ns WNS in LIF arithmetic critical path |
| v012 | **Fix** | **Pipelined LIF into 2 stages → WNS positive → timing closure achieved** |

## Bug Reports

| ID | Title | Root Cause | Fix |
|----|-------|-----------|-----|
| BUG-001 | Tuple Valid Timeout | Parser `tuple_valid` not clearing properly | Added timeout counter |
| BUG-003 | SNN Leak Gating | Leak was not gated by `valid_in`, causing free-running decay | Gated leak with valid signal |
| BUG-004 | Unsigned Threshold | Signed comparison failed due to unsigned wire declaration | Changed to explicit `signed` type |
| BUG-005 | Dead Code Elimination | Vivado optimized out SNN because output was unconnected | Connected `anomaly_detected` to output gate |

## Quick Start

### Simulation (Icarus Verilog)
```bash
cd sim
iverilog -o sim.vvp -I ../rtl ../rtl/*.v ../tb/tb_ha_tff_system_top.v
vvp sim.vvp
gtkwave tb_ha_tff_system_top.vcd
```

### Synthesis (Vivado)
```bash
cd constraints
vivado -mode batch -source synth.tcl
```

## SNN: How It Works

The Spiking Neural Network classifies network traffic as "Safe" or "Anomaly" using biologically-inspired Leaky Integrate-and-Fire neurons:

1. **Feature Encoding**: The `snn_feature_encoder` converts packet metadata into an 8-bit spike vector (TCP?, UDP?, high port?, broadcast?, known-bad subnet?, DNS port?, etc.)

2. **Synaptic Integration**: Each spike is multiplied by a signed 16-bit weight (loaded via AXI-Lite) and summed to produce synaptic current.

3. **LIF Dynamics** (zero DSP):
   ```
   U_decay[t] = U[t-1] - (U[t-1] >>> LEAK_SHIFT)   // Bit-shift leak ≈ α=0.875
   U_temp[t]  = U_decay[t] + I[t]                    // Integration
   if (U_temp >= THRESHOLD) → spike, reset to 0       // Fire & reset
   ```

4. **Decision**: If `neuron_anomaly` spikes → `anomaly_detected = 1` → all traffic is dropped until `neuron_safe` spikes.

See [LIF_Neuron_Formulation.md](docs/LIF_Neuron_Formulation.md) for the full mathematical derivation from continuous ODE → discrete time → hardware bit-shift approximation.

## License

MIT License. See [LICENSE](LICENSE).
