`timescale 1ns / 1ps

// Hardware-Accelerated Traffic Filter Firewall (HA-TFF) - SYSTEM TOP v005
// Iteration 013: Incorporates AXI4-Lite Control Plane for Dynamic SNN Weights
// and Hash Secret Key (Algorithmic Complexity Mitigation).

module ha_tff_system_top_v005 (
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

    // -------------------------------------------------------------------------
    // AXI4-Lite Control Plane
    // -------------------------------------------------------------------------
    
    wire [127:0] w0_flat;
    wire [127:0] w1_flat;
    wire [127:0] hash_secret_key;
    
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
        .w0_flat(w0_flat),
        .w1_flat(w1_flat),
        .hash_secret_key(hash_secret_key)
    );

    // -------------------------------------------------------------------------
    // SNN Feature Extraction
    // -------------------------------------------------------------------------
    
    wire [31:0] src_ip;
    wire [31:0] dst_ip;
    wire [15:0] src_port;
    wire [15:0] dst_port;
    wire [7:0]  protocol;
    wire        tuple_valid;
    wire        parse_error;
    
    // We instantiate parser_snn purely to drive the SNN features here. 
    // The datapath has its own internal parser to avoid routing congestion for the 104-bit bus.
    ha_tff_parser_v002 parser_snn_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(), 
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .protocol(protocol),
        .tuple_valid(tuple_valid),
        .parse_error(parse_error)
    );

    wire [7:0]  snn_spikes_in;
    wire        snn_spikes_valid;
    
    snn_feature_encoder encoder_inst (
        .clk(clk),
        .rst(rst),
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .protocol(protocol),
        .meta_valid(tuple_valid),
        .out_spikes(snn_spikes_in),
        .spike_valid(snn_spikes_valid)
    );
    
    // -------------------------------------------------------------------------
    // SNN Coprocessor (Dynamic Weights)
    // -------------------------------------------------------------------------
    
    wire [1:0] snn_out_spikes;
    wire       snn_out_valid;
    
    snn_tff_layer_v005 snn_core (
        .clk(clk),
        .rst(rst),
        .in_spikes(snn_spikes_in),
        .valid_in(snn_spikes_valid),
        .w0_flat(w0_flat),
        .w1_flat(w1_flat),
        .out_spikes(snn_out_spikes),
        .valid_out(snn_out_valid)
    );
    
    reg anomaly_detected;
    always @(posedge clk) begin
        if (rst) begin
            anomaly_detected <= 0;
        end else if (snn_out_spikes[1]) begin
            anomaly_detected <= 1'b1; 
        end else if (snn_out_spikes[0]) begin
            anomaly_detected <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Rule-Based Exact Match Datapath (Secured Hash)
    // -------------------------------------------------------------------------
    
    wire dp_match_valid;
    wire dp_match_found;
    wire dp_action_forward;
    
    ha_tff_datapath_top_v003 datapath_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .secret_key(hash_secret_key),
        .match_valid(dp_match_valid),
        .match_found(dp_match_found),
        .action_forward(dp_action_forward),
        .parse_error()
    );

    // -------------------------------------------------------------------------
    // Synchronization & Pipeline
    // -------------------------------------------------------------------------
    
    // SYNCHRONIZATION STAGE: Datapath is 4 cycles. SNN is 5 cycles.
    reg dp_match_valid_d1;
    reg dp_action_forward_d1;
    always @(posedge clk) begin
        if (rst) begin
            dp_match_valid_d1 <= 0;
            dp_action_forward_d1 <= 0;
        end else begin
            dp_match_valid_d1 <= dp_match_valid;
            dp_action_forward_d1 <= dp_action_forward;
        end
    end

    // PIPELINE STAGE: Combine decisions in cycle 6
    reg final_forward_reg;
    always @(posedge clk) begin
        if (rst) begin
            final_forward_reg <= 1'b0;
        end else begin
            final_forward_reg <= (dp_match_valid_d1 && dp_action_forward_d1 && !anomaly_detected);
        end
    end

    // DATA SYNCHRONIZATION: Total latency is 6 cycles.
    wire [63:0] delayed_tdata;
    wire [7:0]  delayed_tkeep;
    wire        delayed_tlast;
    wire        delayed_tvalid;
    
    axi_stream_delay_line #(.LATENCY(6)) data_delay_inst (
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
    
    // Output valid only if our security checks passed.
    assign m_axis_tvalid = (delayed_tvalid && final_forward_reg);

endmodule
