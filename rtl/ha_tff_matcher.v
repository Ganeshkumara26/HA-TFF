`timescale 1ns / 1ps

module ha_tff_matcher (
    input  wire         clk,
    input  wire         rst,
    
    input  wire [103:0] tuple_in,
    input  wire         valid_in,
    
    // BRAM data inputs (from 4 banks)
    input  wire [127:0] b0_data,
    input  wire [127:0] b1_data,
    input  wire [127:0] b2_data,
    input  wire [127:0] b3_data,
    input  wire         bram_valid,
    
    // Outputs
    output reg          match_found,
    output reg          action_forward,
    output reg          match_valid
);

    // Latency matching: Hash (1), BRAM (2). We delay tuple by 3 cycles.
    reg [103:0] tuple_delay [0:2];
    reg         valid_delay [0:2];
    
    // Stage 1 Pipeline Registers (Equality Check)
    reg         s1_b0_match, s1_b1_match, s1_b2_match, s1_b3_match;
    reg         s1_b0_action, s1_b1_action, s1_b2_action, s1_b3_action;
    reg         s1_valid;
    
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i=0; i<3; i=i+1) begin
                tuple_delay[i] <= 0;
                valid_delay[i] <= 0;
            end
            s1_b0_match <= 0; s1_b1_match <= 0; s1_b2_match <= 0; s1_b3_match <= 0;
            s1_b0_action <= 0; s1_b1_action <= 0; s1_b2_action <= 0; s1_b3_action <= 0;
            s1_valid <= 0;
            
            match_found    <= 0;
            action_forward <= 0;
            match_valid    <= 0;
        end else begin
            // Shift Register for Tuple
            tuple_delay[0] <= tuple_in;
            valid_delay[0] <= valid_in;
            tuple_delay[1] <= tuple_delay[0];
            valid_delay[1] <= valid_delay[0];
            tuple_delay[2] <= tuple_delay[1];
            valid_delay[2] <= valid_delay[1];
            
            // ----------------------------------------------------
            // PIPELINE STAGE 1: Equality Checks (104-bit wide)
            // ----------------------------------------------------
            s1_valid <= bram_valid & valid_delay[2];
            
            if (bram_valid && valid_delay[2]) begin
                // Check Bank 0
                s1_b0_match  <= b0_data[127] & (b0_data[103:0] == tuple_delay[2]);
                s1_b0_action <= b0_data[126];
                
                // Check Bank 1
                s1_b1_match  <= b1_data[127] & (b1_data[103:0] == tuple_delay[2]);
                s1_b1_action <= b1_data[126];
                
                // Check Bank 2
                s1_b2_match  <= b2_data[127] & (b2_data[103:0] == tuple_delay[2]);
                s1_b2_action <= b2_data[126];
                
                // Check Bank 3
                s1_b3_match  <= b3_data[127] & (b3_data[103:0] == tuple_delay[2]);
                s1_b3_action <= b3_data[126];
            end else begin
                s1_b0_match <= 0; s1_b1_match <= 0; s1_b2_match <= 0; s1_b3_match <= 0;
            end
            
            // ----------------------------------------------------
            // PIPELINE STAGE 2: Reduction and Output
            // ----------------------------------------------------
            match_valid <= s1_valid;
            if (s1_valid) begin
                match_found <= s1_b0_match | s1_b1_match | s1_b2_match | s1_b3_match;
                
                if (s1_b0_match)      action_forward <= s1_b0_action;
                else if (s1_b1_match) action_forward <= s1_b1_action;
                else if (s1_b2_match) action_forward <= s1_b2_action;
                else if (s1_b3_match) action_forward <= s1_b3_action;
                else                  action_forward <= 0; // Default Drop
            end else begin
                match_found <= 0;
                action_forward <= 0;
            end
        end
    end

endmodule
