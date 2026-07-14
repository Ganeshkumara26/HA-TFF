`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall (HA-TFF) - SYSTEM TOP
// Pure RTL Datapath for 10Gbps Packet Classification and Telemetry

module ha_tff_system_top (
    input  wire         clk,
    input  wire         rst,

    // AXI4-Lite Control Plane Interface
    input  wire [31:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    // AXI4-Stream Input (10GbE MAC)
    input  wire [63:0]  s_axis_tdata,
    input  wire [7:0]   s_axis_tkeep,
    input  wire         s_axis_tvalid,
    input  wire         s_axis_tlast,
    output wire         s_axis_tready,

    // AXI4-Stream Output (To Network)
    output wire [63:0]  m_axis_tdata,
    output wire [7:0]   m_axis_tkeep,
    output wire         m_axis_tvalid,
    output wire         m_axis_tlast,
    input  wire         m_axis_tready
);

    // Performance Monitor Signals
    wire [31:0] stat_rx_stalls;
    wire [31:0] stat_tx_stalls;
    wire [15:0] stat_current_occupancy;
    wire [31:0] stat_peak_occupancy;
    wire [31:0] hist_latency_under_10;
    wire [31:0] hist_latency_10_to_20;
    wire [31:0] hist_latency_over_20;

    // -------------------------------------------------------------------------
    // AXI4-Lite Control Plane
    // -------------------------------------------------------------------------
    
    wire [127:0] hash_secret_key;
    wire         enable_firewall;
    wire         enable_parser;
    wire         stats_reset;
    
    wire [127:0] rule_write_data;
    wire [11:0]  rule_write_addr;
    wire [1:0]   rule_write_bank;
    wire         rule_write_en;
    
    wire [31:0] stat_rx_pkts, stat_tx_pkts, stat_drops;
    wire [63:0] stat_rx_bytes, stat_tx_bytes;
    wire [31:0] stat_tcp_pkts, stat_udp_pkts, stat_icmp_pkts;
    wire [31:0] stat_parse_errors;
    
    ha_tff_axi_lite_regs control_plane (
        .s_axi_aclk(clk),
        .s_axi_aresetn(~rst), // AXI uses active-low reset
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        
        .hash_secret_key(hash_secret_key),
        .enable_firewall(enable_firewall),
        .enable_parser(enable_parser),
        .stats_reset(stats_reset),
        
        .rule_write_data(rule_write_data),
        .rule_write_addr(rule_write_addr),
        .rule_write_bank(rule_write_bank),
        .rule_write_en(rule_write_en),
        
        .stat_rx_pkts(stat_rx_pkts),
        .stat_tx_pkts(stat_tx_pkts),
        .stat_drops(stat_drops),
        .stat_rx_bytes(stat_rx_bytes),
        .stat_tx_bytes(stat_tx_bytes),
        .stat_tcp_pkts(stat_tcp_pkts),
        .stat_udp_pkts(stat_udp_pkts),
        .stat_icmp_pkts(stat_icmp_pkts),
        .stat_parse_errors(stat_parse_errors),
        
        // Performance Monitor Telemetry
        .stat_rx_stalls(stat_rx_stalls),
        .stat_tx_stalls(stat_tx_stalls),
        .stat_current_occupancy(stat_current_occupancy),
        .stat_peak_occupancy(stat_peak_occupancy),
        .hist_latency_under_10(hist_latency_under_10),
        .hist_latency_10_to_20(hist_latency_10_to_20),
        .hist_latency_over_20(hist_latency_over_20)
    );

    // -------------------------------------------------------------------------
    // Rule-Based Exact Match Datapath
    // -------------------------------------------------------------------------
    
    wire dp_match_found;
    wire dp_match_valid;
    wire dp_action_forward;
    wire parse_error;
    wire [7:0] protocol_out;
    wire tuple_valid_out;
    
    // Gated input valid based on global parser enable
    wire gated_s_axis_tvalid = s_axis_tvalid & enable_parser;
    
    ha_tff_datapath_top datapath_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(gated_s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .secret_key(hash_secret_key),
        .match_valid(dp_match_valid),
        .match_found(dp_match_found),
        .action_forward(dp_action_forward),
        .parse_error(parse_error),
        .protocol_out(protocol_out),
        .tuple_valid_out(tuple_valid_out),
        
        .rule_write_data(rule_write_data),
        .rule_write_addr(rule_write_addr),
        .rule_write_bank(rule_write_bank),
        .rule_write_en(rule_write_en)
    );

    // -------------------------------------------------------------------------
    // Hardware Telemetry Statistics Engine
    // -------------------------------------------------------------------------
    
    // Calculate valid bytes from tkeep
    wire [3:0] rx_keep_bytes = s_axis_tkeep[7] ? 4'd8 :
                               s_axis_tkeep[6] ? 4'd7 :
                               s_axis_tkeep[5] ? 4'd6 :
                               s_axis_tkeep[4] ? 4'd5 :
                               s_axis_tkeep[3] ? 4'd4 :
                               s_axis_tkeep[2] ? 4'd3 :
                               s_axis_tkeep[1] ? 4'd2 :
                               s_axis_tkeep[0] ? 4'd1 : 4'd0;
                               
    wire [3:0] tx_keep_bytes = m_axis_tkeep[7] ? 4'd8 :
                               m_axis_tkeep[6] ? 4'd7 :
                               m_axis_tkeep[5] ? 4'd6 :
                               m_axis_tkeep[4] ? 4'd5 :
                               m_axis_tkeep[3] ? 4'd4 :
                               m_axis_tkeep[2] ? 4'd3 :
                               m_axis_tkeep[1] ? 4'd2 :
                               m_axis_tkeep[0] ? 4'd1 : 4'd0;

    ha_tff_statistics stats_engine (
        .clk(clk),
        .rst(rst),
        .stats_reset(stats_reset),
        
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .rx_keep_bytes(rx_keep_bytes),
        
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .tx_keep_bytes(tx_keep_bytes),
        
        .tuple_valid(tuple_valid_out),
        .parse_error(parse_error),
        .protocol(protocol_out),
        
        .dp_match_valid(dp_match_valid),
        .dp_action_forward(dp_action_forward),
        
        .stat_rx_pkts(stat_rx_pkts),
        .stat_tx_pkts(stat_tx_pkts),
        .stat_rx_bytes(stat_rx_bytes),
        .stat_tx_bytes(stat_tx_bytes),
        .stat_tcp_pkts(stat_tcp_pkts),
        .stat_udp_pkts(stat_udp_pkts),
        .stat_icmp_pkts(stat_icmp_pkts),
        .stat_parse_errors(stat_parse_errors),
        .stat_drops(stat_drops)
    );

    // -------------------------------------------------------------------------
    // Performance Monitor
    // -------------------------------------------------------------------------
    
    ha_tff_performance_monitor perf_monitor (
        .clk(clk),
        .rst(rst),
        .monitor_reset(stats_reset),
        
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        
        .stat_rx_stalls(stat_rx_stalls),
        .stat_tx_stalls(stat_tx_stalls),
        .stat_current_occupancy(stat_current_occupancy),
        .stat_peak_occupancy(stat_peak_occupancy),
        .hist_latency_under_10(hist_latency_under_10),
        .hist_latency_10_to_20(hist_latency_10_to_20),
        .hist_latency_over_20(hist_latency_over_20)
    );

    // -------------------------------------------------------------------------
    // Synchronization & Pipeline (Decision FIFO)
    // -------------------------------------------------------------------------
    
    // DECISION FIFO: Stores 1 bit (forward/drop) per packet
    reg decision_fifo [0:31];
    reg [4:0] dec_wr_ptr;
    reg [4:0] dec_rd_ptr;
    
    wire dec_fifo_empty = (dec_wr_ptr == dec_rd_ptr);
    wire decision_write = dp_match_valid || parse_error;
    wire decision_val   = (dp_match_valid && dp_action_forward);
    
    always @(posedge clk) begin
        if (rst) begin
            dec_wr_ptr <= 0;
        end else begin
            if (decision_write) begin
                decision_fifo[dec_wr_ptr] <= decision_val;
                dec_wr_ptr <= dec_wr_ptr + 1;
            end
        end
    end
    
    reg pkt_forward;
    reg pkt_active;
    
    // DATA SYNCHRONIZATION: Total latency is 16 cycles.
    wire [63:0] delayed_tdata;
    wire [7:0]  delayed_tkeep;
    wire        delayed_tlast;
    wire        delayed_tvalid;
    
    always @(posedge clk) begin
        if (rst) begin
            dec_rd_ptr <= 0;
            pkt_forward <= 0;
            pkt_active <= 0;
        end else begin
            if (delayed_tvalid && !pkt_active) begin
                if (!enable_firewall) begin
                    pkt_forward <= 1'b1;
                    if (!delayed_tlast) pkt_active <= 1;
                end else if (!dec_fifo_empty) begin
                    pkt_forward <= decision_fifo[dec_rd_ptr];
                    dec_rd_ptr <= dec_rd_ptr + 1;
                    if (!delayed_tlast) pkt_active <= 1;
                end else begin
                    pkt_forward <= 1'b0; // Underflow, drop
                    if (!delayed_tlast) pkt_active <= 1;
                end
            end else if (delayed_tvalid && pkt_active) begin
                if (delayed_tlast) begin
                    pkt_active <= 0;
                end
            end
        end
    end

    axi_stream_delay_line #(.LATENCY(16)) data_delay_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid),
        .m_axis_tdata(delayed_tdata),
        .m_axis_tkeep(delayed_tkeep),
        .m_axis_tlast(delayed_tlast),
        .m_axis_tvalid(delayed_tvalid)
    );
    
    assign m_axis_tdata  = delayed_tdata;
    assign m_axis_tkeep  = delayed_tkeep;
    assign m_axis_tlast  = delayed_tlast;
    
    wire current_forward = (!enable_firewall) ? 1'b1 :
                           (pkt_active) ? pkt_forward : 
                           (!dec_fifo_empty) ? decision_fifo[dec_rd_ptr] : 1'b0;
    
    // Output valid only if our firewall rules passed (or bypass is active)
    assign m_axis_tvalid = (delayed_tvalid && current_forward);

endmodule
