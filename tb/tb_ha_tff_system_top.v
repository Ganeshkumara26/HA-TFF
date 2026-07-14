`timescale 1ns / 1ps

// System-Level Testbench for HA-TFF v005
// Tests the complete firewall pipeline: Parser → Hash → Matcher + SNN → Decision
// Includes AXI4-Lite control plane stimulus for dynamic weight loading.

module tb_ha_tff_system_top;

    reg clk;
    reg rst;

    // AXI4-Lite Control Plane
    reg [31:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg [31:0]  s_axi_wdata;
    reg [3:0]   s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg [31:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // AXI4-Stream Input (10GbE MAC)
    reg [63:0]  s_axis_tdata;
    reg [7:0]   s_axis_tkeep;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;

    // AXI4-Stream Output (To Network)
    wire [63:0] m_axis_tdata;
    wire [7:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready;

    // DUT: Final system top (v005 with AXI-Lite control plane)
    ha_tff_system_top_v005 uut (
        .clk(clk),
        .rst(rst),
        // AXI4-Lite
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
        // AXI4-Stream
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tready(m_axis_tready)
    );

    // =========================================================================
    // Clock Generation: 156.25 MHz (6.4ns period)
    // =========================================================================
    initial begin
        $dumpfile("tb_ha_tff_system_top.vcd");
        $dumpvars(0, tb_ha_tff_system_top);
        clk = 0;
        forever #3.2 clk = ~clk;
    end

    // =========================================================================
    // AXI4-Lite Write Task
    // =========================================================================
    task axi_lite_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1;
            s_axi_bready  <= 1;
            @(posedge clk);
            s_axi_awvalid <= 0;
            s_axi_wvalid  <= 0;
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // Output Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("[%0t] SYSTEM OUT: Packet Forwarded. Data: %h", $time, m_axis_tdata);
        end
        if (uut.anomaly_detected) begin
            $display("[%0t] SNN TRIGGERED: Anomaly Active! All traffic dropping.", $time);
        end
    end

    // =========================================================================
    // Main Stimulus
    // =========================================================================
    initial begin
        // Initialize all signals
        rst = 1;
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tkeep  = 8'hFF;
        s_axis_tlast  = 0;
        m_axis_tready = 1;

        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 1;

        #100;
        rst = 0;

        // -----------------------------------------------------------------
        // Phase 1: Program SNN weights via AXI-Lite
        // -----------------------------------------------------------------
        $display("[%0t] PHASE 1: Programming SNN weights via AXI-Lite", $time);

        // Hash secret key (registers 0x00-0x0C)
        axi_lite_write(32'h00, 32'hDEADBEEF);
        axi_lite_write(32'h04, 32'hCAFEBABE);
        axi_lite_write(32'h08, 32'h8BADF00D);
        axi_lite_write(32'h0C, 32'h0DEFACED);

        // w0 weights (registers 0x10-0x1C)
        axi_lite_write(32'h10, {16'd20, 16'd50});
        axi_lite_write(32'h14, {16'd10, 16'd0});
        axi_lite_write(32'h18, {-16'd50, -16'd100});
        axi_lite_write(32'h1C, {16'd40, 16'd30});

        // w1 weights (registers 0x20-0x2C)
        axi_lite_write(32'h20, {-16'd20, -16'd40});
        axi_lite_write(32'h24, {16'd80, 16'd150});
        axi_lite_write(32'h28, {16'd60, 16'd120});
        axi_lite_write(32'h2C, {16'd50, -16'd30});

        $display("[%0t] PHASE 1 COMPLETE: Weights programmed", $time);

        // -----------------------------------------------------------------
        // Phase 2: Inject Safe Traffic
        // -----------------------------------------------------------------
        #50;
        $display("[%0t] PHASE 2: Injecting safe traffic metadata", $time);
        force uut.parser_snn_inst.tuple_valid = 1;
        force uut.parser_snn_inst.src_ip      = 32'h0A000001;
        force uut.parser_snn_inst.dst_ip      = 32'h08080808;
        force uut.parser_snn_inst.src_port    = 16'd10000;
        force uut.parser_snn_inst.dst_port    = 16'd80;
        force uut.parser_snn_inst.protocol    = 8'd6; // TCP

        force uut.datapath_inst.match_valid    = 1;
        force uut.datapath_inst.action_forward = 1;

        s_axis_tvalid = 1;
        s_axis_tdata  = 64'h5AFE_CAFE_BEEF_0001;

        #6.4; // 1 clock cycle
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;

        // -----------------------------------------------------------------
        // Phase 3: Inject Anomaly Traffic
        // -----------------------------------------------------------------
        #250;
        $display("[%0t] PHASE 3: Injecting anomaly traffic (UDP, High Port, Multicast, DNS)", $time);
        force uut.parser_snn_inst.src_ip   = 32'h0A000001;
        force uut.parser_snn_inst.dst_ip   = 32'h080808FF;  // Broadcast
        force uut.parser_snn_inst.src_port = 16'd50000;     // High port
        force uut.parser_snn_inst.dst_port = 16'd53;        // DNS
        force uut.parser_snn_inst.protocol = 8'd17;         // UDP

        #200;
        // Inject packet while anomaly is active — should be DROPPED
        s_axis_tvalid = 1;
        s_axis_tdata  = 64'hBAD0_BAD0_BAD0_BAD0;

        #6.4; // 1 cycle
        s_axis_tvalid = 0;
        s_axis_tdata  = 0;

        #100;
        $display("[%0t] TEST COMPLETE", $time);
        $finish;
    end

endmodule
