# HA-TFF: Hardware-Accelerated Telemetry Firewall

A pure-RTL, line-rate **packet classification and telemetry firewall** for FPGA. It performs
**10GbE (156.25 MHz, 64-bit AXI4-Stream)** exact-match filtering of IPv4 TCP/UDP flows and
exposes **hardware telemetry** (per-protocol packet/byte counts, drops, parse errors) to a CPU
over an AXI4-Lite control plane.


## What It Does

For every 64-bit AXI4-Stream word entering from a 10GbE MAC:

1. **Parse** the Ethernet → IPv4 → TCP/UDP header and extract the **5-tuple**
   (src/dst IP, src/dst port, protocol).
2. **Hash** the tuple with a **keyed, 4-seed XOR-fold hash** (128-bit secret loaded via AXI-Lite)
   to defeat algorithmic-complexity / hash-flooding attacks.
3. **Lookup** the hashed address in **4 parallel BRAM banks** (4096 × 128-bit each) implementing a
   Cuckoo-hash rule table.
4. **Match** the entry exactly (4-way parallel comparator) and read its action bit.
5. **Decide** the packet: forwarded only when an exact-match rule with `action = forward` exists;
   otherwise **dropped** (default-deny). The whole decision is pipelined and re-aligned to the
   original packet via a 16-cycle delay line using a Decision FIFO.
6. **Count** everything: RX/TX packets & bytes, TCP/UDP/ICMP packets, parser errors, and drops —
   all readable from the CPU through AXI4-Lite.

When the firewall is disabled (`control[0] = 0`), packets bypass the decision and are forwarded
unchanged.

## Architecture

```
                       ┌───────────────────────────────────────────────────────┐
                       │             ha_tff_system_top_v005                     │
                       │                                                       │
  AXI4-Lite ────────► │  ┌────────────────────┐                              │
  (CPU control)         │  │  AXI-Lite Regs    │──► hash secret / control     │
                         │  │  + Telemetry Read │──► statistics counters        │
                         │  └────────────────────┘                              │
                       │                                                       │
  AXI4-Stream ───────► │  ┌─────────────────────────────────────────────┐    │
  (10GbE MAC)           │  │            Firewall Datapath                │    │
                         │  │  Parser → Hash → 4×BRAM → 4-way Matcher   │    │
                         │  └───────────────┬─────────────────────────────┘    │
                       │                   │ match / action                     │
                         │  ┌────────────────┤                                 │
                         │  │ Decision: forward = match_valid AND             │──────► AXI4-Stream
                         │  │            action_forward  (else drop)           │        (To Network)
                         │  └────────────────┘                                 │
                       │                                                       │
                         │  ┌─────────────────────────────────────────────┐    │
                         │  │  AXI-Stream Delay Line (16 cycles)          │    │
                         │  │  Re-aligns packet data with the decision    │    │
                         │  │  (Decision FIFO ensures proper ordering)    │    │
                         │  └─────────────────────────────────────────────┘    │
                       │                                                       │
                         │  ┌─────────────────────────────────────────────┐    │
                         │  │  Statistics Engine                          │    │
                         │  │  RX/TX pkts+bytes, TCP/UDP/ICMP, errors,  │    │
                         │  │  drops  (→ AXI-Lite readable counters)     │    │
                         │  └─────────────────────────────────────────────┘    │
                         └───────────────────────────────────────────────────────┘
```

End-to-end pipeline latency is **16 clock cycles (~102.4 ns at 156.25 MHz)**, dominated by the
hash (1) + BRAM (2) + matcher (3-stage) decision and the 16-deep data delay line.

## Key Features

