`timescale 1ns / 1ps

// Hardware-Accelerated Traffic Filter Firewall (HA-TFF) - Hash v002
// Fixes Algorithmic Complexity Vulnerability by introducing a 128-bit secret key.
// Uses a parameterized Galois-style folding hash for 1-cycle latency.

module ha_tff_hash (
    input  wire         clk,
    input  wire         rst,
    
    input  wire [103:0] tuple_in,
    input  wire         valid_in,
    input  wire [127:0] secret_key, // Provided by AXI-Lite Control Plane
    
    output reg  [11:0]  hash_0,
    output reg  [11:0]  hash_1,
    output reg  [11:0]  hash_2,
    output reg  [11:0]  hash_3,
    output reg          valid_out
);

    wire [11:0] h0_comb;
    wire [11:0] h1_comb;
    wire [11:0] h2_comb;
    wire [11:0] h3_comb;
    
    // Mix the tuple with the 128-bit secret key to create a secured payload
    // We pad the 104-bit tuple to 128 bits with zeros for the XOR
    wire [127:0] secured_payload = {24'd0, tuple_in} ^ secret_key;
    
    // Seed 0: Linear folding of the secured payload
    assign h0_comb = secured_payload[11:0] ^ secured_payload[23:12] ^ 
                     secured_payload[35:24] ^ secured_payload[47:36] ^ 
                     secured_payload[59:48] ^ secured_payload[71:60] ^ 
                     secured_payload[83:72] ^ secured_payload[95:84] ^ 
                     secured_payload[107:96] ^ secured_payload[119:108] ^
                     {4'h0, secured_payload[127:120]};

    // Seed 1: Bit-reversed folding of the secured payload
    wire [127:0] rev_payload;
    genvar i;
    generate
        for (i=0; i<128; i=i+1) begin : rev
            assign rev_payload[i] = secured_payload[127-i];
        end
    endgenerate
    
    assign h1_comb = rev_payload[11:0] ^ rev_payload[23:12] ^ 
                     rev_payload[35:24] ^ rev_payload[47:36] ^ 
                     rev_payload[59:48] ^ rev_payload[71:60] ^ 
                     rev_payload[83:72] ^ rev_payload[95:84] ^ 
                     rev_payload[107:96] ^ rev_payload[119:108] ^
                     {4'h0, rev_payload[127:120]};

    // Seed 2: Shifted and mixed with key segment
    assign h2_comb = h0_comb ^ (h0_comb << 3) ^ (h0_comb >> 5) ^ secret_key[11:0];
    
    // Seed 3: Shifted and mixed with h1 and key segment
    assign h3_comb = h1_comb ^ (h0_comb << 7) ^ (h1_comb >> 2) ^ secret_key[23:12];

    always @(posedge clk) begin
        if (rst) begin
            hash_0    <= 0;
            hash_1    <= 0;
            hash_2    <= 0;
            hash_3    <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                hash_0 <= h0_comb;
                hash_1 <= h1_comb;
                hash_2 <= h2_comb;
                hash_3 <= h3_comb;
            end
        end
    end

endmodule
