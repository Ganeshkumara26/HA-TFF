`timescale 1ns / 1ps

// Simple AXI-Stream Shift Register Delay Line
// Delays tdata, tkeep, tlast, tvalid by LATENCY cycles.

module axi_stream_delay_line #(
    parameter LATENCY = 4,
    parameter DWIDTH  = 64
) (
    input  wire              clk,
    input  wire              rst,
    
    // Sink
    input  wire [DWIDTH-1:0] s_axis_tdata,
    input  wire [7:0]        s_axis_tkeep,
    input  wire              s_axis_tlast,
    input  wire              s_axis_tvalid,
    
    // Source
    output wire [DWIDTH-1:0] m_axis_tdata,
    output wire [7:0]        m_axis_tkeep,
    output wire              m_axis_tlast,
    output wire              m_axis_tvalid
);

    reg [DWIDTH-1:0] tdata_pipe [0:LATENCY-1];
    reg [7:0]        tkeep_pipe [0:LATENCY-1];
    reg              tlast_pipe [0:LATENCY-1];
    reg              tvalid_pipe [0:LATENCY-1];
    
    integer i;
    
    always @(posedge clk) begin
        if (rst) begin
            for (i=0; i<LATENCY; i=i+1) begin
                tdata_pipe[i]  <= 0;
                tkeep_pipe[i]  <= 0;
                tlast_pipe[i]  <= 0;
                tvalid_pipe[i] <= 0;
            end
        end else begin
            tdata_pipe[0]  <= s_axis_tdata;
            tkeep_pipe[0]  <= s_axis_tkeep;
            tlast_pipe[0]  <= s_axis_tlast;
            tvalid_pipe[0] <= s_axis_tvalid;
            
            for (i=1; i<LATENCY; i=i+1) begin
                tdata_pipe[i]  <= tdata_pipe[i-1];
                tkeep_pipe[i]  <= tkeep_pipe[i-1];
                tlast_pipe[i]  <= tlast_pipe[i-1];
                tvalid_pipe[i] <= tvalid_pipe[i-1];
            end
        end
    end
    
    assign m_axis_tdata  = tdata_pipe[LATENCY-1];
    assign m_axis_tkeep  = tkeep_pipe[LATENCY-1];
    assign m_axis_tlast  = tlast_pipe[LATENCY-1];
    assign m_axis_tvalid = tvalid_pipe[LATENCY-1];

endmodule