| Feature | Module | Details |
|---------|--------|---------|
| **Packet parsing** | `ha_tff_parser_v002` | 64-bit AXI4-Stream FSM; extracts 5-tuple from IPv4/TCP/UDP frames. Non-IPv4 or non-TCP/UDP → `parse_error`. |
| **Keyed hashing** | `ha_tff_hash_v002` | 4-seed XOR-fold / bit-reversed hash of the 104-bit tuple XORed with a 128-bit secret (anti-hash-flood). 1-cycle latency. |
| **Rule table** | `ha_tff_bram_bank` ×4 | Four 4096×128-bit BRAM banks = Cuckoo-hash table. `bit[127]` = valid, `bit[126]` = action (1=forward), `bit[103:0]` = tuple. |
| **Exact match** | `ha_tff_matcher_v002` | 4-way parallel 104-bit comparator with 3-stage latency alignment. Default action = **drop** (default-deny). |
| **Control plane** | `ha_tff_axi_lite_regs` | AXI4-Lite slave; runtime hash secret, firewall/parser enable, stats reset, rule programming, and telemetry read-out. |
| **Pipeline sync** | `axi_stream_delay_line` | Parameterized shift register (default 16) aligning packet bytes with the decision via Decision FIFO. |
| **Telemetry** | `ha_tff_statistics` | Counters for RX/TX packets & bytes, TCP/UDP/ICMP, parse errors, and drops. Exposed via AXI4-Lite. |
| **Performance monitor** | `ha_tff_performance_monitor` | Stall, occupancy, and latency-histogram tracking. Fully integrated into the datapath and AXI-Lite register map. |

## Repository Structure

```
ha-tff-fpga/
├── rtl/                          # Synthesizable Verilog RTL
│   ├── ha_tff_system_top_v005.v  # Top-level system integration
│   ├── ha_tff_datapath_top_v003.v# Firewall datapath wrapper (parser→hash→bram→matcher)
│   ├── ha_tff_parser_v002.v      # Ethernet/IPv4/TCP/UDP 5-tuple parser FSM
│   ├── ha_tff_hash_v002.v        # Keyed 4-seed XOR-fold hash (128-bit secret)
│   ├── ha_tff_bram_bank.v        # Parameterized BRAM bank (4096×128b)
│   ├── ha_tff_matcher_v002.v     # 4-way pipelined exact-match engine (default-deny)
│   ├── ha_tff_axi_lite_regs.v    # AXI4-Lite slave: control + rules + telemetry read
│   ├── ha_tff_statistics.v       # Telemetry counter engine
│   ├── ha_tff_performance_monitor.v # Stall/occupancy/latency monitor (integrated into top + AXI-Lite)
│   └── axi_stream_delay_line.v   # Parameterized pipeline delay
├── tb/                           # Legacy Verilog testbench (Icarus-compatible)
│   └── tb_ha_tff_system_top.v   # Basic datapath + AXI-Lite telemetry testbench
├── dv/                           # Modern SystemVerilog verification environment
│   ├── tb_ha_tff_dv_top.sv      # UVM-lite DV top: SVA bind, coverage, random traffic
│   ├── dv_packet_generator.sv    # Constrained-random packet/error generator
│   ├── ha_tff_sva.sv            # Concurrent AXI-Stream / parser assertions
│   ├── ha_tff_coverage.sv       # Functional coverage (protocols, errors, decisions)
│   └── golden_model.py           # Standalone Python (scapy) telemetry oracle
├── sim/                          # Simulation data
│   ├── bank0.mem … bank3.mem    # BRAM Cuckoo-table initialization (all-zero by default)
├── constraints/                  # Synthesis scripts
│   └── synth.tcl                # Vivado batch synthesis (Artix-7 xc7a100tfgg484-1)
├── reports/                      # Synthesis reports (Vivado 2026.1, Artix-7 xc7a100tfgg484-1)
│   ├── utilization_report.txt   # Vivado resource utilization (ha_tff_system_top_v005 + PerfMon)
│   ├── timing_summary.txt       # Timing closure report @ 156.25 MHz
│   ├── power_report.txt          # On-chip power estimation
│   └── ha_tff_system_top_v005_synth.dcp # Synthesized design checkpoint
├── docs/                        # Documentation
│   ├── design_decisions/        # Architecture Decision Records (ADR-001..010)
│   └── bugs/                    # Bug reports (BUG-001, BUG-006..008)
├── thesis/                      # Academic thesis (LaTeX source and PDF)
├── LICENSE
├── .gitignore
└── README.md
```

## AXI4-Lite Register Map

