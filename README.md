# HA-TFF: Hardware-Accelerated Telemetry Filter/Forwarder

This is the hardware IP core for filtering drone telemetry packets at wire speed. It sits between an Ethernet MAC and a RISC-V SoC bus, dropping malicious or malformed packets in silicon before they ever generate a CPU interrupt.

I wrote this for my capstone project after realizing that doing this in software (even C11 on an RTOS) introduces unavoidable jitter.

## What it does
1. Receives raw Ethernet frames via AXI-Stream.
2. Cut-through parses the Ethernet, IPv4, and UDP headers.
3. Extracts the 5-tuple and verifies it's MAVLink traffic.
4. Checks the MAVLink System ID against a configurable allow-list.
5. Computes the MAVLink CRC-16 (including the message-specific `CRC_EXTRA` seed) in hardware.
6. Buffers the valid MAVLink payload in a small BRAM FIFO.
7. Exposes the FIFO and statistics counters to the CPU via a Wishbone B4 pipelined slave interface.

## Tech Stack
- **RTL**: SystemVerilog (IEEE 1800-2012)
- **Simulation**: Verilator + C++ testbenches
- **Synthesis target**: Xilinx Artix-7 (Nexys A7 100T) via Vivado 2026.1

## Building and Testing

You need Verilator installed to run the testbenches.

```bash
cd sim
make parser  # unit test the eth/ip/udp parser
make filter  # unit test the mavlink crc + sysid logic
make top     # full integration test with mock Wishbone CPU
```

## Integrating into VeeRwolf

This core is designed to be mapped into the `wb_intercon.v` of the VeeRwolf SoC. See the `docs/register_map.md` for the CSR layout. 

## Shoutouts
- Dr. Smith for convincing me to use Verilator instead of Xilinx XSIM.
- The `rvfpga-soc` curriculum. I wouldn't have understood the Wishbone bus without Lab 3.
- The [Migen](https://m-labs.hk/gateware/migen/) developers, even though I abandoned that attempt. It's a cool idea, I'm just not smart enough to debug generated Verilog.
