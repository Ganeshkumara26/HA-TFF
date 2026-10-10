/*
 * eth_parser.sv - Ethernet/IP/UDP header parser FSM
 *
 * this is the main packet parser. receives bytes from an AXI-Stream
 * interface (from the ethernet MAC), parses ethernet + IP + UDP headers,
 * and outputs the extracted 5-tuple plus a pointer to the UDP payload
 * (which should be MAVLink data).
 *
 * this is the hardware equivalent of the first part of my edp-core
 * mavlink_parser.c FSM. the big difference is that in C, i parsed
 * raw serial bytes (just MAVLink). in hardware, i need to parse the
 * full ethernet/IP/UDP stack first before i even GET to the MAVLink.
 *
 * design choices:
 *   - Moore-style registered outputs (learned from parser_v1_mealy.sv
 *     disaster). outputs depend only on current state, not inputs.
 *     costs one cycle of latency but eliminates glitches.
 *   - byte-by-byte processing (no wide bus). the RMII MAC on the
 *     nexys a7 operates at 100Mbps / 8 = 12.5 million bytes/sec.
 *     at 100MHz clock, we have 8 clock cycles per byte. plenty.
 *   - cut-through: we start forwarding as soon as we know the packet
 *     is valid. we dont buffer the entire frame first. this keeps
 *     latency low (important for the URLLC telemetry path).
 *
 * sept 5, 2026
 */

import ha_tff_pkg::*;

