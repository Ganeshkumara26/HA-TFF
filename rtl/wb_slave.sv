/*
 * wb_slave.sv - Wishbone B4 pipelined slave interface
 *
 * connects the HA-TFF filter to the VeeRwolf SoC's Wishbone bus.
 * provides memory-mapped registers for filter control, statistics,
 * sysid configuration, and FIFO readout.
 *
 * this is the FIXED version of wb_bridge_naive.sv. key differences:
 *   1. proper pipelined ACK (handles back-to-back transactions)
 *   2. FIFO read is edge-detected (only pops once per read access)
 *   3. statistics counters are properly synchronized
 *
 * the register map is documented in docs/register_map.md
 *
 * i learned the wishbone B4 spec by reading the veerwolf source code
 * (specifically wb_intercon.v and the SweRV_EH1 LSU) during the
 * rvfpga-soc labs. the key insight is that the VeeR LSU generates
 * pipelined reads where STB can assert on consecutive cycles. our
 * slave must be able to ACK on the same cycle as the data output
 * (combinational ACK path) to avoid dropping transactions.
 *
 * the register address decode uses the lower 8 bits of the address
 * bus. the upper bits are decoded by wb_intercon.v for slave select.
 * in veerwolf, peripheral address space starts at 0x80000000 and
 * each peripheral gets a 256-byte window.
 *
 * sept 18, 2026
 */

import ha_tff_pkg::*;