All registers are 32-bit. Addresses are byte offsets. The slave samples `awaddr`/`araddr` on bits
`[7:2]`.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `key0` | R/W | Hash secret key word 0 (default `0xDEADBEEF`) |
| `0x04` | `key1` | R/W | Hash secret key word 1 (default `0xCAFEBABE`) |
| `0x08` | `key2` | R/W | Hash secret key word 2 (default `0x8BADF00D`) |
| `0x0C` | `key3` | R/W | Hash secret key word 3 (default `0x0DEFACED`) |
| `0x10` | `control` | R/W | Bit0 = firewall enable, Bit1 = parser enable, Bit2 = stats reset (self-clearing). Default `0x00000003`. |
| `0x20` | `rx_pkts` | R | Total received packets |
| `0x24` | `tx_pkts` | R | Total forwarded packets |
| `0x28` | `drops` | R | Total dropped packets (rule-based) |
| `0x2C` | `rx_bytes_lo` | R | RX bytes, low 32 bits |
| `0x30` | `rx_bytes_hi` | R | RX bytes, high 32 bits |
| `0x34` | `tx_bytes_lo` | R | TX bytes, low 32 bits |
| `0x38` | `tx_bytes_hi` | R | TX bytes, high 32 bits |
| `0x3C` | `tcp_pkts` | R | TCP packet count |
| `0x40` | `udp_pkts` | R | UDP packet count |
| `0x44` | `icmp_pkts` | R | ICMP packet count |
| `0x48` | `parse_errors` | R | Parser error count |
| `0x4C` | `magic` | R | Magic/version id `0xFACEB00C` |
| `0x50` | `rule_w0` | W | Rule data word 0 (`tuple[31:0]`) |
| `0x54` | `rule_w1` | W | Rule data word 1 (`tuple[63:32]`) |
| `0x58` | `rule_w2` | W | Rule data word 2 (`tuple[95:64]`) |
| `0x5C` | `rule_w3` | W | Rule data word 3 (`bit127 valid`, `bit126 action`, `tuple[103:96]`) |
| `0x60` | `rule_ctrl` | W | `addr[11:0]`, `bank[17:16]`, `write_en[31]` (pulses `rule_write_en` one cycle) |
| `0x64` | `rx_stalls` | R | (PerfMon) RX interface stalls (tvalid without tready) |
| `0x68` | `tx_stalls` | R | (PerfMon) TX interface stalls (tvalid without tready) |
| `0x6C` | `occupancy` | R | (PerfMon) `[31:16]` peak occupancy, `[15:0]` current occupancy |
| `0x70` | `lat_u10`   | R | (PerfMon) Latency histogram: < 10 cycles |
| `0x74` | `lat_10_20` | R | (PerfMon) Latency histogram: 10 to 20 cycles |
| `0x78` | `lat_o20`   | R | (PerfMon) Latency histogram: > 20 cycles |

### Rule-table entry format (128-bit, per BRAM word)
```
bit[127]   = entry valid
bit[126]   = action (1 = forward, 0 = drop)
bit[125:104] = protocol (8-bit)   // upper bits of the 104-bit tuple
bit[103:0] = {src_ip[31:0], dst_ip[31:0], src_port[15:0], dst_port[15:0]}
```
The 4 banks are indexed by the 4 independent hash seeds. To program a rule, write `rule_w0..3`
then pulse `rule_ctrl` with the target bank and address.

## Quick Start

### Simulation — legacy testbench (Icarus Verilog)
```bash
cd sim
iverilog -o sim.vvp -I ../rtl ../rtl/*.v ../tb/tb_ha_tff_system_top.v
vvp sim.vvp
# open tb_ha_tff_system_top.vcd in GTKWave
```

### Simulation — SystemVerilog DV environment
The `dv/` suite uses classes, covergroups, SVA `bind`, and `$urandom`, which require a
SystemVerilog simulator (e.g. Questa/ModelSim, Xcelium, or Verilator with `--sv`). Icarus
Verilog has only partial SystemVerilog support and is **not** sufficient.
```bash
# Example (Questa/ModelSim)
vlog -sv -work work ../rtl/*.v ../dv/ha_tff_sva.sv ../dv/ha_tff_coverage.sv \
      ../dv/dv_packet_generator.sv ../dv/tb_ha_tff_dv_top.sv
vsim -c work.tb_ha_tff_dv_top -do "run -all"
```
`dv/golden_model.py` is a **standalone** scapy-based oracle that prints expected telemetry for a
PCAP; it is not yet auto-checked against the SV testbench output.

