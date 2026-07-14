`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - Performance Monitor
// Tracks pipeline stalls, occupancy, and packet processing latency.

module ha_tff_performance_monitor (
    input  wire        clk,
    input  wire        rst,
    
    // Status / Control
    input  wire        monitor_reset,
    
    // RX Interface signals (Ingress)
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tready,
    input  wire        s_axis_tlast,
    
    // TX Interface signals (Egress)
    input  wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    input  wire        m_axis_tlast,
    
    // Output Metrics
    output reg  [31:0] stat_rx_stalls,
    output reg  [31:0] stat_tx_stalls,
    output wire [15:0] stat_current_occupancy,
    output reg  [31:0] stat_peak_occupancy,
    
    // Latency Histogram (Buckets)
    output reg  [31:0] hist_latency_under_10,
    output reg  [31:0] hist_latency_10_to_20,
    output reg  [31:0] hist_latency_over_20
);

    // Track active packets in flight (Occupancy)
    reg [15:0] active_packets;
    assign stat_current_occupancy = active_packets;
    
    // Track latency of the current packet
    // Note: This is simplified for a single-packet-in-flight scenario.
    // For pipelined multi-packet, a small FIFO tracking start timestamps is standard.
    reg [31:0] packet_timer;
    reg        measuring;
    reg        rx_in_pkt;
    
    wire       rx_start;
    wire       tx_end;
    
    assign rx_start = s_axis_tvalid && s_axis_tready && !rx_in_pkt;
    assign tx_end   = m_axis_tvalid && m_axis_tready && m_axis_tlast;
    
    always @(posedge clk) begin
        if (rst || monitor_reset) begin
            stat_rx_stalls <= 0;
            stat_tx_stalls <= 0;
            active_packets <= 0;
            stat_peak_occupancy <= 0;
            hist_latency_under_10 <= 0;
            hist_latency_10_to_20 <= 0;
            hist_latency_over_20 <= 0;
            packet_timer <= 0;
            measuring <= 0;
            rx_in_pkt <= 0;
        end else begin
            // 1. Stall Counting
            if (s_axis_tvalid && !s_axis_tready) begin
                stat_rx_stalls <= stat_rx_stalls + 1;
            end
            if (m_axis_tvalid && !m_axis_tready) begin
                stat_tx_stalls <= stat_tx_stalls + 1;
            end
            
            // 2. Occupancy Tracking
            if (s_axis_tvalid && s_axis_tready) begin
                if (!rx_in_pkt && !s_axis_tlast) begin
                    rx_in_pkt <= 1;
                end else if (rx_in_pkt && s_axis_tlast) begin
                    rx_in_pkt <= 0;
                end
            end
            
            if (rx_start && !tx_end) begin
                active_packets <= active_packets + 1;
            end else if (!rx_start && tx_end) begin
                if (active_packets > 0) active_packets <= active_packets - 1;
            end
            
            // Simplified Latency Tracking for first packet
            if (rx_start && !measuring) begin
                measuring <= 1;
                packet_timer <= 1; // Start counting cycles
            end
            
            if (measuring) begin
                packet_timer <= packet_timer + 1;
            end
            
            if (tx_end) begin
                measuring <= 0; // Stop measuring
                
                // Classify Latency into Histogram Buckets
                if (packet_timer < 10) begin
                    hist_latency_under_10 <= hist_latency_under_10 + 1;
                end else if (packet_timer <= 20) begin
                    hist_latency_10_to_20 <= hist_latency_10_to_20 + 1;
                end else begin
                    hist_latency_over_20 <= hist_latency_over_20 + 1;
                end
            end
            
            // 3. Peak Occupancy
            if (active_packets > stat_peak_occupancy) begin
                stat_peak_occupancy <= active_packets;
            end
        end
    end

endmodule
