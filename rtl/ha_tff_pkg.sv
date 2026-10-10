/*
 * ha_tff_pkg.sv - package for the HA-TFF hardware filter
 *
 * types, constants, configuration parameters.
 * 
 * putting everything in a package because my supervisor said
 * "if i see one more magic number in your RTL im sending you
 * back to the python codebase." fair.
 *
 * the configuration parameters at the top control things like
 * FIFO depth, number of allowed sysids, and register addresses.
 * these can be overridden at instantiation if needed.
 *
 * sept 2, 2026
 */

package ha_tff_pkg;

    // =========================================================
    //  Configuration Parameters
    // =========================================================
    
    // FIFO depth for filtered telemetry (must be power of 2)
    // 64 entries * 4 bytes = 256 bytes. small enough to fit in
    // BRAM slice, big enough to buffer a burst of mavlink packets
    // while the CPU is doing other things.
    parameter int FIFO_DEPTH     = 64;
    parameter int FIFO_ADDR_BITS = $clog2(FIFO_DEPTH);
    
    // max number of allowed MAVLink system IDs
    // 8 should be enough for a fleet of drones. if we need more,
    // switch to a CAM (content-addressable memory) approach.
    parameter int MAX_SYSIDS     = 8;
    
    // MAVLink port (UDP destination port for MAVLink traffic)
    parameter int MAV_PORT       = 14550;
    
    // alternate MAVLink port (some GCS software uses 14555)
    parameter int MAV_PORT_ALT   = 14555;
    
    
    // =========================================================
    //  Protocol Constants
    // =========================================================
    
    // ethernet
    parameter logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
    parameter logic [15:0] ETHERTYPE_ARP  = 16'h0806;  // drop
    
    // IP protocol numbers
    parameter logic [7:0] IPPROTO_TCP  = 8'd6;
    parameter logic [7:0] IPPROTO_UDP  = 8'd17;
    parameter logic [7:0] IPPROTO_ICMP = 8'd1;
    
    // MAVLink v2
    parameter logic [7:0] MAV_STX_V2 = 8'hFD;  // magic start byte
    parameter logic [7:0] MAV_STX_V1 = 8'hFE;  // v1 (ignored)
    
    // ethernet header offsets (byte positions)
    parameter int ETH_DST_MAC    = 0;    // bytes 0-5
    parameter int ETH_SRC_MAC    = 6;    // bytes 6-11
    parameter int ETH_ETHERTYPE  = 12;   // bytes 12-13
    parameter int ETH_HDR_LEN    = 14;
    
    // IP header offsets (relative to IP start)
    parameter int IP_VER_IHL     = 0;
    parameter int IP_TOTAL_LEN   = 2;    // bytes 2-3
    parameter int IP_PROTOCOL    = 9;
    parameter int IP_SRC_ADDR    = 12;   // bytes 12-15
    parameter int IP_DST_ADDR    = 16;   // bytes 16-19
    parameter int IP_HDR_MIN_LEN = 20;   // no options
    
    // UDP header offsets (relative to UDP start)
    parameter int UDP_SRC_PORT   = 0;    // bytes 0-1
    parameter int UDP_DST_PORT   = 2;    // bytes 2-3
    parameter int UDP_LENGTH     = 4;    // bytes 4-5
    parameter int UDP_CHECKSUM   = 6;    // bytes 6-7
    parameter int UDP_HDR_LEN    = 8;
    
    // MAVLink v2 header offsets (relative to MAVLink start)
    parameter int MAV_LEN        = 1;    // payload length
    parameter int MAV_INCOMPAT   = 2;
    parameter int MAV_COMPAT     = 3;
    parameter int MAV_SEQ        = 4;
    parameter int MAV_SYSID      = 5;
    parameter int MAV_COMPID     = 6;
    parameter int MAV_MSGID_LO   = 7;
    parameter int MAV_MSGID_MID  = 8;
    parameter int MAV_MSGID_HI   = 9;
    parameter int MAV_HDR_LEN    = 10;
    
    
    // =========================================================
    //  FSM States
    // =========================================================
    
    // main parser FSM states
    typedef enum logic [3:0] {
        FSM_IDLE        = 4'd0,
        FSM_ETH_HDR     = 4'd1,
        FSM_IP_HDR      = 4'd2,
        FSM_UDP_HDR     = 4'd3,
        FSM_MAV_SYNC    = 4'd4,
        FSM_MAV_HDR     = 4'd5,
        FSM_MAV_PAYLOAD = 4'd6,
        FSM_MAV_CRC     = 4'd7,
        FSM_FORWARD     = 4'd8,
        FSM_DROP        = 4'd9
    } parser_state_t;
    
    // vivado will probably re-encode this as one-hot anyway.
    // NOT manually overriding this time. learned that lesson.
    
    
    // =========================================================
    //  Wishbone Register Map
    // =========================================================
    
    // register offsets from base address
    // the base address itself is set in wb_intercon.v when we
    // integrate into veerwolf. for standalone testing we use
    // 0x80002000 (in the veerwolf peripheral address space).
    
    parameter logic [7:0] REG_CTRL       = 8'h00;  // R/W control
    parameter logic [7:0] REG_STATUS     = 8'h04;  // R   status
    parameter logic [7:0] REG_PKT_TOTAL  = 8'h08;  // R   total packets
    parameter logic [7:0] REG_PKT_PASS   = 8'h0C;  // R   packets passed
    parameter logic [7:0] REG_PKT_DROP   = 8'h10;  // R   packets dropped
    parameter logic [7:0] REG_CRC_ERR    = 8'h14;  // R   CRC errors
    parameter logic [7:0] REG_FIFO_DATA  = 8'h18;  // R   read from FIFO (auto-pop)
    parameter logic [7:0] REG_FIFO_LEVEL = 8'h1C;  // R   FIFO fill level
    parameter logic [7:0] REG_SYSID_0    = 8'h20;  // R/W allowed sysid 0
    parameter logic [7:0] REG_SYSID_1    = 8'h24;  // R/W allowed sysid 1
    parameter logic [7:0] REG_SYSID_2    = 8'h28;  // R/W allowed sysid 2
    parameter logic [7:0] REG_SYSID_3    = 8'h2C;  // R/W allowed sysid 3
    parameter logic [7:0] REG_SYSID_4    = 8'h30;  // R/W allowed sysid 4
    parameter logic [7:0] REG_SYSID_5    = 8'h34;  // R/W allowed sysid 5
    parameter logic [7:0] REG_SYSID_6    = 8'h38;  // R/W allowed sysid 6
    parameter logic [7:0] REG_SYSID_7    = 8'h3C;  // R/W allowed sysid 7
    
    // CTRL register bits
    parameter int CTRL_ENABLE      = 0;   // filter enable
    parameter int CTRL_RST_STATS   = 1;   // reset statistics (auto-clear)
    parameter int CTRL_PROMISC     = 2;   // promiscuous mode (pass all MAVLink)
    parameter int CTRL_DROP_NON_IP = 3;   // drop non-IPv4 traffic
    
    // STATUS register bits
    parameter int STAT_FIFO_EMPTY  = 0;
    parameter int STAT_FIFO_FULL   = 1;
    parameter int STAT_FSM_ACTIVE  = 2;
    // bits [7:4] = current FSM state (for debug)
    
    
    // =========================================================
    //  CRC-16 (MAVLink)
    // =========================================================
    
    // CRC-16/MCRF4XX - same algorithm as edp-core's crc16.c
    // but implemented as a combinational function for single-cycle
    // accumulation. each call advances the CRC by one byte.
    //
    // tried a lookup table first (like crc_table_fat.h in edp-core)
    // but in hardware that would be a 64KB ROM which eats BRAM.
    // the XOR-based calculation is a few LUTs and runs at 200MHz+.
    
    function automatic logic [15:0] crc_accumulate(
        input logic [7:0] data,
        input logic [15:0] crc_in
    );
        logic [15:0] crc;
        logic [7:0] tmp;
        
        tmp = data ^ crc_in[7:0];
        tmp = tmp ^ (tmp << 4);
        
        crc = (crc_in >> 8) ^ ({8'b0, tmp} << 8) ^ 
              ({8'b0, tmp} << 3) ^ ({8'b0, tmp} >> 4);
        
        return crc;
    endfunction
    
    // CRC_EXTRA lookup for known MAVLink message IDs.
    // sparse table, same idea as edp-core's crc16.c
    function automatic logic [7:0] crc_extra(input logic [23:0] msgid);
        case (msgid)
            24'd0:   return 8'd50;   // HEARTBEAT
            24'd1:   return 8'd124;  // SYS_STATUS
            24'd24:  return 8'd24;   // GPS_RAW_INT
            24'd30:  return 8'd39;   // ATTITUDE
            24'd33:  return 8'd104;  // GLOBAL_POSITION_INT
            24'd65:  return 8'd118;  // RC_CHANNELS
            24'd74:  return 8'd20;   // VFR_HUD
            24'd77:  return 8'd143;  // COMMAND_ACK
            24'd147: return 8'd154;  // BATTERY_STATUS
            24'd253: return 8'd83;   // STATUSTEXT
            default: return 8'd0;    // unknown
        endcase
    endfunction
    
    
    // =========================================================
    //  Utility Types
    // =========================================================
    
    // 5-tuple for packet classification
    typedef struct packed {
        logic [31:0] src_ip;
        logic [31:0] dst_ip;
        logic [15:0] src_port;
        logic [15:0] dst_port;
        logic [7:0]  protocol;
    } five_tuple_t;
    
    // filter decision
    typedef enum logic [1:0] {
        DECISION_PENDING = 2'b00,
        DECISION_PASS    = 2'b01,
        DECISION_DROP    = 2'b10,
        DECISION_ERROR   = 2'b11
    } filter_decision_t;

endpackage
