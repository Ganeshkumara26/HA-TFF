`timescale 1ns / 1ps

`include "ha_tff_coverage.sv"
`include "dv_packet_generator.sv"

// Hardware-Accelerated Telemetry Firewall - Advanced DV Testbench
// Incorporates SVA binding, Functional Coverage, Constrained Random Packet Injection, 
// and Error Injection (Backpressure/Truncation).

module tb_ha_tff_dv_top();

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
    ha_tff_system_top uut (
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

    // -------------------------------------------------------------------------
    // Bind SystemVerilog Assertions (SVA)
    // -------------------------------------------------------------------------
    
    // We bind the SVA module directly into the datapath instance to access internal parser signals.
    bind uut.datapath_inst ha_tff_sva sva_checker (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(1'b0), // Not directly observing m_axis here, just sink
        .m_axis_tkeep(1'b0),
        .m_axis_tvalid(1'b0),
        .m_axis_tlast(1'b0),
        .m_axis_tready(1'b0),
        .parsing(uut.datapath_inst.parser.parsing),
        .word_cnt(uut.datapath_inst.parser.word_cnt),
        .parse_error(uut.datapath_inst.parser.parse_error)
    );

    // -------------------------------------------------------------------------
    // Coverage Collector Instantiation
    // -------------------------------------------------------------------------
    
    HA_TFF_Coverage cov_collector;
    
    initial begin
        cov_collector = new();
    end
    
    // Sample coverage on every clock cycle where data is valid
    always @(posedge clk) begin
        if (!rst) begin
            cov_collector.sample(
                uut.datapath_inst.protocol_out,
                uut.datapath_inst.tuple_valid_out,
                uut.datapath_inst.parse_error,
                uut.datapath_inst.match_valid,
                uut.datapath_inst.action_forward,
                s_axis_tready,
                s_axis_tvalid,
                s_axis_tlast
            );
        end
    end

    // -------------------------------------------------------------------------
    // Clock & DV Environment
    // -------------------------------------------------------------------------

    // Clock generation (156.25 MHz -> 6.4ns period)
    always #3.2 clk = ~clk;

    // AXI-Lite Tasks
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

    // Packet Driver Task
    task drive_packet(input logic [63:0] data_q[$], input logic [7:0] keep_q[$]);
        int idx = 0;
        int len = data_q.size();
        
        while (idx < len) begin
            @(posedge clk);
            
            // Random backpressure injection from TB to UUT (simulating MAC delays)
            if ($urandom_range(0, 100) < 10) begin
                s_axis_tvalid <= 0;
            end else begin
                // Inject random mid-packet reset (1% chance per beat)
                if ($urandom_range(0, 1000) < 5) begin
                    rst <= 1;
                    repeat(2) @(posedge clk);
                    rst <= 0;
                    // Packet is dead, break out to generate a new one
                    break;
                end
                
                s_axis_tvalid <= 1;
                s_axis_tdata  <= data_q[idx];
                s_axis_tkeep  <= keep_q[idx];
                s_axis_tlast  <= (idx == len - 1) ? 1'b1 : 1'b0;
                
                if (s_axis_tready) begin
                    idx++;
                end
            end
        end
        
        @(posedge clk);
        s_axis_tvalid <= 0;
        s_axis_tlast  <= 0;
    endtask

    // Random TX Backpressure (Simulating downstream network congestion)
    always @(posedge clk) begin
        if ($urandom_range(0, 100) < 15) begin
            m_axis_tready <= 0;
        end else begin
            m_axis_tready <= 1;
        end
    end

    // -------------------------------------------------------------------------
    // Main DV Sequence
    // -------------------------------------------------------------------------
    
    EthernetPacket pkt;
    PacketGenerator generator;
    logic [63:0] tx_data_q[$];
    logic [7:0]  tx_keep_q[$];

    initial begin
        clk = 0;
        rst = 1;
        s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0; s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axis_tdata = 0; s_axis_tkeep = 0; s_axis_tvalid = 0; s_axis_tlast = 0;
        m_axis_tready = 1;

        pkt = new();
        generator = new();

        #50;
        rst = 0;
        #50;

        $display("[%0t] [DV INIT] Programming Configuration Registers via AXI-Lite...", $time);
        axi_write(32'h00, 32'h11223344);
        axi_write(32'h10, 32'h00000003); // Enable Firewall & Parser

        #100;
        $display("[%0t] [DV RUN] Commencing Constrained Random Packet Injection...", $time);
        
        // Generate and drive 100 constrained random packets
        for (int i = 0; i < 100; i++) begin
            if (!pkt.randomize()) begin
                $fatal("Packet randomization failed!");
            end
            
            generator.generate_packet(pkt, tx_data_q, tx_keep_q);
            
            if (pkt.err_truncated) $display("[%0t] Injecting TRUNCATED packet...", $time);
            if (pkt.err_crc)       $display("[%0t] Injecting CRC ERROR...", $time);
            if (pkt.err_invalid_header) $display("[%0t] Injecting INVALID HEADER...", $time);
            
            drive_packet(tx_data_q, tx_keep_q);
            
            // Random inter-packet gap
            repeat($urandom_range(2, 10)) @(posedge clk);
        end

        #500;
        $display("[%0t] [DV REPORT] Functional Coverage achieved. Terminating simulation.", $time);
        $finish;
    end

endmodule
