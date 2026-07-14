`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - AXI4-Lite Control Plane
// Memory-maps Configuration, Rules, and Telemetry Statistics for CPU access.

module ha_tff_axi_lite_regs (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    
    // AXI4-Lite Slave Write Interface
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    
    // AXI4-Lite Slave Read Interface
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    
    // Global Control Outputs
    output wire [127:0] hash_secret_key,
    output wire         enable_firewall,
    output wire         enable_parser,
    output wire         stats_reset,
    
    // Rule Programming Outputs
    output wire [127:0] rule_write_data,
    output wire [11:0]  rule_write_addr,
    output wire [1:0]   rule_write_bank,
    output reg          rule_write_en,
    
    // Inputs from Fabric (Telemetry Counters)
    input  wire [31:0] stat_rx_pkts,
    input  wire [31:0] stat_tx_pkts,
    input  wire [31:0] stat_drops,
    input  wire [63:0] stat_rx_bytes,
    input  wire [63:0] stat_tx_bytes,
    input  wire [31:0] stat_tcp_pkts,
    input  wire [31:0] stat_udp_pkts,
    input  wire [31:0] stat_icmp_pkts,
    input  wire [31:0] stat_parse_errors,
    
    // Performance Monitor Inputs
    input  wire [31:0] stat_rx_stalls,
    input  wire [31:0] stat_tx_stalls,
    input  wire [15:0] stat_current_occupancy,
    input  wire [31:0] stat_peak_occupancy,
    input  wire [31:0] hist_latency_under_10,
    input  wire [31:0] hist_latency_10_to_20,
    input  wire [31:0] hist_latency_over_20
);

    // Memory Map:
    // 0x00 - 0x0C : Hash Secret Key [R/W]
    // 0x10        : Control Register (Bit 0: FW En, Bit 1: Parser En, Bit 2: Stats Reset) [R/W]
    // 0x20        : Total Packets RX [R]
    // 0x24        : Total Packets TX [R]
    // 0x28        : Total Packets DROP [R]
    // 0x2C        : Total Bytes RX (Lower 32) [R]
    // 0x30        : Total Bytes RX (Upper 32) [R]
    // 0x34        : Total Bytes TX (Lower 32) [R]
    // 0x38        : Total Bytes TX (Upper 32) [R]
    // 0x3C        : TCP Packets [R]
    // 0x40        : UDP Packets [R]
    // 0x44        : ICMP Packets [R]
    // 0x48        : Parse Errors [R]
    // 0x4C        : Version/Magic Number (0xFACEB00C) [R]
    
    // 0x50        : Rule Word 0 [R/W]
    // 0x54        : Rule Word 1 [R/W]
    // 0x58        : Rule Word 2 [R/W]
    // 0x5C        : Rule Word 3 [R/W]
    // 0x60        : Rule Control (addr[11:0], bank[17:16], write_en[31]) [W]
    
    // 0x64        : RX Stalls [R]
    // 0x68        : TX Stalls [R]
    // 0x6C        : Peak Occ [31:16] | Current Occ [15:0] [R]
    // 0x70        : Latency Histogram < 10 [R]
    // 0x74        : Latency Histogram 10-20 [R]
    // 0x78        : Latency Histogram > 20 [R]
    
    reg [31:0] reg_key0, reg_key1, reg_key2, reg_key3;
    reg [31:0] reg_control;
    reg [31:0] reg_rule0, reg_rule1, reg_rule2, reg_rule3;
    reg [31:0] reg_rule_ctrl;
    
    // Write logic
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = (s_axi_awvalid && s_axi_wvalid);
    
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            reg_key0 <= 32'hDEADBEEF;
            reg_key1 <= 32'hCAFEBABE;
            reg_key2 <= 32'h8BADF00D;
            reg_key3 <= 32'h0DEFACED;
            reg_control <= 32'h00000003; // Default: FW and Parser enabled
        end else begin
            // Self-clearing reset bit and write strobe
            if (reg_control[2]) begin
                reg_control[2] <= 1'b0;
            end
            if (rule_write_en) begin
                rule_write_en <= 1'b0; // Single cycle strobe
                reg_rule_ctrl[31] <= 1'b0;
            end
            
            if (s_axi_awvalid && s_axi_wvalid) begin
                case (s_axi_awaddr[7:2])
                    6'h00: reg_key0 <= s_axi_wdata;
                    6'h01: reg_key1 <= s_axi_wdata;
                    6'h02: reg_key2 <= s_axi_wdata;
                    6'h03: reg_key3 <= s_axi_wdata;
                    6'h04: reg_control <= s_axi_wdata;
                    
                    6'h14: reg_rule0 <= s_axi_wdata; // 0x50
                    6'h15: reg_rule1 <= s_axi_wdata; // 0x54
                    6'h16: reg_rule2 <= s_axi_wdata; // 0x58
                    6'h17: reg_rule3 <= s_axi_wdata; // 0x5C
                    6'h18: begin // 0x60
                        reg_rule_ctrl <= s_axi_wdata;
                        if (s_axi_wdata[31]) begin
                            rule_write_en <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
    
    assign hash_secret_key = {reg_key3, reg_key2, reg_key1, reg_key0};
    assign enable_firewall = reg_control[0];
    assign enable_parser   = reg_control[1];
    assign stats_reset     = reg_control[2];
    
    assign rule_write_data = {reg_rule3, reg_rule2, reg_rule1, reg_rule0};
    assign rule_write_addr = reg_rule_ctrl[11:0];
    assign rule_write_bank = reg_rule_ctrl[17:16];

    // Read logic
    reg rvalid_reg;
    assign s_axi_arready = !rvalid_reg;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rresp   = 2'b00;
    
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            rvalid_reg <= 1'b0;
            s_axi_rdata <= 32'd0;
        end else begin
            if (s_axi_arvalid && !rvalid_reg) begin
                rvalid_reg <= 1'b1;
                case (s_axi_araddr[7:2])
                    6'h00: s_axi_rdata <= reg_key0;
                    6'h01: s_axi_rdata <= reg_key1;
                    6'h02: s_axi_rdata <= reg_key2;
                    6'h03: s_axi_rdata <= reg_key3;
                    6'h04: s_axi_rdata <= reg_control;
                    
                    6'h08: s_axi_rdata <= stat_rx_pkts;
                    6'h09: s_axi_rdata <= stat_tx_pkts;
                    6'h0A: s_axi_rdata <= stat_drops;
                    6'h0B: s_axi_rdata <= stat_rx_bytes[31:0];
                    6'h0C: s_axi_rdata <= stat_rx_bytes[63:32];
                    6'h0D: s_axi_rdata <= stat_tx_bytes[31:0];
                    6'h0E: s_axi_rdata <= stat_tx_bytes[63:32];
                    6'h0F: s_axi_rdata <= stat_tcp_pkts;
                    
                    6'h10: s_axi_rdata <= stat_udp_pkts;
                    6'h11: s_axi_rdata <= stat_icmp_pkts;
                    6'h12: s_axi_rdata <= stat_parse_errors;
                    6'h13: s_axi_rdata <= 32'hFACEB00C; // Magic version
                    
                    6'h19: s_axi_rdata <= stat_rx_stalls;
                    6'h1A: s_axi_rdata <= stat_tx_stalls;
                    6'h1B: s_axi_rdata <= {stat_peak_occupancy[15:0], stat_current_occupancy};
                    6'h1C: s_axi_rdata <= hist_latency_under_10;
                    6'h1D: s_axi_rdata <= hist_latency_10_to_20;
                    6'h1E: s_axi_rdata <= hist_latency_over_20;
                    
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rready && rvalid_reg) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
