/*
 * parser_v1_mealy.sv - first SystemVerilog attempt at the packet parser
 *
 * aug 2, 2026
 *
 * ok so i gave up on Migen and im writing SV by hand. i can READ
 * systemverilog pretty well from the rvfpga labs (spent a year staring 
 * at eh1_veer.sv and the decoder files). writing it is... different.
 *
 * this is a Mealy-style FSM where the outputs depend on BOTH the
 * current state AND the inputs. seemed logical at first - i want to
 * start forwarding data as soon as i detect a valid header, not one
 * clock cycle later.
 *
 * THE PROBLEM: Mealy machines have combinational paths from inputs to 
 * outputs. This means:
 *   1. Output glitches during state transitions (combinational hazards)
 *   2. Long combinational paths that hurt timing closure
 *   3. The tvalid_out signal glitches HIGH for one delta-cycle when
 *      transitioning from DROP to IDLE, which causes the downstream
 *      FIFO to latch garbage data
 *
 * My supervisor pointed out that production packet processing hardware
 * almost always uses Moore-style registered outputs to avoid exactly
 * this kind of glitch. The latency cost is ONE clock cycle, which at
 * 100MHz is 10ns. We can afford that.
 *
 * LESSON: Mealy FSMs are a trap for beginners. The "one cycle faster"
 * advantage is not worth the glitch debugging nightmare.
 *
 * STATUS: ABANDONED - replaced by Moore-style FSM in eth_parser.sv
 */

