`timescale 1ns / 1ps

module ha_tff_parser_v002 (
    input  wire        clk,
    input  wire        rst,
    
    // AXI4-Stream Sink Interface (64-bit)
    input  wire [63:0] s_axis_tdata,
    input  wire [7:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    output wire        s_axis_tready,
    
    // Extracted 5-tuple output
    output reg  [31:0] src_ip,
    output reg  [31:0] dst_ip,
    output reg  [15:0] src_port,
    output reg  [15:0] dst_port,
    output reg  [7:0]  protocol,
    output reg         tuple_valid,
    output reg         parse_error
);

    assign s_axis_tready = 1'b1;

    reg [3:0] word_cnt;
    reg       parsing;

    // We assume data arrives MSB-first or network byte order is mapped nicely.
    // For simplicity, we treat s_axis_tdata[63:56] as byte 0 of the word.
    // Word 0 (Bytes 0-7): 
    // Word 1 (Bytes 8-15): [63:48]=SrcMAC[4:5], [47:32]=EtherType, [31:24]=Ver/IHL, [23:16]=TOS
    // Word 2 (Bytes 16-23): [63:48]=Len, [47:32]=ID, [31:16]=Flags/Frag, [15:8]=TTL, [7:0]=Protocol
    // Word 3 (Bytes 24-31): [63:48]=Checksum, [47:16]=Src IP, [15:0]=Dst IP [31:16]
    // Word 4 (Bytes 32-39): [63:48]=Dst IP [15:0], [47:32]=Src Port, [31:16]=Dst Port, [15:0]=UDP Len

    reg [15:0] ethertype;

    always @(posedge clk) begin
        if (rst) begin
            word_cnt    <= 0;
            parsing     <= 0;
            tuple_valid <= 0;
            parse_error <= 0;
            src_ip      <= 0;
            dst_ip      <= 0;
            src_port    <= 0;
            dst_port    <= 0;
            protocol    <= 0;
            ethertype   <= 0;
        end else begin
            tuple_valid <= 0;
            
            if (s_axis_tvalid) begin
                if (!parsing) begin
                    parsing <= 1;
                    word_cnt <= 1; // Word 0 processed this cycle
                end else begin
                    word_cnt <= word_cnt + 1;
                    
                    case (word_cnt)
                        4'd1: begin
                            ethertype <= s_axis_tdata[31:16];
                        end
                        4'd2: begin
                            protocol <= s_axis_tdata[7:0];
                        end
                        4'd3: begin
                            src_ip <= s_axis_tdata[47:16];
                            dst_ip[31:16] <= s_axis_tdata[15:0];
                        end
                        4'd4: begin
                            dst_ip[15:0] <= s_axis_tdata[63:48];
                            src_port <= s_axis_tdata[47:32];
                            dst_port <= s_axis_tdata[31:16];
                            
                            if (ethertype == 16'h0800 && (protocol == 8'h11 || protocol == 8'h06)) begin
                                tuple_valid <= 1;
                            end else begin
                                parse_error <= 1;
                            end
                        end
                    endcase
                end
                
                if (s_axis_tlast) begin
                    parsing <= 0;
                    word_cnt <= 0;
                end
            end
        end
    end

endmodule