module eth_parser (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- AXI-Stream input (from MAC) ---
    input  logic [7:0]  s_tdata,
    input  logic        s_tvalid,
    output logic        s_tready,
    input  logic        s_tlast,
    
    // --- parsed output ---
    output five_tuple_t tuple,
    output logic        tuple_valid,    // pulses when 5-tuple is complete
    
    // --- to MAVLink filter ---
    output logic [7:0]  mav_data,       // byte-by-byte MAVLink data
    output logic        mav_valid,      // mav_data is valid this cycle
    output logic        mav_last,       // last byte of MAVLink payload
    output logic        mav_sof,        // start of MAVLink frame (0xFD seen)
    
    // --- control ---
    input  logic        enable,
    input  logic        drop_non_ip,
    
    // --- statistics ---
    output logic        stat_pkt_seen,   // pulse: any packet started
    output logic        stat_non_ipv4,   // pulse: dropped non-IPv4
    output logic        stat_non_udp,    // pulse: dropped non-UDP
    output logic        stat_wrong_port, // pulse: dropped wrong port
    output logic        stat_runt        // pulse: truncated frame
);

    // --- internal state ---
    parser_state_t state, state_next;
    
    logic [15:0] byte_cnt;
    logic [15:0] byte_cnt_next;
    
    // header field accumulators
    // these get filled byte-by-byte as the header arrives
    logic [15:0] ethertype_r;
    logic [7:0]  ip_ihl_r;       // IP header length (in 32-bit words)
    logic [15:0] ip_total_len_r;
    logic [7:0]  ip_proto_r;
    logic [31:0] ip_src_r;
    logic [31:0] ip_dst_r;
    logic [15:0] udp_src_port_r;
    logic [15:0] udp_dst_port_r;
    logic [15:0] udp_len_r;
    
    // IP header length in bytes (IHL field * 4)
    // IHL is the lower 4 bits of the first IP byte
    logic [7:0] ip_hdr_bytes;
    assign ip_hdr_bytes = {ip_ihl_r[3:0], 2'b00};  // * 4
    
    // are we processing a valid byte this cycle?
    logic byte_valid;
    assign byte_valid = s_tvalid & s_tready;
    
    
    // =========================================================
    //  State Register
    // =========================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= FSM_IDLE;
            byte_cnt <= '0;
        end else begin
            state    <= state_next;
            byte_cnt <= byte_cnt_next;
        end
    end
    
    
    // =========================================================
    //  Next State Logic
    // =========================================================
    
    always_comb begin
        state_next    = state;
        byte_cnt_next = byte_cnt;
        
        case (state)
            // ---- IDLE: waiting for packet ----
            FSM_IDLE: begin
                if (s_tvalid && enable) begin
                    state_next    = FSM_ETH_HDR;
                    byte_cnt_next = '0;
                end
            end
            
            // ---- ETH_HDR: parsing 14-byte ethernet header ----
            FSM_ETH_HDR: begin
                if (s_tlast && byte_valid) begin
                    // frame ended before we finished the header. runt.
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    byte_cnt_next = byte_cnt + 1;
                    
                    // on byte 13, we have the full ethertype
                    // but we check it on byte 13 using the INCOMING byte
                    // (not the registered one) to avoid the pipeline hazard
                    // from parser_v1_mealy.sv
                    if (byte_cnt == 16'd13) begin
                        // ethertype_r[15:8] was captured on byte 12
                        // s_tdata is byte 13 (ethertype low byte)
                        if ({ethertype_r[15:8], s_tdata} == ETHERTYPE_IPV4) begin
                            state_next    = FSM_IP_HDR;
                            byte_cnt_next = '0;
                        end else begin
                            state_next = drop_non_ip ? FSM_DROP : FSM_IDLE;
                        end
                    end
                end
            end
            
            // ---- IP_HDR: parsing IP header (variable length!) ----
            // the IP header can be 20-60 bytes depending on options.
            // IHL field (lower 4 bits of first byte) tells us the length.
            // we extract protocol (byte 9) and addresses (bytes 12-19).
            FSM_IP_HDR: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    byte_cnt_next = byte_cnt + 1;
                    
                    // done when we've consumed all IP header bytes
                    // using ip_hdr_bytes which is set from byte 0's IHL field
                    if (byte_cnt == {8'b0, ip_hdr_bytes} - 1 && byte_cnt >= 16'd19) begin
                        // check if UDP
                        if (ip_proto_r == IPPROTO_UDP) begin
                            state_next    = FSM_UDP_HDR;
                            byte_cnt_next = '0;
                        end else begin
                            state_next = FSM_DROP;
                        end
                    end
                end
            end
            
            // ---- UDP_HDR: parsing 8-byte UDP header ----
            FSM_UDP_HDR: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    byte_cnt_next = byte_cnt + 1;
                    
                    if (byte_cnt == 16'd7) begin
                        // check destination port using incoming byte for
                        // port low byte and registered value for high byte
                        // (avoid pipeline hazard)
                        logic [15:0] check_port;
                        check_port = udp_dst_port_r;  // already has both bytes by now
                        
                        if (check_port == MAV_PORT || check_port == MAV_PORT_ALT) begin
                            state_next    = FSM_MAV_SYNC;
                            byte_cnt_next = '0;
                        end else begin
                            state_next = FSM_DROP;
                        end
                    end
                end
            end
            
            // ---- MAV_SYNC: look for 0xFD magic byte ----
            FSM_MAV_SYNC: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    if (s_tdata == MAV_STX_V2) begin
                        state_next    = FSM_MAV_HDR;
                        byte_cnt_next = '0;
                    end else begin
                        // not MAVLink, drop the rest
                        state_next = FSM_DROP;
                    end
                end
            end
            
            // ---- MAV_HDR: parse MAVLink v2 header (9 bytes after magic) ----
            // byte 0 = payload length
            // byte 4 = sysid  
            // byte 6-8 = msgid (24-bit)
            FSM_MAV_HDR: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    byte_cnt_next = byte_cnt + 1;
                    
                    if (byte_cnt == 16'd8) begin
                        // header complete, move to payload
                        state_next    = FSM_MAV_PAYLOAD;
                        byte_cnt_next = '0;
                    end
                end
            end
            
            // ---- MAV_PAYLOAD: forward payload bytes ----
            // we know the payload length from byte 0 of MAV_HDR
            FSM_MAV_PAYLOAD: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end else if (byte_valid) begin
                    byte_cnt_next = byte_cnt + 1;
                    
                    // payload_len_r was captured during MAV_HDR
                    // when byte_cnt reaches payload_len_r - 1, payload is done
                    // then we expect 2 CRC bytes
                    // (this is handled by the mav_filter module)
                end
            end
            
            // ---- FORWARD: valid packet, forwarding remaining bytes ----
            FSM_FORWARD: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end
            end
            
            // ---- DROP: consume and discard until end of frame ----
            FSM_DROP: begin
                if (s_tlast && byte_valid) begin
                    state_next = FSM_IDLE;
                end
            end
            
            default: state_next = FSM_IDLE;
        endcase
    end
    
    
    // =========================================================
    //  Header Field Capture
    // =========================================================
    
    // MAVLink header fields
    logic [7:0]  mav_payload_len_r;
    logic [7:0]  mav_sysid_r;
    logic [7:0]  mav_compid_r;
    logic [23:0] mav_msgid_r;
    logic [7:0]  mav_seq_r;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ethertype_r    <= '0;
            ip_ihl_r       <= 8'h45;  // default: no options
            ip_total_len_r <= '0;
            ip_proto_r     <= '0;
            ip_src_r       <= '0;
            ip_dst_r       <= '0;
            udp_src_port_r <= '0;
            udp_dst_port_r <= '0;
            udp_len_r      <= '0;
            mav_payload_len_r <= '0;
            mav_sysid_r    <= '0;
            mav_compid_r   <= '0;
            mav_msgid_r    <= '0;
            mav_seq_r      <= '0;
        end else if (byte_valid) begin
            case (state)
                FSM_ETH_HDR: begin
                    case (byte_cnt)
                        16'd12: ethertype_r[15:8] <= s_tdata;
                        16'd13: ethertype_r[7:0]  <= s_tdata;
                        default: ;
                    endcase
                end
                
                FSM_IP_HDR: begin
                    case (byte_cnt)
                        16'd0:  ip_ihl_r <= s_tdata;  // version + IHL
                        16'd2:  ip_total_len_r[15:8] <= s_tdata;
                        16'd3:  ip_total_len_r[7:0]  <= s_tdata;
                        16'd9:  ip_proto_r <= s_tdata;
                        16'd12: ip_src_r[31:24] <= s_tdata;
                        16'd13: ip_src_r[23:16] <= s_tdata;
                        16'd14: ip_src_r[15:8]  <= s_tdata;
                        16'd15: ip_src_r[7:0]   <= s_tdata;
                        16'd16: ip_dst_r[31:24] <= s_tdata;
                        16'd17: ip_dst_r[23:16] <= s_tdata;
                        16'd18: ip_dst_r[15:8]  <= s_tdata;
                        16'd19: ip_dst_r[7:0]   <= s_tdata;
                        default: ;
                    endcase
                end
                
                FSM_UDP_HDR: begin
                    case (byte_cnt)
                        16'd0: udp_src_port_r[15:8] <= s_tdata;
                        16'd1: udp_src_port_r[7:0]  <= s_tdata;
                        16'd2: udp_dst_port_r[15:8] <= s_tdata;
                        16'd3: udp_dst_port_r[7:0]  <= s_tdata;
                        16'd4: udp_len_r[15:8]      <= s_tdata;
                        16'd5: udp_len_r[7:0]       <= s_tdata;
                        default: ;
                    endcase
                end
                
                FSM_MAV_HDR: begin
                    case (byte_cnt)
                        16'd0: mav_payload_len_r <= s_tdata;
                        // byte 1 = incompat flags (ignore)
                        // byte 2 = compat flags (ignore)
                        16'd3: mav_seq_r    <= s_tdata;
                        16'd4: mav_sysid_r  <= s_tdata;
                        16'd5: mav_compid_r <= s_tdata;
                        16'd6: mav_msgid_r[7:0]   <= s_tdata;
                        16'd7: mav_msgid_r[15:8]  <= s_tdata;
                        16'd8: mav_msgid_r[23:16] <= s_tdata;
                        default: ;
                    endcase
                end
                
                default: ;
            endcase
        end
    end
    
    
    // =========================================================
    //  Output Generation (Moore - registered)
    // =========================================================
    
    // 5-tuple output
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tuple       <= '0;
            tuple_valid <= 1'b0;
        end else begin
            tuple_valid <= 1'b0;  // default: deassert
            
            // pulse tuple_valid when we transition to MAV_SYNC
            // (meaning IP+UDP headers are fully parsed)
            if (state == FSM_UDP_HDR && state_next == FSM_MAV_SYNC) begin
                tuple.src_ip   <= ip_src_r;
                tuple.dst_ip   <= ip_dst_r;
                tuple.src_port <= udp_src_port_r;
                tuple.dst_port <= udp_dst_port_r;
                tuple.protocol <= ip_proto_r;
                tuple_valid    <= 1'b1;
            end
        end
    end
    
    // MAVLink data output (to mav_filter)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mav_data  <= '0;
            mav_valid <= 1'b0;
            mav_last  <= 1'b0;
            mav_sof   <= 1'b0;
        end else begin
            mav_valid <= 1'b0;
            mav_last  <= 1'b0;
            mav_sof   <= 1'b0;
            
            if (byte_valid) begin
                case (state)
                    FSM_MAV_SYNC: begin
                        if (s_tdata == MAV_STX_V2) begin
                            mav_data  <= s_tdata;
                            mav_valid <= 1'b1;
                            mav_sof   <= 1'b1;
                        end
                    end
                    
                    FSM_MAV_HDR, FSM_MAV_PAYLOAD: begin
                        mav_data  <= s_tdata;
                        mav_valid <= 1'b1;
                        
                        if (s_tlast) begin
                            mav_last <= 1'b1;
                        end
                    end
                    
                    default: ;
                endcase
            end
        end
    end
    
    // backpressure / tready
    // always ready except in IDLE when disabled
    always_comb begin
        s_tready = enable || (state != FSM_IDLE);
    end
    
    // statistics pulses
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_pkt_seen  <= 1'b0;
            stat_non_ipv4  <= 1'b0;
            stat_non_udp   <= 1'b0;
            stat_wrong_port <= 1'b0;
            stat_runt      <= 1'b0;
        end else begin
            stat_pkt_seen   <= 1'b0;
            stat_non_ipv4   <= 1'b0;
            stat_non_udp    <= 1'b0;
            stat_wrong_port <= 1'b0;
            stat_runt       <= 1'b0;
            
            // packet seen: transition IDLE -> ETH_HDR
            if (state == FSM_IDLE && state_next == FSM_ETH_HDR)
                stat_pkt_seen <= 1'b1;
            
            // non-IPv4: ETH_HDR -> DROP (or IDLE if drop_non_ip is off)
            if (state == FSM_ETH_HDR && state_next == FSM_DROP)
                stat_non_ipv4 <= 1'b1;
            
            // non-UDP: IP_HDR -> DROP
            if (state == FSM_IP_HDR && state_next == FSM_DROP)
                stat_non_udp <= 1'b1;
            
            // wrong port: UDP_HDR -> DROP
            if (state == FSM_UDP_HDR && state_next == FSM_DROP)
                stat_wrong_port <= 1'b1;
            
            // runt: any parsing state -> IDLE (tlast before header complete)
            if (state != FSM_IDLE && state != FSM_DROP && state != FSM_FORWARD &&
                state_next == FSM_IDLE && byte_valid && s_tlast)
                stat_runt <= 1'b1;
        end
    end

endmodule
