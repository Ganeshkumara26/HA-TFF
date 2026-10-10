/*
 * mav_filter.sv - MAVLink system ID filter + CRC check
 *
 * receives byte-by-byte MAVLink data from eth_parser, checks the
 * system ID against a configurable allow-list, verifies the CRC,
 * and decides whether to pass or drop the packet.
 *
 * the CRC check is the hardware version of what edp-core's
 * mavlink_parser.c does in software. same CRC-16/MCRF4XX algorithm,
 * same CRC_EXTRA seed per message ID. the difference is that in
 * hardware, we can compute one CRC step per clock cycle using the
 * combinational crc_accumulate function from ha_tff_pkg.sv.
 *
 * the sysid allow-list is loaded by the CPU through the wishbone
 * interface. up to 8 entries. linear scan because 8 entries takes
 * like 3 LUTs and runs at clock speed. dont need a CAM for this.
 *
 * sept 12, 2026
 */

import ha_tff_pkg::*;

module mav_filter (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- from eth_parser ---
    input  logic [7:0]  mav_data,
    input  logic        mav_valid,
    input  logic        mav_last,       // end of frame from MAC
    input  logic        mav_sof,        // start of MAVLink (0xFD seen)
    
    // --- sysid allow-list (from wb_slave) ---
    input  logic [7:0]  allowed_sysid [MAX_SYSIDS],
    input  logic [MAX_SYSIDS-1:0] sysid_valid,  // which entries are active
    input  logic        promisc_mode,   // pass all MAVLink regardless of sysid
    
    // --- to FIFO ---
    output logic [7:0]  filt_data,
    output logic        filt_valid,     // write this byte to FIFO
    output logic        filt_last,      // last byte of filtered packet
    output logic        filt_drop,      // pulse: packet was dropped
    
    // --- decision output ---
    output filter_decision_t decision,
    
    // --- statistics ---
    output logic        stat_mav_ok,    // pulse: valid MAVLink parsed
    output logic        stat_crc_err,   // pulse: CRC mismatch
    output logic        stat_sysid_rej  // pulse: sysid not in allow-list
);

    // --- internal state ---
    typedef enum logic [2:0] {
        MF_IDLE     = 3'd0,
        MF_HDR      = 3'd1,   // parsing MAVLink header (bytes 1-9 after 0xFD)
        MF_PAYLOAD  = 3'd2,   // forwarding payload bytes
        MF_CRC_LO   = 3'd3,   // receiving CRC low byte
        MF_CRC_HI   = 3'd4,   // receiving CRC high byte
        MF_PASS     = 3'd5,   // packet passed
        MF_DROP_PKT = 3'd6    // packet rejected
    } mf_state_t;
    
    mf_state_t mf_state, mf_next;
    
    // header fields captured during MF_HDR
    logic [7:0]  payload_len;
    logic [7:0]  mav_seq;
    logic [7:0]  mav_sysid;
    logic [7:0]  mav_compid;
    logic [23:0] mav_msgid;
    
    // byte counter within current parsing phase
    logic [7:0]  hdr_cnt;
    logic [15:0] pay_cnt;
    
    // CRC accumulator
    logic [15:0] crc_calc;
    logic [15:0] crc_recv;
    
    // sysid match result
    logic sysid_match;
    
    
    // =========================================================
    //  System ID matching
    // =========================================================
    
    // check if mav_sysid is in the allow-list
    // linear scan of 8 entries. at 100MHz this is one LUT layer.
    always_comb begin
        sysid_match = promisc_mode;  // promiscuous passes everything
        
        if (!promisc_mode) begin
            for (int i = 0; i < MAX_SYSIDS; i++) begin
                if (sysid_valid[i] && allowed_sysid[i] == mav_sysid) begin
                    sysid_match = 1'b1;
                end
            end
        end
    end
    
    
    // =========================================================
    //  State Machine
    // =========================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mf_state <= MF_IDLE;
        end else begin
            mf_state <= mf_next;
        end
    end
    
    always_comb begin
        mf_next = mf_state;
        
        case (mf_state)
            MF_IDLE: begin
                if (mav_valid && mav_sof) begin
                    mf_next = MF_HDR;
                end
            end
            
            MF_HDR: begin
                if (mav_last) begin
                    // frame ended during header. truncated.
                    mf_next = MF_IDLE;
                end else if (mav_valid && hdr_cnt == 8'd8) begin
                    // header complete. check sysid.
                    if (sysid_match) begin
                        if (payload_len > 0) begin
                            mf_next = MF_PAYLOAD;
                        end else begin
                            // zero-length payload. unusual but valid.
                            mf_next = MF_CRC_LO;
                        end
                    end else begin
                        mf_next = MF_DROP_PKT;
                    end
                end
            end
            
            MF_PAYLOAD: begin
                if (mav_last) begin
                    // truncated payload
                    mf_next = MF_IDLE;
                end else if (mav_valid && pay_cnt == {8'b0, payload_len} - 1) begin
                    mf_next = MF_CRC_LO;
                end
            end
            
            MF_CRC_LO: begin
                if (mav_last) begin
                    mf_next = MF_IDLE;
                end else if (mav_valid) begin
                    mf_next = MF_CRC_HI;
                end
            end
            
            MF_CRC_HI: begin
                if (mav_valid) begin
                    // CRC check: compare calculated vs received
                    // note: we need to include CRC_EXTRA in our calculation
                    // (this happens in the CRC accumulation logic below)
                    mf_next = MF_PASS;  // tentatively pass, check CRC in output logic
                end else begin
                    mf_next = MF_IDLE;
                end
            end
            
            MF_PASS: begin
                mf_next = MF_IDLE;
            end
            
            MF_DROP_PKT: begin
                // consume remaining frame bytes
                if (mav_last || !mav_valid) begin
                    mf_next = MF_IDLE;
                end
            end
            
            default: mf_next = MF_IDLE;
        endcase
    end
    
    
    // =========================================================
    //  Header Field Capture & CRC
    // =========================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hdr_cnt     <= '0;
            pay_cnt     <= '0;
            payload_len <= '0;
            mav_seq     <= '0;
            mav_sysid   <= '0;
            mav_compid  <= '0;
            mav_msgid   <= '0;
            crc_calc    <= 16'hFFFF;
            crc_recv    <= '0;
        end else begin
            case (mf_state)
                MF_IDLE: begin
                    hdr_cnt  <= '0;
                    pay_cnt  <= '0;
                    crc_calc <= 16'hFFFF;  // CRC init
                    
                    if (mav_valid && mav_sof) begin
                        // 0xFD is NOT included in CRC
                        // (MAVLink CRC covers bytes 1-9 + payload + CRC_EXTRA)
                    end
                end
                
                MF_HDR: begin
                    if (mav_valid) begin
                        hdr_cnt <= hdr_cnt + 1;
                        
                        // accumulate CRC (bytes 1-9)
                        crc_calc <= crc_accumulate(mav_data, crc_calc);
                        
                        case (hdr_cnt)
                            8'd0: payload_len <= mav_data;
                            // 8'd1: incompat flags (skip)
                            // 8'd2: compat flags (skip)
                            8'd3: mav_seq    <= mav_data;
                            8'd4: mav_sysid  <= mav_data;
                            8'd5: mav_compid <= mav_data;
                            8'd6: mav_msgid[7:0]   <= mav_data;
                            8'd7: mav_msgid[15:8]  <= mav_data;
                            8'd8: mav_msgid[23:16] <= mav_data;
                            default: ;
                        endcase
                    end
                end
                
                MF_PAYLOAD: begin
                    if (mav_valid) begin
                        pay_cnt  <= pay_cnt + 1;
                        crc_calc <= crc_accumulate(mav_data, crc_calc);
                    end
                end
                
                MF_CRC_LO: begin
                    if (mav_valid) begin
                        crc_recv[7:0] <= mav_data;
                        
                        // accumulate CRC_EXTRA BEFORE comparing
                        // the CRC_EXTRA is a per-message seed that must be
                        // accumulated into the running CRC AFTER the payload
                        // but BEFORE comparing with the received CRC.
                        // spent 3 hours getting this wrong in edp-core.
                        // at least now i know the correct order.
                        crc_calc <= crc_accumulate(
                            crc_extra(mav_msgid),
                            crc_calc
                        );
                    end
                end
                
                MF_CRC_HI: begin
                    if (mav_valid) begin
                        crc_recv[15:8] <= mav_data;
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    
    // =========================================================
    //  Output Logic
    // =========================================================
    
    // CRC comparison
    logic crc_ok;
    assign crc_ok = (crc_calc == crc_recv);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filt_data    <= '0;
            filt_valid   <= 1'b0;
            filt_last    <= 1'b0;
            filt_drop    <= 1'b0;
            decision     <= DECISION_PENDING;
            stat_mav_ok  <= 1'b0;
            stat_crc_err <= 1'b0;
            stat_sysid_rej <= 1'b0;
        end else begin
            filt_valid   <= 1'b0;
            filt_last    <= 1'b0;
            filt_drop    <= 1'b0;
            stat_mav_ok  <= 1'b0;
            stat_crc_err <= 1'b0;
            stat_sysid_rej <= 1'b0;
            decision     <= DECISION_PENDING;
            
            case (mf_state)
                MF_HDR, MF_PAYLOAD: begin
                    if (mav_valid) begin
                        // forward data to FIFO tentatively
                        // if CRC fails later, the FIFO write pointer
                        // gets rolled back (see telem_fifo.sv)
                        filt_data  <= mav_data;
                        filt_valid <= 1'b1;
                    end
                end
                
                MF_PASS: begin
                    if (crc_ok) begin
                        filt_last   <= 1'b1;  // commit the packet in FIFO
                        decision    <= DECISION_PASS;
                        stat_mav_ok <= 1'b1;
                    end else begin
                        filt_drop    <= 1'b1;  // rollback FIFO write pointer
                        decision     <= DECISION_ERROR;
                        stat_crc_err <= 1'b1;
                    end
                end
                
                MF_DROP_PKT: begin
                    filt_drop      <= 1'b1;
                    decision       <= DECISION_DROP;
                    stat_sysid_rej <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end

endmodule
