/*
 * fsm_onehot_broken.sv - one-hot encoding experiment
 *
 * aug 8, 2026
 *
 * read somewhere that one-hot encoding is better for FPGAs because
 * each state is a single flip-flop, and the next-state logic becomes
 * simpler (just AND/OR gates instead of a decoder). vivado apparently
 * prefers one-hot for small FSMs.
 *
 * tried to manually encode my FSM as one-hot. it went badly.
 *
 * THE PROBLEM: i used `(* fsm_encoding = "one_hot" *)` attribute
 * thinking vivado would handle the encoding. but then i ALSO manually
 * defined my states as one-hot values (8'b00000001, 8'b00000010, etc.)
 * AND used explicit equality checks (state == S_ETH_HDR). vivado got
 * confused by the conflicting encoding hints and inferred a priority
 * encoder instead of proper one-hot transitions.
 *
 * the result: state transitions were WRONG. the FSM would sometimes
 * jump from ETH_HDR directly to FORWARD, skipping IP and UDP parsing
 * entirely. every packet was being accepted regardless of content.
 *
 * my supervisor's response: "just let vivado choose the encoding.
 * use an enum, let the tool do its job. you're fighting the toolchain."
 *
 * he was right. went back to enum-based states and let vivado's
 * synthesis optimizer pick the encoding. it chose one-hot anyway,
 * but correctly this time.
 *
 * LESSON: dont fight the synthesis tool. declare intent with enums,
 * let the optimizer figure out the encoding. this is basically the
 * "dont outsmart the compiler" lesson but for hardware.
 *
 * STATUS: ABANDONED
 */

module fsm_onehot_broken (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] s_tdata,
    input  logic       s_tvalid,
    output logic       s_tready,
    input  logic       s_tlast,
    output logic       accept,
    output logic       drop
);

    // one-hot state encoding - MANUALLY. this is the mistake.
    // vivado's (* fsm_encoding *) attribute conflicts with this.
    localparam logic [7:0] S_IDLE      = 8'b00000001;
    localparam logic [7:0] S_ETH_HDR   = 8'b00000010;
    localparam logic [7:0] S_IP_HDR    = 8'b00000100;
    localparam logic [7:0] S_UDP_HDR   = 8'b00001000;
    localparam logic [7:0] S_MAV_CHECK = 8'b00010000;
    localparam logic [7:0] S_FORWARD   = 8'b00100000;
    localparam logic [7:0] S_DROP      = 8'b01000000;
    localparam logic [7:0] S_CRC       = 8'b10000000;

    (* fsm_encoding = "one_hot" *)  // conflicts with manual encoding above!
    logic [7:0] state;

    logic [15:0] byte_cnt;
    logic [15:0] ethertype_reg;
    logic [7:0]  proto_reg;
    logic [15:0] port_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            byte_cnt <= 0;
            ethertype_reg <= 0;
            proto_reg <= 0;
            port_reg <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (s_tvalid) begin
                        state <= S_ETH_HDR;
                        byte_cnt <= 0;
                    end
                end
                
                S_ETH_HDR: begin
                    if (s_tvalid) begin
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 16'd12) ethertype_reg[15:8] <= s_tdata;
                        if (byte_cnt == 16'd13) begin
                            ethertype_reg[7:0] <= s_tdata;
                            // BUG: checking ethertype_reg here but byte 13
                            // hasnt been latched yet (same-cycle hazard again)
                            if (ethertype_reg[15:8] == 8'h08 && s_tdata == 8'h00)
                                state <= S_IP_HDR;
                            else
                                state <= S_DROP;
                            byte_cnt <= 0;
                        end
                    end
                    if (s_tlast) state <= S_IDLE;
                end
                
                S_IP_HDR: begin
                    if (s_tvalid) begin
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 16'd9) proto_reg <= s_tdata;
                        if (byte_cnt == 16'd19) begin
                            // BUG: same hazard. proto_reg not yet valid.
                            // using s_tdata directly here is WRONG because
                            // byte 19 is NOT the protocol byte, byte 9 is.
                            // but proto_reg WAS set on byte 9. however since
                            // we're in a case block inside always_ff, the
                            // NBA (non-blocking assignment) from byte 9
                            // IS visible here because its a different clock
                            // cycle. so this actually works... i think?
                            // honestly im not sure anymore.
                            if (proto_reg == 8'd17)
                                state <= S_UDP_HDR;
                            else
                                state <= S_DROP;
                            byte_cnt <= 0;
                        end
                    end
                    if (s_tlast) state <= S_IDLE;
                end
                
                S_UDP_HDR: begin
                    if (s_tvalid) begin
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 16'd2) port_reg[15:8] <= s_tdata;
                        if (byte_cnt == 16'd3) port_reg[7:0] <= s_tdata;
                        if (byte_cnt == 16'd7) begin
                            // dst_port check
                            if (port_reg == 16'd14550)
                                state <= S_MAV_CHECK;
                            else
                                state <= S_DROP;
                            byte_cnt <= 0;
                        end
                    end
                    if (s_tlast) state <= S_IDLE;
                end
                
                S_MAV_CHECK: begin
                    if (s_tvalid) begin
                        if (s_tdata == 8'hFD)
                            state <= S_FORWARD;
                        else
                            state <= S_DROP;
                    end
                    if (s_tlast) state <= S_IDLE;
                end
                
                S_FORWARD: begin
                    if (s_tlast && s_tvalid)
                        state <= S_IDLE;
                end
                
                S_DROP: begin
                    if (s_tlast && s_tvalid)
                        state <= S_IDLE;
                end
                
                // if we end up in an undefined state (which happened
                // because of the encoding conflict), go back to idle.
                // this shouldnt happen but it DID. twice.
                default: state <= S_IDLE;
            endcase
        end
    end
    
    // outputs - at least these are registered (Moore-style)
    // learned that lesson from parser_v1_mealy.sv
    assign s_tready = (state != S_IDLE);  // hmm this might be wrong
    assign accept   = (state == S_FORWARD);
    assign drop     = (state == S_DROP);

endmodule

/*
 * vivado synthesis log excerpt:
 *
 * WARNING: [Synth 8-327] inferring latch for variable 'state'
 * WARNING: [Synth 8-3886] unable to determine FSM encoding for state
 *          register 'state_reg'. Defaulting to auto encoding.
 * 
 * that "unable to determine FSM encoding" warning is vivado saying
 * "i see your manual one-hot AND your attribute and they conflict,
 * so im going to do my own thing." its own thing was wrong.
 *
 * also the "inferring latch" warning means my always_ff block has
 * an incomplete assignment somewhere. probably the default case
 * or a missing else branch. need to be more careful with that.
 *
 * ABANDONED. using enum in production code.
 */
