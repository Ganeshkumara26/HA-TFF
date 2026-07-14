`timescale 1ns / 1ps

// Hardware-Accelerated Telemetry Firewall - SystemVerilog Assertions (SVA)
// Concurrent assertions to formally verify AXI4-Stream compliance and Parser safety.

module ha_tff_sva (
    input wire        clk,
    input wire        rst,
    
    // AXI-Stream Sink
    input wire [63:0] s_axis_tdata,
    input wire [7:0]  s_axis_tkeep,
    input wire        s_axis_tvalid,
    input wire        s_axis_tlast,
    input wire        s_axis_tready,
    
    // AXI-Stream Source
    input wire [63:0] m_axis_tdata,
    input wire [7:0]  m_axis_tkeep,
    input wire        m_axis_tvalid,
    input wire        m_axis_tlast,
    input wire        m_axis_tready,
    
    // Internal Parser State
    input wire        parsing,
    input wire [3:0]  word_cnt,
    input wire        parse_error
);

    // -------------------------------------------------------------------------
    // AXI4-Stream Compliance Assertions
    // -------------------------------------------------------------------------
    
    // 1. Data Stability: If tvalid is high and tready is low, tdata/tkeep/tlast MUST remain stable on the next cycle.
    property p_axis_sink_stable;
        @(posedge clk) disable iff (rst)
        (s_axis_tvalid && !s_axis_tready) |=> 
            (s_axis_tvalid && (s_axis_tdata == $past(s_axis_tdata)) && 
             (s_axis_tkeep == $past(s_axis_tkeep)) && (s_axis_tlast == $past(s_axis_tlast)));
    endproperty
    assert property (p_axis_sink_stable) else $error("SVA ERROR: AXI-Stream Sink violated data stability rule.");

    property p_axis_src_stable;
        @(posedge clk) disable iff (rst)
        (m_axis_tvalid && !m_axis_tready) |=> 
            (m_axis_tvalid && (m_axis_tdata == $past(m_axis_tdata)) && 
             (m_axis_tkeep == $past(m_axis_tkeep)) && (m_axis_tlast == $past(m_axis_tlast)));
    endproperty
    assert property (p_axis_src_stable) else $error("SVA ERROR: AXI-Stream Source violated data stability rule.");

    // 2. Cannot drop tvalid without a handshake.
    property p_axis_sink_valid_no_drop;
        @(posedge clk) disable iff (rst)
        (s_axis_tvalid && !s_axis_tready) |=> s_axis_tvalid;
    endproperty
    assert property (p_axis_sink_valid_no_drop) else $error("SVA ERROR: AXI-Stream Sink dropped tvalid without handshake.");

    // -------------------------------------------------------------------------
    // Parser Safety Assertions
    // -------------------------------------------------------------------------

    // 1. Parser Word Count Constraint: The parser word count should never exceed 4 during parsing of headers.
    // Wait, the packet can be larger than 4 words. The parser just stops capturing after word 4.
    // But word_cnt shouldn't overflow if it's 4-bits. Let's assert word_cnt never goes to 15 (max).
    property p_parser_no_overflow;
        @(posedge clk) disable iff (rst)
        word_cnt < 15;
    endproperty
    assert property (p_parser_no_overflow) else $error("SVA ERROR: Parser word count reached dangerous upper bound.");

    // 2. Parsing state resets on tlast.
    property p_parser_tlast_reset;
        @(posedge clk) disable iff (rst)
        (s_axis_tvalid && s_axis_tready && s_axis_tlast) |=> (!parsing);
    endproperty
    assert property (p_parser_tlast_reset) else $error("SVA ERROR: Parser 'parsing' state did not reset on tlast.");

endmodule
