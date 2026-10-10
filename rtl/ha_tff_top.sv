/*
 * ha_tff_top.sv - top-level integration module
 *
 * wires together: eth_parser -> mav_filter -> telem_fifo -> wb_slave
 *
 * this is the module that gets instantiated in the veerwolf SoC.
 * its address is mapped in wb_intercon.v alongside the other
 * peripherals (UART, SPI, GPIO).
 *
 * the interface is clean: AXI-Stream in (from MAC), Wishbone out 
 * (to CPU bus). everything internal is hidden.
 *
 * i tried to keep this file as simple as possible. just wiring.
 * all the logic is in the submodules. my supervisor said "a good
 * top-level module should be boring. if your top-level is exciting,
 * your architecture is wrong." i think mine is appropriately boring.
 *
 * sept 22, 2026
 */

import ha_tff_pkg::*;

module ha_tff_top (
    input  logic        clk,
    input  logic        rst_n,
    
    // =========================================================
    //  AXI-Stream Input (from Ethernet MAC)
    // =========================================================
    input  logic [7:0]  s_tdata,
    input  logic        s_tvalid,
    output logic        s_tready,
    input  logic        s_tlast,
    
    // =========================================================
    //  Wishbone B4 Slave (to CPU bus)
    // =========================================================
    input  logic [31:0] wb_adr_i,
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,
    input  logic        wb_we_i,
    input  logic [3:0]  wb_sel_i,
    input  logic        wb_stb_i,
    input  logic        wb_cyc_i,
    output logic        wb_ack_o,
    output logic        wb_err_o,
    
    // =========================================================
    //  Interrupt (active high, active when FIFO has data)
    // =========================================================
    output logic        irq
);

    // ==========================================================
    //  Internal Wires
    // ==========================================================
    
    // eth_parser -> mav_filter
    five_tuple_t        tuple;
    logic               tuple_valid;
    logic [7:0]         mav_data;
    logic               mav_valid;
    logic               mav_last;
    logic               mav_sof;
    
    // wb_slave -> filter control
    logic               filt_enable;
    logic               filt_promisc;
    logic               filt_drop_non_ip;
    logic               stat_reset;
    
    // wb_slave -> sysid config
    logic [7:0]         allowed_sysid [MAX_SYSIDS];
    logic [MAX_SYSIDS-1:0] sysid_valid;
    
    // mav_filter -> telem_fifo
    logic [7:0]         filt_data;
    logic               filt_valid;
    logic               filt_last;
    logic               filt_drop;
    filter_decision_t   filt_decision;
    
    // telem_fifo -> wb_slave
    logic [7:0]         fifo_rd_data;
    logic               fifo_empty;
    logic               fifo_full;
    logic [FIFO_ADDR_BITS:0] fifo_level;
    logic               fifo_rd_en;
    
    // statistics wires
    logic               stat_pkt_seen;
    logic               stat_non_ipv4;
    logic               stat_non_udp;
    logic               stat_wrong_port;
    logic               stat_runt;
    logic               stat_mav_ok;
    logic               stat_crc_err;
    logic               stat_sysid_rej;
    
    // aggregated statistics for wb_slave
    logic               stat_any_pass;
    logic               stat_any_drop;
    
    assign stat_any_pass = stat_mav_ok;
    assign stat_any_drop = stat_non_ipv4 | stat_non_udp | stat_wrong_port |
                           stat_runt | stat_sysid_rej;
    
    // interrupt: asserted when FIFO has data for the CPU to read
    assign irq = ~fifo_empty;
    
    
    // ==========================================================
    //  Submodule Instantiation
    // ==========================================================
    
    // --- Ethernet/IP/UDP Parser ---
    eth_parser u_parser (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI-Stream input
        .s_tdata        (s_tdata),
        .s_tvalid       (s_tvalid),
        .s_tready       (s_tready),
        .s_tlast        (s_tlast),
        
        // parsed output
        .tuple          (tuple),
        .tuple_valid    (tuple_valid),
        
        // to MAVLink filter
        .mav_data       (mav_data),
        .mav_valid      (mav_valid),
        .mav_last       (mav_last),
        .mav_sof        (mav_sof),
        
        // control
        .enable         (filt_enable),
        .drop_non_ip    (filt_drop_non_ip),
        
        // statistics
        .stat_pkt_seen  (stat_pkt_seen),
        .stat_non_ipv4  (stat_non_ipv4),
        .stat_non_udp   (stat_non_udp),
        .stat_wrong_port(stat_wrong_port),
        .stat_runt      (stat_runt)
    );
    
    // --- MAVLink System ID Filter ---
    mav_filter u_filter (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // from parser
        .mav_data       (mav_data),
        .mav_valid      (mav_valid),
        .mav_last       (mav_last),
        .mav_sof        (mav_sof),
        
        // sysid config
        .allowed_sysid  (allowed_sysid),
        .sysid_valid    (sysid_valid),
        .promisc_mode   (filt_promisc),
        
        // to FIFO
        .filt_data      (filt_data),
        .filt_valid     (filt_valid),
        .filt_last      (filt_last),
        .filt_drop      (filt_drop),
        .decision       (filt_decision),
        
        // statistics
        .stat_mav_ok    (stat_mav_ok),
        .stat_crc_err   (stat_crc_err),
        .stat_sysid_rej (stat_sysid_rej)
    );
    
    // --- Telemetry FIFO ---
    telem_fifo u_fifo (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // write port
        .wr_data        (filt_data),
        .wr_en          (filt_valid),
        .wr_commit      (filt_last),
        .wr_rollback    (filt_drop),
        
        // read port
        .rd_data        (fifo_rd_data),
        .rd_en          (fifo_rd_en),
        
        // status
        .empty          (fifo_empty),
        .full           (fifo_full),
        .level          (fifo_level)
    );
    
    // --- Wishbone Slave ---
    wb_slave u_wb (
        .wb_clk_i       (clk),
        .wb_rst_i       (~rst_n),  // wishbone uses active-high reset
        
        // wishbone bus
        .wb_adr_i       (wb_adr_i),
        .wb_dat_i       (wb_dat_i),
        .wb_dat_o       (wb_dat_o),
        .wb_we_i        (wb_we_i),
        .wb_sel_i       (wb_sel_i),
        .wb_stb_i       (wb_stb_i),
        .wb_cyc_i       (wb_cyc_i),
        .wb_ack_o       (wb_ack_o),
        .wb_err_o       (wb_err_o),
        
        // control
        .filt_enable    (filt_enable),
        .filt_promisc   (filt_promisc),
        .filt_drop_non_ip(filt_drop_non_ip),
        .stat_reset     (stat_reset),
        
        // sysid config
        .allowed_sysid  (allowed_sysid),
        .sysid_valid    (sysid_valid),
        
        // statistics
        .stat_pkt_seen  (stat_pkt_seen),
        .stat_pkt_pass  (stat_any_pass),
        .stat_pkt_drop  (stat_any_drop),
        .stat_crc_err   (stat_crc_err),
        
        // FIFO
        .fifo_rd_data   (fifo_rd_data),
        .fifo_empty     (fifo_empty),
        .fifo_level     (fifo_level),
        .fifo_rd_en     (fifo_rd_en)
    );

endmodule