### Synthesis (Vivado)
```bash
cd constraints
vivado -mode batch -source synth.tcl
```
`synth.tcl` reads the current `rtl/` sources, synthesizes `ha_tff_system_top_v005` for the
Artix-7 `xc7a100tfgg484-1` at 156.25 MHz, and writes utilization/timing/power reports to
`reports/`.

## Synthesis Results (Vivado 2026.1, Artix-7 xc7a100tfgg484-1)

The committed `reports/utilization_report.txt` reflects **design `ha_tff_system_top_v005`** with the 
performance monitor fully integrated.

| Resource | Used | Available | Utilization |
|----------|------|-----------|:-----------:|
| Slice LUTs | 811 | 63,400 | 1.28% |
| Slice Registers | 1608 | 126,800 | 1.27% |
| Block RAM (36Kb) | 48 | 135 | 35.56% |
| Block RAM (18Kb) | 0 | 270 | 0.00% |
| DSP Slices | 0 | 240 | 0.00% |
| Bonded IOB | 241 | 285 | 84.56% |

> **Zero DSP slices** — the datapath uses only XOR/shift/comparator logic, making it trivially
> scalable. The 84.56% IOB utilization reflects the wide AXI4-Stream + AXI4-Lite bus pinout properly accommodated in the larger FGG484 package.

## Known Limitations

- **IPv4 + TCP/UDP only.** ARP, IPv6, and ICMP are parsed as `parse_error` and dropped. (ICMP is
  *counted* in `icmp_pkts` only when a valid 5-tuple is produced, which the current parser does
  not do — so live ICMP increments `parse_errors` instead.)
- **Default-deny.** Packets without a matching forward rule are dropped, including all unmatched
  valid flows. Disable the firewall (`control[0]=0`) to forward everything.
- **Static rule table.** Rules are loaded via AXI4-Lite at runtime but the Cuckoo placement is
  expected to be pre-computed offline; the hardware performs lookup only, not insertion/eviction.
- **Empty tables by default.** `sim/bank*.mem` ship all-zero (no valid entries), so out-of-the-box
  every packet is dropped until rules are programmed.

## Open Items

- **SVA `bind` path** in `dv/tb_ha_tff_dv_top.sv` reaches `uut.datapath_inst.parser.*`; verify the
  hierarchical path after any datapath instance-name changes.
- **Golden-model automation**: couple `dv/golden_model.py` to the SV testbench for self-checking
  telemetry comparisons.

## Engineering History (iteration map)

| Iteration | Focus | Key Decision |
|-----------|-------|--------------|
| v001 | Parsing | AXI4-Stream 5-tuple extraction |
| v002 | Parser | Pipelined 64-bit Ethernet frame parser (`ha_tff_parser_v002`) |
| v003 | Hashing | Keyed 4-seed XOR-fold hash (`ha_tff_hash_v002`) |
| v004 | Memory | BRAM Cuckoo-hash banks (`ha_tff_bram_bank`) |
| v005 | Datapath | 4-way parallel matcher + delay-line alignment (`ha_tff_datapath_top_v003`, `ha_tff_matapath_top_v005`→`ha_tff_system_top_v005`) |
| +telemetry | Monitoring | `ha_tff_statistics` engine + AXI-Lite telemetry read-out |
| +perf_mon | Monitoring | `ha_tff_performance_monitor` integration + IOB constraint resolution |

### Bug Reports (still relevant to current code)
| ID | Title | Root Cause | Fix |
|----|-------|-----------|-----|
| BUG-001 | Tuple Valid Timeout | Parser `tuple_valid` not clearing properly | Added timeout/reset-on-`tlast` behaviour |
| BUG-006 | Sticky Parse Error | `parse_error` was not cleared in the `else` block | Added `parse_error <= 0` and short packet handling |
| BUG-007 | Occupancy Tracker Flaw | `active_packets` was gated by latency measurement | Separated tracking logic to independently count concurrent packets |
| BUG-008 | Pipeline Synchronization | Delay line latency was 6 (too short), decision was 1-cycle pulse | Increased latency to 16, added Decision FIFO to robustly stream decisions |

## License

MIT License. See [LICENSE](LICENSE).
