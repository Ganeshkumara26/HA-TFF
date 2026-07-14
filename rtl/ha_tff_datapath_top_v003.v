`timescale 1ns / 1ps

module ha_tff_datapath_top_v003 (
    input  wire        clk,
    input  wire        rst,
    
    // AXI4-Stream Sink Interface (64-bit)
    input  wire [63:0] s_axis_tdata,
    input  wire [7:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    
    // AXI-Lite Configured Secret Key for Hash
    input  wire [127:0] secret_key,
    
    // Final Decision Output
    output wire        match_valid,
    output wire        match_found,
    output wire        action_forward,
    
    // Error Monitoring
    output wire        parse_error
);

    // Wires from Parser
    wire [31:0] src_ip;
    wire [31:0] dst_ip;
    wire [15:0] src_port;
    wire [15:0] dst_port;
    wire [7:0]  protocol;
    wire        tuple_valid;
    
    wire [103:0] parsed_tuple = {src_ip, dst_ip, src_port, dst_port, protocol};

    // Instantiate Parser (v002: 64-bit)
    ha_tff_parser_v002 parser (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .protocol(protocol),
        .tuple_valid(tuple_valid),
        .parse_error(parse_error)
    );
    
    // Wires from Hash
    wire [11:0] h0, h1, h2, h3;
    wire        hash_valid;

    // Instantiate Hash Function (v002) - Secured Parameterized Hash
    ha_tff_hash_v002 hasher (
        .clk(clk),
        .rst(rst),
        .tuple_in(parsed_tuple),
        .valid_in(tuple_valid),
        .secret_key(secret_key),
        .hash_0(h0),
        .hash_1(h1),
        .hash_2(h2),
        .hash_3(h3),
        .valid_out(hash_valid)
    );
    
    // Wires from BRAM Banks
    wire [127:0] b0_data, b1_data, b2_data, b3_data;
    wire         b0_v, b1_v, b2_v, b3_v;

    // Instantiate 4 BRAM Banks
    ha_tff_bram_bank #(.INIT_FILE("../sim/bank0.mem")) bank0 (
        .clk(clk), .rst(rst),
        .read_addr(h0), .read_en(hash_valid),
        .read_data(b0_data), .read_valid(b0_v)
    );
    ha_tff_bram_bank #(.INIT_FILE("../sim/bank1.mem")) bank1 (
        .clk(clk), .rst(rst),
        .read_addr(h1), .read_en(hash_valid),
        .read_data(b1_data), .read_valid(b1_v)
    );
    ha_tff_bram_bank #(.INIT_FILE("../sim/bank2.mem")) bank2 (
        .clk(clk), .rst(rst),
        .read_addr(h2), .read_en(hash_valid),
        .read_data(b2_data), .read_valid(b2_v)
    );
    ha_tff_bram_bank #(.INIT_FILE("../sim/bank3.mem")) bank3 (
        .clk(clk), .rst(rst),
        .read_addr(h3), .read_en(hash_valid),
        .read_data(b3_data), .read_valid(b3_v)
    );

    // Instantiate Pipelined Matcher (v002)
    ha_tff_matcher_v002 matcher (
        .clk(clk),
        .rst(rst),
        .tuple_in(parsed_tuple),
        .valid_in(tuple_valid),
        .b0_data(b0_data),
        .b1_data(b1_data),
        .b2_data(b2_data),
        .b3_data(b3_data),
        .bram_valid(b0_v),
        .match_found(match_found),
        .action_forward(action_forward),
        .match_valid(match_valid)
    );

endmodule
