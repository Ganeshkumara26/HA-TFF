/*
 * telem_fifo.sv - synchronous FIFO for CPU telemetry readout
 *
 * small BRAM-based FIFO that buffers filtered MAVLink bytes for
 * the CPU to read through the wishbone interface.
 *
 * key feature: tentative write with rollback. during packet parsing,
 * bytes are written speculatively. if the packet fails CRC, the
 * write pointer is rolled back to where it was before the packet
 * started. if it passes, the write pointer is "committed."
 *
 * this is similar to the "store-and-forward" vs "cut-through" tradeoff
 * in network switches. we're kind of doing both: we write cut-through
 * (one byte at a time as it arrives) but can undo the write if the
 * CRC fails. best of both worlds at the cost of a saved write pointer.
 *
 * the fifo is synchronous (single clock domain) because both the
 * ethernet MAC and the wishbone bus run off the same 100MHz system
 * clock in the veerwolf SoC. if we needed clock domain crossing,
 * this would be an async FIFO with gray code pointers. but we dont.
 * thankfully. async FIFOs are a pain.
 *
 * sept 15, 2026
 */

import ha_tff_pkg::*;

module telem_fifo (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- write port (from mav_filter) ---
    input  logic [7:0]  wr_data,
    input  logic        wr_en,
    input  logic        wr_commit,   // commit current packet (CRC passed)
    input  logic        wr_rollback, // rollback current packet (CRC failed or sysid rejected)
    
    // --- read port (to wb_slave) ---
    output logic [7:0]  rd_data,
    input  logic        rd_en,
    
    // --- status ---
    output logic        empty,
    output logic        full,
    output logic [FIFO_ADDR_BITS:0] level  // number of valid entries
);

    // --- storage ---
    logic [7:0] mem [FIFO_DEPTH];
    
    // --- pointers ---
    // wr_ptr:       current write position (speculative)
    // wr_committed: last committed write position
    // rd_ptr:       current read position
    //
    // the distinction between wr_ptr and wr_committed is what enables
    // the rollback feature. wr_ptr advances with each byte written.
    // wr_committed only advances when commit asserts. if rollback
    // asserts instead, wr_ptr snaps back to wr_committed.
    
    logic [FIFO_ADDR_BITS:0] wr_ptr;
    logic [FIFO_ADDR_BITS:0] wr_committed;
    logic [FIFO_ADDR_BITS:0] rd_ptr;
    
    // --- derived signals ---
    logic [FIFO_ADDR_BITS-1:0] wr_addr;
    logic [FIFO_ADDR_BITS-1:0] rd_addr;
    
    assign wr_addr = wr_ptr[FIFO_ADDR_BITS-1:0];
    assign rd_addr = rd_ptr[FIFO_ADDR_BITS-1:0];
    
    // full/empty based on COMMITTED pointer vs read pointer
    // (not speculative wr_ptr, because uncommitted data shouldnt
    // be visible to the reader)
    assign empty = (wr_committed == rd_ptr);
    assign full  = (wr_ptr[FIFO_ADDR_BITS] != rd_ptr[FIFO_ADDR_BITS]) &&
                   (wr_ptr[FIFO_ADDR_BITS-1:0] == rd_ptr[FIFO_ADDR_BITS-1:0]);
    assign level = wr_committed - rd_ptr;
    
    
    // --- write logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr       <= '0;
            wr_committed <= '0;
        end else begin
            if (wr_rollback) begin
                // snap back to last committed position
                wr_ptr <= wr_committed;
            end else begin
                if (wr_en && !full) begin
                    mem[wr_addr] <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                end
                
                if (wr_commit) begin
                    // advance the committed pointer to current write position
                    // (or wr_ptr + 1 if we're also writing on this cycle)
                    if (wr_en && !full)
                        wr_committed <= wr_ptr + 1;
                    else
                        wr_committed <= wr_ptr;
                end
            end
        end
    end
    
    
    // --- read logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr  <= '0;
            rd_data <= '0;
        end else begin
            if (rd_en && !empty) begin
                rd_data <= mem[rd_addr];
                rd_ptr  <= rd_ptr + 1;
            end
        end
    end

endmodule
