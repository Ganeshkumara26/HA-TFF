"""
migen_filter.py - first attempt at hardware packet filter using Migen/Amaranth

july 2026

ok so my supervisor said "you need to write a hardware packet filter in
SystemVerilog" and i was like... i can barely write SystemVerilog. i learned
to READ it during the rvfpga labs but writing production RTL from scratch
is a completely different thing.

found this library called Migen (now called Amaranth) that lets you describe
hardware in Python and it generates Verilog. sounded amazing. "hardware
description in Python!" they said. "it'll be fun!" they said.

spoiler: it was not fun. the generated verilog is unreadable, debugging is
a nightmare because you're debugging two abstraction layers deep, and when
i tried to integrate it with the veerwolf wishbone bus nothing worked because
the generated port names dont match what wb_intercon.v expects.

abandoned this after 2 weeks of fighting with it. going back to writing
SystemVerilog by hand. at least i can read the rvfpga source files for
reference.

LESSON: "write hardware in Python" sounds great until you need to debug
the generated verilog. there's no substitute for understanding the RTL.
"""

from migen import *
from migen.genlib.fsm import FSM, NextState, NextValue


class PacketFilter(Module):
    """
    Ethernet packet filter.
    
    Receives bytes from an AXI-Stream-like interface, parses
    Ethernet + IP + UDP headers, checks if its a MAVLink packet
    from an allowed system ID, and either forwards or drops.
    
    This was supposed to be clean and elegant. It is neither.
    """
    
    def __init__(self, allowed_sysids=None):
        if allowed_sysids is None:
            allowed_sysids = [1, 2, 3]  # default fleet IDs
        
        # --- AXI-Stream input ---
        self.tdata_in = Signal(8)
        self.tvalid_in = Signal()
        self.tready_in = Signal()  # we drive this
        self.tlast_in = Signal()
        
        # --- AXI-Stream output (filtered) ---
        self.tdata_out = Signal(8)
        self.tvalid_out = Signal()
        self.tready_out = Signal()  # downstream drives this
        self.tlast_out = Signal()
        
        # --- status ---
        self.packets_seen = Signal(32)
        self.packets_passed = Signal(32)
        self.packets_dropped = Signal(32)
        
        # --- internal ---
        byte_count = Signal(16)
        ethertype = Signal(16)
        ip_protocol = Signal(8)
        dst_port = Signal(16)
        mav_sysid = Signal(8)
        
        # packet buffer - this is where it gets ugly
        # migen doesnt have a nice way to do shift registers
        # for header accumulation, so i'm using individual signals
        hdr_byte0 = Signal(8)
        hdr_byte1 = Signal(8)
        
        # FSM
        self.submodules.fsm = fsm = FSM(reset_state="IDLE")
        
        # --- IDLE ---
        fsm.act("IDLE",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                NextValue(byte_count, 0),
                NextValue(self.packets_seen, self.packets_seen + 1),
                NextState("ETH_HDR"),
            )
        )
        
        # --- ETH_HDR (14 bytes: 6 dst + 6 src + 2 ethertype) ---
        # i need bytes 12 and 13 for the ethertype
        # this is where migen gets painful. in SV i'd just index
        # into a shift register. here i'm doing this awful thing:
        fsm.act("ETH_HDR",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                NextValue(byte_count, byte_count + 1),
                If(byte_count == 12,
                    NextValue(hdr_byte0, self.tdata_in),  # ethertype MSB
                ),
                If(byte_count == 13,
                    NextValue(ethertype, Cat(self.tdata_in, hdr_byte0)),
                    # check if IPv4 (0x0800)
                    # BUG: this check happens one cycle late because of
                    # NextValue. i need to restructure this but i'm tired
                    NextState("CHECK_ETHERTYPE"),
                ),
            ),
            If(self.tlast_in,
                # runt frame, abort
                NextState("IDLE"),
            ),
        )
        
        fsm.act("CHECK_ETHERTYPE",
            If(ethertype == 0x0800,
                NextValue(byte_count, 0),
                NextState("IP_HDR"),
            ).Else(
                # not IPv4, drop
                NextValue(self.packets_dropped, self.packets_dropped + 1),
                NextState("DROP"),
            )
        )
        
        # --- IP_HDR (20 bytes minimum, no options support) ---
        # need byte 9 for protocol
        fsm.act("IP_HDR",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                NextValue(byte_count, byte_count + 1),
                If(byte_count == 9,
                    NextValue(ip_protocol, self.tdata_in),
                ),
                If(byte_count == 19,  # end of basic IP header
                    NextState("CHECK_PROTOCOL"),
                ),
            ),
            If(self.tlast_in,
                NextState("IDLE"),
            ),
        )
        
        fsm.act("CHECK_PROTOCOL",
            If(ip_protocol == 17,  # UDP
                NextValue(byte_count, 0),
                NextState("UDP_HDR"),
            ).Else(
                NextValue(self.packets_dropped, self.packets_dropped + 1),
                NextState("DROP"),
            )
        )
        
        # --- UDP_HDR (8 bytes) ---
        # need bytes 2-3 for destination port
        fsm.act("UDP_HDR",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                NextValue(byte_count, byte_count + 1),
                If(byte_count == 2,
                    NextValue(hdr_byte0, self.tdata_in),  # dst port MSB
                ),
                If(byte_count == 3,
                    NextValue(dst_port, Cat(self.tdata_in, hdr_byte0)),
                ),
                If(byte_count == 7,
                    NextState("CHECK_PORT"),
                ),
            ),
            If(self.tlast_in,
                NextState("IDLE"),
            ),
        )
        
        fsm.act("CHECK_PORT",
            If(dst_port == 14550,  # standard MAVLink port
                NextValue(byte_count, 0),
                NextState("MAV_CHECK"),
            ).Else(
                NextValue(self.packets_dropped, self.packets_dropped + 1),
                NextState("DROP"),
            )
        )
        
        # --- MAV_CHECK (look for 0xFD magic byte) ---
        fsm.act("MAV_CHECK",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                If(self.tdata_in == 0xFD,
                    NextValue(byte_count, 0),
                    NextState("MAV_HDR"),
                ).Else(
                    # not MAVLink, drop
                    NextValue(self.packets_dropped, self.packets_dropped + 1),
                    NextState("DROP"),
                )
            ),
            If(self.tlast_in,
                NextState("IDLE"),
            ),
        )
        
        # --- MAV_HDR (bytes 1-9 of mavlink, need byte 5 for sysid) ---
        # this is getting really ugly. each byte needs its own condition.
        # in SV i would use a case statement and a counter. here i'm
        # doing nested Ifs and it looks terrible.
        fsm.act("MAV_HDR",
            self.tready_in.eq(1),
            If(self.tvalid_in,
                NextValue(byte_count, byte_count + 1),
                If(byte_count == 4,  # sysid is byte 5 (0-indexed: 4)
                    NextValue(mav_sysid, self.tdata_in),
                ),
                If(byte_count == 8,  # end of mavlink header
                    NextState("CHECK_SYSID"),
                ),
            ),
            If(self.tlast_in,
                NextState("IDLE"),
            ),
        )
        
        # --- CHECK_SYSID ---
        # TODO: this should check against a configurable allow list
        # but migen makes parameterized comparisons painful
        # hardcoding for now
        fsm.act("CHECK_SYSID",
            If((mav_sysid == allowed_sysids[0]) | 
               (mav_sysid == allowed_sysids[1]) |
               (mav_sysid == allowed_sysids[2]),
                NextValue(self.packets_passed, self.packets_passed + 1),
                NextState("FORWARD"),
            ).Else(
                NextValue(self.packets_dropped, self.packets_dropped + 1),
                NextState("DROP"),
            )
        )
        
        # --- FORWARD (pass remaining bytes to output) ---
        # BUG: we've already consumed all the header bytes and they're
        # gone. we cant forward the complete packet because we ate the
        # headers during parsing. this is the fundamental flaw in this
        # design - i need either a store-and-forward buffer (expensive)
        # or a cut-through approach where i forward AND parse simultaneously.
        # 
        # this is where i gave up on the migen approach. the cut-through
        # design is actually doable in SV with a proper shift register
        # and combinational forwarding, but in migen the code becomes
        # so convoluted that i cant reason about it anymore.
        fsm.act("FORWARD",
            self.tready_in.eq(self.tready_out),
            self.tvalid_out.eq(self.tvalid_in),
            self.tdata_out.eq(self.tdata_in),
            self.tlast_out.eq(self.tlast_in),
            If(self.tlast_in & self.tvalid_in,
                NextState("IDLE"),
            ),
        )
        
        # --- DROP (consume and discard until tlast) ---
        fsm.act("DROP",
            self.tready_in.eq(1),  # keep accepting to drain
            If(self.tlast_in & self.tvalid_in,
                NextState("IDLE"),
            ),
        )


# --- quick sim to see if it even elaborates ---
if __name__ == "__main__":
    dut = PacketFilter(allowed_sysids=[1, 2, 3])
    
    # generate verilog
    # this is the part that made me give up. look at the generated
    # verilog. LOOK AT IT. its like 500 lines of incomprehensible
    # auto-generated wire names like "migen_fsm_case_0_sink_next"
    from migen.fhdl.verilog import convert
    v = convert(dut, ios={
        dut.tdata_in, dut.tvalid_in, dut.tready_in, dut.tlast_in,
        dut.tdata_out, dut.tvalid_out, dut.tready_out, dut.tlast_out,
        dut.packets_seen, dut.packets_passed, dut.packets_dropped,
    })
    
    with open("migen_filter_generated.v", "w") as f:
        f.write(str(v))
    
    print("generated verilog written to migen_filter_generated.v")
    print("good luck reading it. i couldnt.")
    print("")
    print("VERDICT: abandoning this approach. writing SV by hand.")
    print("at least i know what a hardware FSM looks like now.")