module parser_v1_mealy (
    input  logic        clk,
    input  logic        rst_n,
    
    // AXI-Stream input
    input  logic [7:0]  s_tdata,
    input  logic        s_tvalid,
    output logic        s_tready,
    input  logic        s_tlast,
    
    // AXI-Stream output (filtered)
    output logic [7:0]  m_tdata,
    output logic        m_tvalid,
    input  logic        m_tready,
    output logic        m_tlast,
    
    // status (active high)
    output logic        pkt_valid,      // current packet passed filter
    output logic        pkt_dropped     // current packet was dropped
);

    // FSM states
    typedef enum logic [2:0] {
        S_IDLE      = 3'd0,
        S_ETH_HDR   = 3'd1,
        S_IP_HDR    = 3'd2,
        S_UDP_HDR   = 3'd3,
        S_MAV_CHECK = 3'd4,
        S_FORWARD   = 3'd5,
        S_DROP      = 3'd6
    } state_t;
    
    state_t state, next_state;
    
    logic [15:0] byte_cnt;
    logic [15:0] ethertype;
    logic [7:0]  ip_proto;
    logic [15:0] dst_port;
    
    // --- state register ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    // --- byte counter ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 0;
        end else if (state != next_state) begin
            // reset counter on state transition
            byte_cnt <= 0;
        end else if (s_tvalid && s_tready) begin
            byte_cnt <= byte_cnt + 1;
        end
    end
    
    // --- header field capture ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ethertype <= 0;
            ip_proto  <= 0;
            dst_port  <= 0;
        end else if (s_tvalid && s_tready) begin
            case (state)
                S_ETH_HDR: begin
                    if (byte_cnt == 12) ethertype[15:8] <= s_tdata;
                    if (byte_cnt == 13) ethertype[7:0]  <= s_tdata;
                end
                S_IP_HDR: begin
                    if (byte_cnt == 9) ip_proto <= s_tdata;
                end
                S_UDP_HDR: begin
                    if (byte_cnt == 2) dst_port[15:8] <= s_tdata;
                    if (byte_cnt == 3) dst_port[7:0]  <= s_tdata;
                end
                default: ;
            endcase
        end
    end
    
    // --- next state logic (combinational) ---
    always_comb begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (s_tvalid)
                    next_state = S_ETH_HDR;
            end
            
            S_ETH_HDR: begin
                if (s_tlast && s_tvalid)
                    next_state = S_IDLE;  // runt
                else if (s_tvalid && byte_cnt == 13) begin
                    // BUG: ethertype isnt fully captured yet at this point
                    // because the second byte is being latched on this same
                    // edge. the comparison below uses the OLD value.
                    // this is a classic RTL beginner mistake.
                    if (ethertype == 16'h0800)
                        next_state = S_IP_HDR;
                    else
                        next_state = S_DROP;
                end
            end
            
            S_IP_HDR: begin
                if (s_tlast && s_tvalid)
                    next_state = S_IDLE;
                else if (s_tvalid && byte_cnt == 19) begin
                    if (ip_proto == 8'd17)  // UDP
                        next_state = S_UDP_HDR;
                    else
                        next_state = S_DROP;
                end
            end
            
            S_UDP_HDR: begin
                if (s_tlast && s_tvalid)
                    next_state = S_IDLE;
                else if (s_tvalid && byte_cnt == 7) begin
                    if (dst_port == 16'd14550)
                        next_state = S_MAV_CHECK;
                    else
                        next_state = S_DROP;
                end
            end
            
            S_MAV_CHECK: begin
                if (s_tlast && s_tvalid)
                    next_state = S_IDLE;
                else if (s_tvalid) begin
                    if (s_tdata == 8'hFD)
                        next_state = S_FORWARD;
                    else
                        next_state = S_DROP;
                end
            end
            
            S_FORWARD: begin
                if (s_tlast && s_tvalid && m_tready)
                    next_state = S_IDLE;
            end
            
            S_DROP: begin
                if (s_tlast && s_tvalid)
                    next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end
    
    // --- outputs (Mealy: combinational function of state AND inputs) ---
    // THIS IS THE PROBLEM. these outputs glitch during state transitions.
    // specifically, when transitioning from S_DROP to S_IDLE, there's a
    // brief moment where s_tready goes low, which causes the upstream
    // MAC to think we're backpressuring when we're actually just switching
    // states. this causes byte drops.
    //
    // and m_tvalid glitches high during the S_IDLE->S_FORWARD transition
    // edge, which makes the downstream FIFO capture garbage.
    always_comb begin
        s_tready   = 1'b0;
        m_tdata    = 8'b0;
        m_tvalid   = 1'b0;
        m_tlast    = 1'b0;
        pkt_valid  = 1'b0;
        pkt_dropped = 1'b0;
        
        case (state)
            S_IDLE: begin
                s_tready = 1'b1;  // always ready in idle
            end
            
            S_ETH_HDR, S_IP_HDR, S_UDP_HDR, S_MAV_CHECK: begin
                s_tready = 1'b1;  // consuming headers
            end
            
            S_FORWARD: begin
                // cut-through: forward input directly to output
                s_tready  = m_tready;
                m_tdata   = s_tdata;     // combinational path! glitch risk!
                m_tvalid  = s_tvalid;    // THIS GLITCHES. SEE ABOVE.
                m_tlast   = s_tlast;
                pkt_valid = 1'b1;
            end
            
            S_DROP: begin
                s_tready    = 1'b1;  // consume and discard
                pkt_dropped = 1'b1;
            end
            
            default: ;
        endcase
    end

endmodule

/*
 * POST-MORTEM (aug 5):
 * 
 * the verilator simulation showed the glitch clearly in the VCD trace.
 * m_tvalid goes high for exactly ONE DELTA when transitioning through
 * intermediate combinational evaluations. in real hardware this would
 * be even worse because of propagation delays through the LUTs.
 * 
 * fix: register ALL outputs. use Moore-style FSM where outputs depend
 * only on the current state. costs one clock cycle of latency (10ns at
 * 100MHz) but eliminates all glitches.
 * 
 * also the byte_cnt == 13 check for ethertype has a pipeline hazard:
 * the ethertype register is being updated on the SAME clock edge where
 * we're checking it. the comparison sees the OLD value. need to either:
 *   a) delay the check by one cycle, or
 *   b) compare against the incoming s_tdata directly in the transition logic
 * 
 * went with (b) in the production version (eth_parser.sv).
 * 
 * funny how this is EXACTLY the same pipeline hazard concept from
 * rvfpga lab 15 (data hazards). the register file write and read
 * happen on the same edge, so forwarding is needed. same thing here
 * but with header fields instead of register values. EVERYTHING
 * in hardware comes back to pipeline hazards eventually.
 */