module wb_slave (
    input  logic        wb_clk_i,
    input  logic        wb_rst_i,
    
    // --- Wishbone B4 slave interface ---
    input  logic [31:0] wb_adr_i,
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,
    input  logic        wb_we_i,
    input  logic [3:0]  wb_sel_i,
    input  logic        wb_stb_i,
    input  logic        wb_cyc_i,
    output logic        wb_ack_o,
    output logic        wb_err_o,
    
    // --- filter control outputs ---
    output logic        filt_enable,
    output logic        filt_promisc,
    output logic        filt_drop_non_ip,
    output logic        stat_reset,       // pulse: reset statistics
    
    // --- sysid allow-list ---
    output logic [7:0]  allowed_sysid [MAX_SYSIDS],
    output logic [MAX_SYSIDS-1:0] sysid_valid,
    
    // --- statistics inputs (active-high pulses) ---
    input  logic        stat_pkt_seen,
    input  logic        stat_pkt_pass,
    input  logic        stat_pkt_drop,
    input  logic        stat_crc_err,
    
    // --- FIFO interface ---
    input  logic [7:0]  fifo_rd_data,
    input  logic        fifo_empty,
    input  logic [FIFO_ADDR_BITS:0] fifo_level,
    output logic        fifo_rd_en
);

    // --- wishbone access decode ---
    logic valid_access;
    logic [7:0] reg_addr;
    
    assign valid_access = wb_cyc_i & wb_stb_i;
    assign reg_addr     = wb_adr_i[7:0];
    assign wb_err_o     = 1'b0;  // no error conditions implemented
    
    // --- ACK generation ---
    // Combinational ACK for pipelined mode.
    // ACK asserts in the same cycle as valid_access.
    // This handles back-to-back reads correctly (unlike wb_bridge_naive.sv).
    //
    // Note: this creates a combinational path from STB to ACK which
    // vivado might complain about for timing. if it becomes a problem,
    // we can add a registered ACK with a 1-cycle latency. but at 100MHz
    // on the nexys a7 this should be fine.
    assign wb_ack_o = valid_access;
    
    
    // --- control register ---
    logic [31:0] ctrl_reg;
    
    assign filt_enable     = ctrl_reg[CTRL_ENABLE];
    assign filt_promisc    = ctrl_reg[CTRL_PROMISC];
    assign filt_drop_non_ip = ctrl_reg[CTRL_DROP_NON_IP];
    
    
    // --- statistics counters ---
    logic [31:0] cnt_pkt_total;
    logic [31:0] cnt_pkt_pass;
    logic [31:0] cnt_pkt_drop;
    logic [31:0] cnt_crc_err;
    
    // auto-clear the reset bit after one cycle
    logic stat_reset_pending;
    assign stat_reset = stat_reset_pending;
    
    
    // --- FIFO read edge detection ---
    // only pop once per read access to the FIFO_DATA register.
    // detect rising edge of (valid_access && reading FIFO_DATA).
    logic fifo_read_prev;
    logic fifo_read_now;
    
    assign fifo_read_now = valid_access && !wb_we_i && (reg_addr == REG_FIFO_DATA);
    
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i)
            fifo_read_prev <= 1'b0;
        else
            fifo_read_prev <= fifo_read_now;
    end
    
    // rising edge = new read transaction
    assign fifo_rd_en = fifo_read_now && !fifo_read_prev && !fifo_empty;
    
    
    // --- sysid registers ---
    // one register per allowed sysid. writing a non-zero value enables
    // the entry, writing 0 disables it.
    
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            for (int i = 0; i < MAX_SYSIDS; i++) begin
                allowed_sysid[i] <= '0;
                sysid_valid[i]   <= 1'b0;
            end
        end else if (valid_access && wb_we_i) begin
            case (reg_addr)
                REG_SYSID_0: begin allowed_sysid[0] <= wb_dat_i[7:0]; sysid_valid[0] <= |wb_dat_i[7:0]; end
                REG_SYSID_1: begin allowed_sysid[1] <= wb_dat_i[7:0]; sysid_valid[1] <= |wb_dat_i[7:0]; end
                REG_SYSID_2: begin allowed_sysid[2] <= wb_dat_i[7:0]; sysid_valid[2] <= |wb_dat_i[7:0]; end
                REG_SYSID_3: begin allowed_sysid[3] <= wb_dat_i[7:0]; sysid_valid[3] <= |wb_dat_i[7:0]; end
                REG_SYSID_4: begin allowed_sysid[4] <= wb_dat_i[7:0]; sysid_valid[4] <= |wb_dat_i[7:0]; end
                REG_SYSID_5: begin allowed_sysid[5] <= wb_dat_i[7:0]; sysid_valid[5] <= |wb_dat_i[7:0]; end
                REG_SYSID_6: begin allowed_sysid[6] <= wb_dat_i[7:0]; sysid_valid[6] <= |wb_dat_i[7:0]; end
                REG_SYSID_7: begin allowed_sysid[7] <= wb_dat_i[7:0]; sysid_valid[7] <= |wb_dat_i[7:0]; end
                default: ;
            endcase
        end
    end
    
    
    // --- control register write ---
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ctrl_reg          <= 32'h0;
            stat_reset_pending <= 1'b0;
        end else begin
            stat_reset_pending <= 1'b0;  // auto-clear
            
            if (valid_access && wb_we_i && reg_addr == REG_CTRL) begin
                ctrl_reg <= wb_dat_i;
                
                // if reset-stats bit is written, pulse stat_reset
                if (wb_dat_i[CTRL_RST_STATS]) begin
                    stat_reset_pending <= 1'b1;
                    // auto-clear the bit in the register
                    ctrl_reg[CTRL_RST_STATS] <= 1'b0;
                end
            end
        end
    end
    
    
    // --- statistics counters ---
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i || stat_reset) begin
            cnt_pkt_total <= '0;
            cnt_pkt_pass  <= '0;
            cnt_pkt_drop  <= '0;
            cnt_crc_err   <= '0;
        end else begin
            if (stat_pkt_seen) cnt_pkt_total <= cnt_pkt_total + 1;
            if (stat_pkt_pass) cnt_pkt_pass  <= cnt_pkt_pass + 1;
            if (stat_pkt_drop) cnt_pkt_drop  <= cnt_pkt_drop + 1;
            if (stat_crc_err)  cnt_crc_err   <= cnt_crc_err + 1;
        end
    end
    
    
    // --- read mux ---
    always_comb begin
        wb_dat_o = 32'hDEADBEEF;  // default for unimplemented registers
        
        if (valid_access && !wb_we_i) begin
            case (reg_addr)
                REG_CTRL:       wb_dat_o = ctrl_reg;
                REG_STATUS:     wb_dat_o = {24'b0, 
                                            mf_state_debug,     // [7:4] FSM state
                                            1'b0,               // [3] reserved
                                            1'b0,               // [2] FSM active
                                            fifo_full_r,        // [1] FIFO full
                                            fifo_empty};        // [0] FIFO empty
                REG_PKT_TOTAL:  wb_dat_o = cnt_pkt_total;
                REG_PKT_PASS:   wb_dat_o = cnt_pkt_pass;
                REG_PKT_DROP:   wb_dat_o = cnt_pkt_drop;
                REG_CRC_ERR:    wb_dat_o = cnt_crc_err;
                REG_FIFO_DATA:  wb_dat_o = {24'b0, fifo_rd_data};
                REG_FIFO_LEVEL: wb_dat_o = {24'b0, fifo_level};
                REG_SYSID_0:   wb_dat_o = {24'b0, allowed_sysid[0]};
                REG_SYSID_1:   wb_dat_o = {24'b0, allowed_sysid[1]};
                REG_SYSID_2:   wb_dat_o = {24'b0, allowed_sysid[2]};
                REG_SYSID_3:   wb_dat_o = {24'b0, allowed_sysid[3]};
                REG_SYSID_4:   wb_dat_o = {24'b0, allowed_sysid[4]};
                REG_SYSID_5:   wb_dat_o = {24'b0, allowed_sysid[5]};
                REG_SYSID_6:   wb_dat_o = {24'b0, allowed_sysid[6]};
                REG_SYSID_7:   wb_dat_o = {24'b0, allowed_sysid[7]};
                default:       wb_dat_o = 32'hDEADBEEF;
            endcase
        end
    end
    
    // debug signals (directly from status reg, not critical)
    // these dont need to be perfectly clean
    logic [3:0] mf_state_debug;
    logic fifo_full_r;
    assign mf_state_debug = 4'b0;  // TODO: connect to actual FSM state
    assign fifo_full_r = ~fifo_empty & (fifo_level >= FIFO_DEPTH - 1);

endmodule
