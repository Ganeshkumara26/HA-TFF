/*
 * tb_basic.sv - first testbench attempt (non-randomized)
 *
 * aug 4, 2026
 *
 * wrote this to test parser_v1_mealy.sv. its just a bunch of
 * hardcoded stimulus - one valid IPv4/UDP/MAVLink packet, one
 * non-IPv4 packet, one wrong-port packet.
 *
 * THE PROBLEM: this testbench only tests the happy path. it doesnt
 * test:
 *   - truncated packets (tlast before header is complete)
 *   - back-to-back packets with no gap
 *   - packets with IP options (header > 20 bytes)
 *   - maximum-length frames (1518 bytes)
 *   - minimum-length frames (64 bytes)
 *   - backpressure from downstream (tready deassertion)
 *
 * basically all the edge cases that actually matter. my supervisor
 * called this a "sunshine testbench" and told me to learn about
 * constrained-random verification.
 *
 * replaced by the verilator C++ testbenches in tb/ which use
 * random packet generation and coverage tracking.
 *
 * STATUS: ABANDONED (kept as a reference for the packet format)
 */

`timescale 1ns / 1ps

module tb_basic;

    logic       clk = 0;
    logic       rst_n = 0;
    logic [7:0] s_tdata;
    logic       s_tvalid;
    logic       s_tready;
    logic       s_tlast;
    logic [7:0] m_tdata;
    logic       m_tvalid;
    logic       m_tready;
    logic       m_tlast;
    logic       pkt_valid;
    logic       pkt_dropped;

    // 100MHz clock
    always #5 clk = ~clk;
    
    // DUT
    parser_v1_mealy dut (.*);
    
    // downstream always ready (no backpressure testing. bad.)
    assign m_tready = 1'b1;
    
    // --- stimulus ---
    task send_byte(input logic [7:0] data, input logic last);
        @(posedge clk);
        s_tdata  <= data;
        s_tvalid <= 1'b1;
        s_tlast  <= last;
        @(posedge clk);
        while (!s_tready) @(posedge clk);
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
    endtask

    // send a complete ethernet frame byte by byte
    task send_frame(input logic [7:0] frame[], input int len);
        for (int i = 0; i < len; i++) begin
            send_byte(frame[i], (i == len - 1));
        end
        // inter-frame gap (2 cycles, way too small for real ethernet)
        @(posedge clk);
        @(posedge clk);
    endtask
    
    initial begin
        // reset
        rst_n = 0;
        s_tdata = 0;
        s_tvalid = 0;
        s_tlast = 0;
        #100;
        rst_n = 1;
        #20;
        
        // --- TEST 1: valid IPv4/UDP/MAVLink packet ---
        $display("--- TEST 1: valid packet ---");
        begin
            automatic logic [7:0] frame[64];
            int idx = 0;
            
            // ethernet header (14 bytes)
            // dst MAC: ff:ff:ff:ff:ff:ff (broadcast)
            frame[idx++] = 8'hFF; frame[idx++] = 8'hFF; frame[idx++] = 8'hFF;
            frame[idx++] = 8'hFF; frame[idx++] = 8'hFF; frame[idx++] = 8'hFF;
            // src MAC: 00:11:22:33:44:55
            frame[idx++] = 8'h00; frame[idx++] = 8'h11; frame[idx++] = 8'h22;
            frame[idx++] = 8'h33; frame[idx++] = 8'h44; frame[idx++] = 8'h55;
            // ethertype: 0x0800 (IPv4)
            frame[idx++] = 8'h08; frame[idx++] = 8'h00;
            
            // IP header (20 bytes, no options)
            frame[idx++] = 8'h45; // version=4, IHL=5
            frame[idx++] = 8'h00; // DSCP/ECN
            frame[idx++] = 8'h00; frame[idx++] = 8'h2E; // total length = 46
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; // ID
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; // flags/fragment
            frame[idx++] = 8'h40; // TTL = 64
            frame[idx++] = 8'h11; // protocol = 17 (UDP)
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; // checksum (dont care)
            frame[idx++] = 8'hC0; frame[idx++] = 8'hA8; // src IP: 192.168.1.100
            frame[idx++] = 8'h01; frame[idx++] = 8'h64;
            frame[idx++] = 8'hC0; frame[idx++] = 8'hA8; // dst IP: 192.168.1.1
            frame[idx++] = 8'h01; frame[idx++] = 8'h01;
            
            // UDP header (8 bytes)
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; // src port (dont care)
            frame[idx++] = 8'h38; frame[idx++] = 8'hE6; // dst port = 14550 (MAVLink)
            frame[idx++] = 8'h00; frame[idx++] = 8'h1A; // UDP length
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; // UDP checksum
            
            // MAVLink v2 header
            frame[idx++] = 8'hFD; // magic byte
            frame[idx++] = 8'h09; // payload length = 9 (heartbeat)
            frame[idx++] = 8'h00; // incompat flags
            frame[idx++] = 8'h00; // compat flags
            frame[idx++] = 8'h00; // sequence
            frame[idx++] = 8'h01; // sysid = 1 (our drone)
            frame[idx++] = 8'h01; // compid
            frame[idx++] = 8'h00; frame[idx++] = 8'h00; frame[idx++] = 8'h00; // msgid = 0 (heartbeat)
            
            // heartbeat payload (9 bytes)
            frame[idx++] = 8'h00; frame[idx++] = 8'h00;
            frame[idx++] = 8'h00; frame[idx++] = 8'h00;
            frame[idx++] = 8'h02; frame[idx++] = 8'h03;
            frame[idx++] = 8'h8D; frame[idx++] = 8'h03;
            frame[idx++] = 8'h03;
            
            // CRC (fake, we dont check it in this version)
            frame[idx++] = 8'hAA; frame[idx++] = 8'hBB;
            
            send_frame(frame, idx);
            
            if (pkt_valid)
                $display("  PASS: packet accepted");
            else
                $display("  FAIL: packet was not accepted");
        end
        
        // --- TEST 2: non-IPv4 packet (ARP, ethertype 0x0806) ---
        $display("--- TEST 2: non-IPv4 (should drop) ---");
        begin
            automatic logic [7:0] frame[20];
            // ethernet header with ARP ethertype
            frame[0] = 8'hFF; frame[1] = 8'hFF; frame[2] = 8'hFF;
            frame[3] = 8'hFF; frame[4] = 8'hFF; frame[5] = 8'hFF;
            frame[6] = 8'h00; frame[7] = 8'h11; frame[8] = 8'h22;
            frame[9] = 8'h33; frame[10] = 8'h44; frame[11] = 8'h55;
            frame[12] = 8'h08; frame[13] = 8'h06;  // ARP
            // some payload
            frame[14] = 8'h00; frame[15] = 8'h01;
            frame[16] = 8'h08; frame[17] = 8'h00;
            frame[18] = 8'h06; frame[19] = 8'h04;
            
            send_frame(frame, 20);
            
            if (pkt_dropped)
                $display("  PASS: ARP packet dropped");
            else
                $display("  FAIL: ARP packet was not dropped");
        end
        
        // --- TEST 3: TODO: add more tests ---
        // (i never did. hence "sunshine testbench".)
        
        #200;
        $display("--- tb_basic done ---");
        $display("NOTE: this only tests happy path. need constrained-random.");
        $finish;
    end
    
    // waveform dump
    initial begin
        $dumpfile("tb_basic.vcd");
        $dumpvars(0, tb_basic);
    end

endmodule
