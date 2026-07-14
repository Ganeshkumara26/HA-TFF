`timescale 1ns / 1ps

// AXI4-Lite Control Plane Registers
// Memory-maps the SNN weights and Hash Secret Key so a CPU can dynamically
// update them, replacing the static ROM assignments.

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
    
    // AXI4-Lite Slave Read Interface (Omitted for simplicity in prototype, write-only for now)
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    
    // Outputs to Fabric
    output wire [127:0] w0_flat,
    output wire [127:0] w1_flat,
    output wire [127:0] hash_secret_key
);

    // Memory Map:
    // 0x00 - 0x0C : Hash Secret Key (4 x 32-bit)
    // 0x10 - 0x1C : w0 Weights (4 x 32-bit, containing 8x16-bit weights)
    // 0x20 - 0x2C : w1 Weights (4 x 32-bit, containing 8x16-bit weights)
    
    reg [31:0] slv_reg0; // key[31:0]
    reg [31:0] slv_reg1; // key[63:32]
    reg [31:0] slv_reg2; // key[95:64]
    reg [31:0] slv_reg3; // key[127:96]
    
    reg [31:0] slv_reg4; // w0[1:0]
    reg [31:0] slv_reg5; // w0[3:2]
    reg [31:0] slv_reg6; // w0[5:4]
    reg [31:0] slv_reg7; // w0[7:6]
    
    reg [31:0] slv_reg8; // w1[1:0]
    reg [31:0] slv_reg9; // w1[3:2]
    reg [31:0] slv_reg10; // w1[5:4]
    reg [31:0] slv_reg11; // w1[7:6]

    // Tie off AXI responses (Always ready)
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_bvalid  = (s_axi_awvalid && s_axi_wvalid);
    
    assign s_axi_arready = 1'b1;
    assign s_axi_rdata   = 32'd0;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = s_axi_arvalid;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            // Default Initialization (Fallback to old hardcoded values)
            slv_reg0 <= 32'hDEADBEEF;
            slv_reg1 <= 32'hCAFEBABE;
            slv_reg2 <= 32'h8BADF00D;
            slv_reg3 <= 32'h0DEFACED;
            
            // w0 defaults (50, 20), (0, 10), (-100, -50), (30, 40) -> Note 16'sd representation
            slv_reg4 <= {16'd20, 16'd50};
            slv_reg5 <= {16'd10, 16'd0};
            slv_reg6 <= {-16'd50, -16'd100};
            slv_reg7 <= {16'd40, 16'd30};
            
            // w1 defaults
            slv_reg8 <= {-16'd20, -16'd40};
            slv_reg9 <= {16'd80, 16'd150};
            slv_reg10 <= {16'd60, 16'd120};
            slv_reg11 <= {16'd50, -16'd30};
            
        end else begin
            if (s_axi_awvalid && s_axi_wvalid) begin
                case (s_axi_awaddr[7:2])
                    6'h00: slv_reg0 <= s_axi_wdata;
                    6'h01: slv_reg1 <= s_axi_wdata;
                    6'h02: slv_reg2 <= s_axi_wdata;
                    6'h03: slv_reg3 <= s_axi_wdata;
                    
                    6'h04: slv_reg4 <= s_axi_wdata;
                    6'h05: slv_reg5 <= s_axi_wdata;
                    6'h06: slv_reg6 <= s_axi_wdata;
                    6'h07: slv_reg7 <= s_axi_wdata;
                    
                    6'h08: slv_reg8 <= s_axi_wdata;
                    6'h09: slv_reg9 <= s_axi_wdata;
                    6'h0A: slv_reg10 <= s_axi_wdata;
                    6'h0B: slv_reg11 <= s_axi_wdata;
                endcase
            end
        end
    end
    
    assign hash_secret_key = {slv_reg3, slv_reg2, slv_reg1, slv_reg0};
    assign w0_flat = {slv_reg7, slv_reg6, slv_reg5, slv_reg4};
    assign w1_flat = {slv_reg11, slv_reg10, slv_reg9, slv_reg8};

endmodule
