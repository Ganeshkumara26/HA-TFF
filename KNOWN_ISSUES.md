# known issues (wontfix)

- IPv4 options are not supported. If a packet has IHL > 5, the state machine will probably drop it, or worse, parse the options as the UDP header. Since our drone fleet uses standard no-option IPv4, I am not fixing this. If you try to route this over a weird VPN that adds IP options, it will break.
- The Wishbone ACK path has a combinational path from STB. This is fine at 100MHz on Artix-7, but if you try to synthesize this for a 300MHz ASIC, it will fail setup time.
- The `stat_runt` counter increments if the MAC asserts `tlast` early, but it doesn't catch runts that are technically complete at the ethernet layer but have a truncated UDP payload.
- MAVLink v1 is entirely ignored. We only check for the `0xFD` magic byte. If your drone uses v1 (`0xFE`), update your firmware. I'm not writing a dual-version parser in hardware.
- The CRC lookup table (`crc_extra()`) is hardcoded for the 10 message IDs we actually use. If you send a `PARAM_REQUEST_LIST` (msgid 21), the CRC will fail because I didn't add the seed for it. Update `ha_tff_pkg.sv` if you need more message types.
