`timescale 1ns / 1ps

module ha_tff_bram_bank #(
    parameter INIT_FILE = ""
) (
    input  wire         clk,
    input  wire         rst,
    
    // Datapath (Read-Only)
    input  wire [11:0]  read_addr,
    input  wire         read_en,
    output reg  [127:0] read_data,
    output reg          read_valid,
    
    // Control Plane (Write-Only for Rule Updates)
    input  wire [11:0]  write_addr,
    input  wire         write_en,
    input  wire [127:0] write_data
);

    // 4096 entries x 128 bits = 512Kb
    (* ram_style = "block" *) reg [127:0] memory [0:4095];
    
    reg valid_d1;
    
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            read_data  <= 128'h0;
            read_valid <= 0;
            valid_d1   <= 0;
        end else begin
            valid_d1 <= read_en;
            read_valid <= valid_d1; // 2-cycle latency to match typical BRAM
            
            if (write_en) begin
                memory[write_addr] <= write_data;
            end
            
            if (read_en) begin
                read_data <= memory[read_addr];
            end
        end
    end

endmodule
