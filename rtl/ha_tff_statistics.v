`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - Statistics Engine
// Tracks packet counts, protocol types, drop reasons, and byte counts.

module ha_tff_statistics (
    input  wire        clk,
    input  wire        rst,
    
    // Status / Control
    input  wire        stats_reset,
    
    // RX Interface signals
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire [3:0]  rx_keep_bytes,
    
    // TX Interface signals
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    input  wire        m_axis_tlast,
    input  wire [3:0]  tx_keep_bytes,
    
    // Parser signals
    input  wire        tuple_valid,
    input  wire        parse_error,
    input  wire [7:0]  protocol,
    
    // Datapath Decisions
    input  wire        dp_match_valid,
    input  wire        dp_action_forward,
    
    // Output Counters
    output reg  [31:0] stat_rx_pkts,
    output reg  [31:0] stat_tx_pkts,
    output reg  [63:0] stat_rx_bytes,
    output reg  [63:0] stat_tx_bytes,
    
    output reg  [31:0] stat_tcp_pkts,
    output reg  [31:0] stat_udp_pkts,
    output reg  [31:0] stat_icmp_pkts,
    
    output reg  [31:0] stat_parse_errors,
    output reg  [31:0] stat_drops
);

    always @(posedge clk) begin
        if (rst || stats_reset) begin
            stat_rx_pkts <= 0;
            stat_rx_bytes <= 0;
            stat_tx_pkts <= 0;
            stat_tx_bytes <= 0;
            stat_tcp_pkts <= 0;
            stat_udp_pkts <= 0;
            stat_icmp_pkts <= 0;
            stat_parse_errors <= 0;
            stat_drops <= 0;
        end else begin
            // RX Counting
            if (s_axis_tvalid && s_axis_tready) begin
                stat_rx_bytes <= stat_rx_bytes + rx_keep_bytes;
                if (s_axis_tlast) begin
                    stat_rx_pkts <= stat_rx_pkts + 1;
                end
            end
            
            // TX Counting
            if (m_axis_tvalid && m_axis_tready) begin
                stat_tx_bytes <= stat_tx_bytes + tx_keep_bytes;
                if (m_axis_tlast) begin
                    stat_tx_pkts <= stat_tx_pkts + 1;
                end
            end
            
            // Protocol Counting (on tuple valid)
            if (tuple_valid) begin
                if (protocol == 8'h06) stat_tcp_pkts <= stat_tcp_pkts + 1;
                else if (protocol == 8'h11) stat_udp_pkts <= stat_udp_pkts + 1;
                else if (protocol == 8'h01) stat_icmp_pkts <= stat_icmp_pkts + 1;
            end
            
            // Parser Error Counting
            if (parse_error) begin
                stat_parse_errors <= stat_parse_errors + 1;
            end
            
            // Drop Counting
            if (dp_match_valid && !dp_action_forward) begin
                stat_drops <= stat_drops + 1;
            end
        end
    end

endmodule
