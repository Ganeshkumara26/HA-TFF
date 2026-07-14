`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - Constrained Random Packet Generator
// Injects valid packets, malformed packets, and randomized backpressure.

class EthernetPacket;
    rand bit [47:0] dest_mac;
    rand bit [47:0] src_mac;
    rand bit [15:0] ethertype;
    
    rand bit [31:0] src_ip;
    rand bit [31:0] dst_ip;
    rand bit [7:0]  protocol;
    
    rand bit [15:0] src_port;
    rand bit [15:0] dst_port;
    
    rand int payload_len; // in bytes
    
    // Error injection flags
    rand bit err_truncated;
    rand bit err_crc;
    rand bit err_invalid_header;
    rand bit err_random_bytes;
    
    // Constraints for realistic traffic
    constraint c_ethertype {
        if (!err_invalid_header) {
            ethertype dist { 16'h0800 := 90, 16'h86DD := 5, 16'h0806 := 5 }; // Mostly IPv4
        } else {
            ethertype inside {[16'h0000 : 16'hFFFF]}; // Complete garbage
        }
    }
    
    constraint c_protocol {
        protocol dist { 8'h06 := 70, 8'h11 := 20, 8'h01 := 10 }; // TCP, UDP, ICMP
    }
    
    constraint c_payload {
        payload_len inside {[46:1500]}; // Standard Ethernet frame payload sizes
    }
    
    constraint c_errors {
        err_truncated      dist { 0 := 95, 1 := 5 };
        err_crc            dist { 0 := 95, 1 := 5 };
        err_invalid_header dist { 0 := 98, 1 := 2 };
        err_random_bytes   dist { 0 := 98, 1 := 2 };
    }
    
    // Post-randomize hook to handle error injection
    function void post_randomize();
        if (err_truncated) begin
            // Inject an error by forcing payload length to be illegally small (truncated header)
            payload_len = $urandom_range(0, 10);
        end
    endfunction
    
endclass

class PacketGenerator;
    // Drives the packet onto the AXI4-Stream interface via a virtual interface or tasks
    // For now, this class generates the flat 64-bit word arrays to feed to the TB.
    
    function void generate_packet(EthernetPacket pkt, output logic [63:0] data_q[$], output logic [7:0] keep_q[$]);
        logic [63:0] current_word;
        logic [7:0]  current_keep;
        
        data_q.delete();
        keep_q.delete();
        
        // Word 0 (Bytes 0-7): Dest MAC [47:0], Src MAC [47:32]
        current_word = {pkt.src_mac[47:32], pkt.dest_mac};
        data_q.push_back(current_word);
        keep_q.push_back(8'hFF);
        
        // Word 1 (Bytes 8-15): Src MAC [31:0], EtherType [15:0], IP Ver/IHL/TOS [15:0]
        current_word = {16'h4500, pkt.ethertype, pkt.src_mac[31:0]};
        data_q.push_back(current_word);
        keep_q.push_back(8'hFF);
        
        // Word 2 (Bytes 16-23): IP Len [15:0], ID [15:0], Flags/Frag [15:0], TTL [7:0], Protocol [7:0]
        current_word = {pkt.protocol, 8'h40, 16'h0000, 16'h1234, 16'h0028};
        data_q.push_back(current_word);
        keep_q.push_back(8'hFF);
        
        // Word 3 (Bytes 24-31): Checksum [15:0], Src IP [31:0], Dst IP [15:0]
        current_word = {pkt.dst_ip[31:16], pkt.src_ip, 16'hABCD};
        data_q.push_back(current_word);
        keep_q.push_back(8'hFF);
        
        // Word 4 (Bytes 32-39): Dst IP [15:0], Src Port [15:0], Dst Port [15:0], UDP/TCP Len [15:0]
        current_word = {16'h0010, pkt.dst_port, pkt.src_port, pkt.dst_ip[15:0]};
        
        if (pkt.err_random_bytes) begin
            current_word = {$urandom, $urandom}; // Corrupt the transport header
        end
        
        if (pkt.err_truncated) begin
            // Truncate here
            data_q.push_back(current_word);
            keep_q.push_back(8'h0F); // Only half the word is valid
        end else begin
            data_q.push_back(current_word);
            keep_q.push_back(8'hFF);
            // Append payload bytes
            for (int i = 0; i < pkt.payload_len/8; i++) begin
                data_q.push_back({$urandom, $urandom});
                keep_q.push_back(8'hFF);
            end
            // Simulated CRC word at the end
            if (pkt.err_crc) begin
                data_q.push_back({$urandom, $urandom}); // Bad CRC
            end else begin
                data_q.push_back(64'hDEADBEEFCAFEBABE); // Simulated Good CRC
            end
            keep_q.push_back(8'h0F);
        end
    endfunction
endclass
