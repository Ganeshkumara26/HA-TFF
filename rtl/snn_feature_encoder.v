`timescale 1ns / 1ps

// Spike Feature Encoder
// Taps into the AXI-Stream parser output and converts network metadata into an 8-bit spike vector.

module snn_feature_encoder (
    input  wire         clk,
    input  wire         rst,
    
    // Metadata from Parser
    input  wire [31:0]  src_ip,
    input  wire [31:0]  dst_ip,
    input  wire [15:0]  src_port,
    input  wire [15:0]  dst_port,
    input  wire [7:0]   protocol,
    input  wire         meta_valid,
    
    // Output Spikes
    output reg  [7:0]   out_spikes,
    output reg          spike_valid
);

    always @(posedge clk) begin
        if (rst) begin
            out_spikes <= 0;
            spike_valid <= 0;
        end else begin
            spike_valid <= meta_valid;
            
            if (meta_valid) begin
                // Simple feature extraction heuristics for the prototype:
                
                // Spike 0: Is TCP?
                out_spikes[0] <= (protocol == 8'd6) ? 1'b1 : 1'b0;
                
                // Spike 1: Is UDP?
                out_spikes[1] <= (protocol == 8'd17) ? 1'b1 : 1'b0;
                
                // Spike 2: Well-known HTTP/HTTPS port (80 or 443)
                out_spikes[2] <= (dst_port == 16'd80 || dst_port == 16'd443) ? 1'b1 : 1'b0;
                
                // Spike 3: Suspicious high port (source port > 40000)
                out_spikes[3] <= (src_port > 16'd40000) ? 1'b1 : 1'b0;
                
                // Spike 4: Target is broadcast/multicast IP (ends in 255)
                out_spikes[4] <= (dst_ip[7:0] == 8'd255) ? 1'b1 : 1'b0;
                
                // Spike 5: Source is a known bad subnet (e.g. 192.168.100.x)
                out_spikes[5] <= (src_ip[31:8] == 24'hC0A864) ? 1'b1 : 1'b0;
                
                // Spike 6: Traffic matching common DNS port
                out_spikes[6] <= (dst_port == 16'd53) ? 1'b1 : 1'b0;
                
                // Spike 7: Default random feature (source port is even)
                out_spikes[7] <= (src_port[0] == 1'b0) ? 1'b1 : 1'b0;
            end else begin
                out_spikes <= 0;
            end
        end
    end

endmodule
