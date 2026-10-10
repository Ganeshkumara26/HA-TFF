# HA-TFF Wishbone Register Map

Base Address: Defined in `wb_intercon.v` (usually 0x80002000 for peripheral space)

| Offset | Register       | Access | Description |
|--------|----------------|--------|-------------|
| 0x00   | CTRL           | R/W    | Control register (see below) |
| 0x04   | STATUS         | R      | Status register (see below) |
| 0x08   | PKT_TOTAL      | R      | Total ethernet packets seen |
| 0x0C   | PKT_PASS       | R      | Packets passed filter & CRC |
| 0x10   | PKT_DROP       | R      | Packets dropped (wrong IP/UDP/SysID) |
| 0x14   | CRC_ERR        | R      | Packets dropped due to bad CRC |
| 0x18   | FIFO_DATA      | R      | Read one byte from FIFO (auto-pops) |
| 0x1C   | FIFO_LEVEL     | R      | Current number of bytes in FIFO |
| 0x20   | SYSID_0        | R/W    | Allowed System ID 0 (0 = disable) |
| 0x24   | SYSID_1        | R/W    | Allowed System ID 1 |
| ...    | ...            | ...    | ... |
| 0x3C   | SYSID_7        | R/W    | Allowed System ID 7 |

## CTRL Register (0x00)
- `Bit 0` - ENABLE: 1 to start filtering, 0 to bypass/drop all
- `Bit 1` - RST_STATS: Write 1 to clear counters (auto-clears to 0)
- `Bit 2` - PROMISC: 1 to pass ALL MAVLink sysids, 0 to enforce sysid list
- `Bit 3` - DROP_NON_IP: 1 to drop ARP/etc, 0 to pass non-IPv4 to CPU

## STATUS Register (0x04)
- `Bit 0` - FIFO_EMPTY: 1 if no telemetry available
- `Bit 1` - FIFO_FULL: 1 if FIFO is full (packets are being lost)
- `Bit 2` - FSM_ACTIVE: 1 if parser is currently in the middle of a packet
- `Bits [7:4]` - FSM_STATE: Current parser state (for debug)
