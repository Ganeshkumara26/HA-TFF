`timescale 1ns / 1ps

// Spike-Based Traffic Filter Firewall (SNN-TFF) Layer v005
// Dynamic Weights: Removes ROM assign statements. Weights are now provided
// via flat input vectors (from an AXI-Lite register file).

module snn_tff_layer_v005 (
    input  wire         clk,
    input  wire         rst,
    
    input  wire [7:0]   in_spikes,
    input  wire         valid_in,
    
    // 16-bit weights flattened (8 * 16 = 128 bits per neuron)
    input  wire [127:0] w0_flat,
    input  wire [127:0] w1_flat,
    
    output wire [1:0]   out_spikes,
    output reg          valid_out
);

    wire signed [15:0] w0 [0:7];
    wire signed [15:0] w1 [0:7];
    
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : weight_unpack
            assign w0[g] = w0_flat[(g*16) +: 16];
            assign w1[g] = w1_flat[(g*16) +: 16];
        end
    endgenerate

    reg signed [15:0] current_n0;
    reg signed [15:0] current_n1;
    
    integer i;
    always @(*) begin
        current_n0 = 0;
        current_n1 = 0;
        for (i = 0; i < 8; i = i + 1) begin
            if (in_spikes[i]) begin
                current_n0 = current_n0 + w0[i];
                current_n1 = current_n1 + w1[i];
            end
        end
    end

    // Cycle 0: in_spikes arrive, combinational sum
    // Cycle 1: register current
    // Cycle 2: Neuron Stage 1 (Arithmetic)
    // Cycle 3: Neuron Stage 2 (Threshold & spike out)

    reg signed [15:0] current_n0_reg;
    reg signed [15:0] current_n1_reg;
    
    reg valid_reg_1;
    reg valid_reg_2;
    reg valid_reg_3;

    always @(posedge clk) begin
        if (rst) begin
            current_n0_reg <= 0;
            current_n1_reg <= 0;
            valid_reg_1    <= 0;
            valid_reg_2    <= 0;
            valid_reg_3    <= 0;
            valid_out      <= 0;
        end else begin
            valid_reg_1 <= valid_in;
            valid_reg_2 <= valid_reg_1;
            valid_reg_3 <= valid_reg_2;
            valid_out   <= valid_reg_3; 
            
            if (valid_in) begin
                current_n0_reg <= current_n0;
                current_n1_reg <= current_n1;
            end else begin
                current_n0_reg <= 0;
                current_n1_reg <= 0;
            end
        end
    end

    // We reuse the v004 pipelined neuron which was previously introduced for timing closure.
    snn_tff_neuron_v004 #(
        .DATA_WIDTH(16),
        .LEAK_SHIFT(3),      
        .THRESHOLD(16'sd1000)  
    ) neuron_safe (
        .clk(clk),
        .rst(rst),
        .syn_current(current_n0_reg),
        .valid_in(valid_reg_1),
        .spike_out(out_spikes[0])
    );

    snn_tff_neuron_v004 #(
        .DATA_WIDTH(16),
        .LEAK_SHIFT(3),
        .THRESHOLD(16'sd1000)
    ) neuron_anomaly (
        .clk(clk),
        .rst(rst),
        .syn_current(current_n1_reg),
        .valid_in(valid_reg_1),
        .spike_out(out_spikes[1])
    );

endmodule
