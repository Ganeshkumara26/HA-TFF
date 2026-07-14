`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - Testbench
// Tests the complete pipeline: Parser -> Hash -> Matcher -> Telemetry -> Decision
// Reads Telemetry Statistics via AXI4-Lite Control Plane.

module tb_ha_tff_system_top();

    reg         clk;
    reg         rst;

    // AXI4-Lite Control Plane Interface
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    
    reg  [31:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // AXI4-Stream Input (10GbE MAC)
    reg  [63:0] s_axis_tdata;
    reg  [7:0]  s_axis_tkeep;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    wire        s_axis_tready;

    // AXI4-Stream Output (To Network)
    wire [63:0] m_axis_tdata;
    wire [7:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready;

    // Instantiate the Unit Under Test (UUT)
    ha_tff_system_top_v005 uut (
        .clk(clk),
        .rst(rst),
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

    // Clock generation (156.25 MHz -> 6.4ns period)
    always #3.2 clk = ~clk;

    // AXI-Lite Write Task
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1;
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid <= 0;
            s_axi_wvalid  <= 0;
            wait(s_axi_bvalid);
            s_axi_bready  <= 1;
            @(posedge clk);
            s_axi_bready  <= 0;
        end
    endtask

    // AXI-Lite Read Task
    task axi_read(input [31:0] addr);
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1;
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid <= 0;
            wait(s_axi_rvalid);
            s_axi_rready  <= 1;
            $display("[%0t] READ ADDR 0x%h = %d", $time, addr, s_axi_rdata);
            @(posedge clk);
            s_axi_rready  <= 0;
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axis_tdata = 0; s_axis_tkeep = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
        m_axis_tready = 1;

        #50;
        rst = 0;
        #50;

        $display("[%0t] PHASE 1: Programming Hash Secret Key via AXI-Lite", $time);
        axi_write(32'h00, 32'h11223344);
        axi_write(32'h04, 32'h55667788);
        axi_write(32'h08, 32'h99AABBCC);
        axi_write(32'h0C, 32'hDDEEFF00);

        #100;
        $display("[%0t] PHASE 2: Transmitting Valid Packet (Forward Rule)", $time);
        // Valid packet headers (simulating 64-byte ethernet frame)
        @(posedge clk);
        s_axis_tvalid <= 1; s_axis_tdata <= 64'h0000000000000000; s_axis_tkeep <= 8'hFF; s_axis_tlast <= 0; // MAC
        @(posedge clk);
        s_axis_tdata <= 64'h4500002800004000; // IP header start
        @(posedge clk);
        s_axis_tdata <= 64'h4006A60FC0A80101; // Protocol TCP (06), Src IP: 192.168.1.1
        @(posedge clk);
        s_axis_tdata <= 64'h0A000001005004D2; // Dst IP: 10.0.0.1, Src Port: 80, Dst Port: 1234
        @(posedge clk);
        s_axis_tdata <= 64'h0000000000000000; s_axis_tlast <= 1; // Tail
        @(posedge clk);
        s_axis_tvalid <= 0; s_axis_tlast <= 0;

        #200;
        
        $display("[%0t] PHASE 3: Reading Telemetry Statistics", $time);
        axi_read(32'h20); // Total Packets RX
        axi_read(32'h24); // Total Packets TX
        axi_read(32'h28); // Total Packets DROP
        axi_read(32'h2C); // Total Bytes RX (Lower 32)
        axi_read(32'h34); // Total Bytes TX (Lower 32)
        axi_read(32'h3C); // TCP Packets

        #100;
        $display("[%0t] Simulation Complete.", $time);
        $finish;
    end

endmodule
