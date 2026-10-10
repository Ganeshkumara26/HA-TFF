/*
 * wb_bridge_naive.sv - first wishbone slave attempt
 *
 * aug 12, 2026
 *
 * trying to connect my filter to the veerwolf SoC's wishbone bus
 * so the RISC-V CPU can read filtered telemetry and filter stats.
 *
 * i learned how the wishbone bus works from rvfpga-soc lab 3 where
 * we mapped a custom peripheral to wb_intercon.v. the addressing
 * scheme uses the upper address bits for slave select and the lower
 * bits for register offset. each slave gets a slice of the address
 * space.
 *
 * THE PROBLEM: my first wishbone slave implementation didnt handle
 * the pipeline stall correctly. in wishbone B4 pipelined mode, the
 * master can send a new request before the previous ACK comes back.
 * my slave assumed one-request-at-a-time (classic mode) and when the
 * VeeR core sent a burst read, the first byte got dropped because
 * my ACK was one cycle late.
 *
 * the infamous "2-cycle NOP" bug: i added a 2-cycle delay as a hack
 * to work around the timing, but it just masked the real problem.
 * the real fix was to properly implement the ACK pipeline.
 *
 * STATUS: REPLACED by wb_slave.sv
 */

module wb_bridge_naive #(
    parameter BASE_ADDR = 32'h80002000  // in veerwolf address space
)(
    input  logic        wb_clk_i,
    input  logic        wb_rst_i,
    
    // wishbone slave interface
    input  logic [31:0] wb_adr_i,
    input  logic [31:0] wb_dat_i,
    output logic [31:0] wb_dat_o,
    input  logic        wb_we_i,
    input  logic [3:0]  wb_sel_i,
    input  logic        wb_stb_i,
    input  logic        wb_cyc_i,
    output logic        wb_ack_o,
    output logic        wb_err_o,
    
    // filter status inputs
    input  logic [31:0] pkts_seen,
    input  logic [31:0] pkts_passed,
    input  logic [31:0] pkts_dropped,
    input  logic [31:0] crc_errors,
    
    // fifo read port
    input  logic [31:0] fifo_data,
    input  logic        fifo_empty,
    output logic        fifo_rd_en
);

    // register map:
    //   offset 0x00: CTRL     (R/W) - filter enable, reset stats
    //   offset 0x04: STATUS   (R)   - fifo status, filter state
    //   offset 0x08: PKT_SEEN (R)   - total packets seen
    //   offset 0x0C: PKT_PASS (R)   - packets passed filter
    //   offset 0x10: PKT_DROP (R)   - packets dropped
    //   offset 0x14: CRC_ERR  (R)   - CRC errors
    //   offset 0x18: FIFO_RD  (R)   - read one word from FIFO
    
    logic [31:0] ctrl_reg;
    logic valid_access;
    logic [7:0] reg_offset;
    
    assign valid_access = wb_cyc_i & wb_stb_i;
    assign reg_offset   = wb_adr_i[7:0];
    assign wb_err_o     = 1'b0;  // we never error. probably should.
    
    // --- ACK generation ---
    // BUG: this is the broken version. ACK comes one cycle after
    // strobe, which is correct for classic mode but wrong for
    // pipelined mode where ACK should come on the same cycle
    // as the data (or at least, the slave shouldnt drop transactions
    // while waiting to ACK).
    //
    // the VeeR core's LSU uses pipelined wishbone, and when it does
    // a burst read (like reading multiple status registers), it sends
    // STB on consecutive cycles. my delayed ACK causes the second
    // read to be lost because i'm still ACKing the first one.
    
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o <= 1'b0;
        end else begin
            // one-cycle delayed ACK. WRONG for pipelined mode.
            wb_ack_o <= valid_access & ~wb_ack_o;
        end
    end
    
    // --- read mux ---
    always_comb begin
        wb_dat_o = 32'h0;
        fifo_rd_en = 1'b0;
        
        if (valid_access && !wb_we_i) begin
            case (reg_offset)
                8'h00: wb_dat_o = ctrl_reg;
                8'h04: wb_dat_o = {30'b0, fifo_empty, ctrl_reg[0]};
                8'h08: wb_dat_o = pkts_seen;
                8'h0C: wb_dat_o = pkts_passed;
                8'h10: wb_dat_o = pkts_dropped;
                8'h14: wb_dat_o = crc_errors;
                8'h18: begin
                    wb_dat_o = fifo_data;
                    fifo_rd_en = ~fifo_empty;
                    // BUG: fifo_rd_en is combinational here, which means
                    // it pulses on every cycle that the CPU is reading
                    // this register. if the CPU reads take >1 cycle (which
                    // they do because of the ACK delay), we pop MULTIPLE
                    // entries from the FIFO when we should pop just one.
                    //
                    // fix: make fifo_rd_en edge-detected (only pulse on
                    // the first cycle of the read). done in wb_slave.sv.
                end
                default: wb_dat_o = 32'hDEADBEEF;
            endcase
        end
    end
    
    // --- write logic ---
    always_ff @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            ctrl_reg <= 32'h0;
        end else if (valid_access && wb_we_i && wb_ack_o) begin
            case (reg_offset)
                8'h00: ctrl_reg <= wb_dat_i;
                default: ; // ignore writes to read-only registers
            endcase
        end
    end

endmodule

/*
 * debugging notes (aug 14):
 * 
 * connected this to a simple verilator testbench that simulates
 * wishbone reads. single reads work fine. burst reads drop data.
 * 
 * the VCD trace shows the problem clearly:
 *   cycle 1: master asserts STB for register 0x08
 *   cycle 2: slave ACKs register 0x08, data is valid
 *             BUT master already asserted STB for register 0x0C
 *   cycle 3: slave sees STB for 0x0C but is still deasserting ACK
 *             from the previous transaction. the 0x0C read is LOST.
 * 
 * the fix is to ACK on the same cycle as the data output (combinational
 * ACK), OR to implement proper pipelined ACK where we can handle
 * back-to-back transactions. going with the latter.
 * 
 * also the FIFO read pop bug: i need to track the rising edge of
 * the access to the FIFO register and only pop once per read.
 * 
 * these bugs are exactly why my supervisor said "get the bus right
 * first, then worry about the filter logic." he was right. again.
 */
