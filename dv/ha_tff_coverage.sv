`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - Functional Coverage
// Covergroups for Protocol Types, Corner Cases, and Datapath Decisions

class HA_TFF_Coverage;

    // Data members mapped from RTL interfaces
    logic [7:0]  protocol;
    logic        tuple_valid;
    logic        parse_error;
    logic        match_valid;
    logic        action_forward;
    logic        s_axis_tready;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    
    // Covergroup for Protocols (TCP, UDP, ICMP)
    covergroup cg_protocols;
        option.per_instance = 1;
        
        cp_protocol: coverpoint protocol iff (tuple_valid) {
            bins tcp  = {8'h06};
            bins udp  = {8'h11};
            bins icmp = {8'h01};
            bins other = default;
        }
    endgroup

    // Covergroup for Parser Errors (e.g. truncated or bad ethertype)
    covergroup cg_parser_errors;
        option.per_instance = 1;
        
        cp_error: coverpoint parse_error {
            bins no_error = {0};
            bins error    = {1};
        }
    endgroup

    // Covergroup for Firewall Decisions
    covergroup cg_decisions;
        option.per_instance = 1;
        
        cp_forward: coverpoint action_forward iff (match_valid) {
            bins dropped   = {0};
            bins forwarded = {1};
        }
    endgroup

    // Covergroup for Corner Cases (Backpressure and Small/Large Packets)
    covergroup cg_corner_cases;
        option.per_instance = 1;
        
        cp_backpressure: coverpoint s_axis_tready {
            bins stall = {0};
            bins flow  = {1};
        }
        
        cp_eop: coverpoint s_axis_tlast {
            bins end_of_packet = {1};
        }
        
        cross cp_eop, cp_backpressure; // Ensure backpressure hits during EOP
    endgroup

    function new();
        cg_protocols = new();
        cg_parser_errors = new();
        cg_decisions = new();
        cg_corner_cases = new();
    endfunction
    
    function void sample(
        logic [7:0] p_protocol, logic p_tuple_valid, logic p_parse_error,
        logic p_match_valid, logic p_action_forward, 
        logic p_tready, logic p_tvalid, logic p_tlast
    );
        this.protocol       = p_protocol;
        this.tuple_valid    = p_tuple_valid;
        this.parse_error    = p_parse_error;
        this.match_valid    = p_match_valid;
        this.action_forward = p_action_forward;
        this.s_axis_tready  = p_tready;
        this.s_axis_tvalid  = p_tvalid;
        this.s_axis_tlast   = p_tlast;
        
        cg_protocols.sample();
        cg_parser_errors.sample();
        cg_decisions.sample();
        cg_corner_cases.sample();
    endfunction

endclass
