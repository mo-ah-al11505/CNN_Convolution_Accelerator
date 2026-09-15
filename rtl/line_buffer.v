`timescale 1ns/1ps

// ------------------------------------------------------------
// line_buffer — single-row delay using a circular buffer
// ------------------------------------------------------------
module line_buffer #(
    parameter IMG_W  = 32,
    parameter DATA_W = 8
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output reg  [DATA_W-1:0] rd_data
);
    // NOTE: DEPTH = IMG_W-1, not IMG_W. rd_data is itself a registered
    // output (1 pipeline stage). A (IMG_W-1)-deep circular buffer plus
    // that 1 output register together give exactly IMG_W cycles of total
    // delay. Using an IMG_W-deep buffer here (as in an earlier revision)
    // gave IMG_W+1 cycles instead - a silent off-by-one that shifts every
    // row above the bottom one by one extra position per line_buffer
    // stage chained (verified by simulation: bottom window row, which
    // bypasses line_buffer entirely, was always correct; the row fed by
    // one line_buffer lagged by 1 cycle; the row fed by two chained
    // line_buffers lagged by 2).
    localparam DEPTH  = IMG_W - 1;
    localparam ADDR_W = $clog2(DEPTH);
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr     <= {ADDR_W{1'b0}};
            rd_data <= {DATA_W{1'b0}};
        end else if (wr_en) begin
            rd_data <= mem[ptr];   // read OLD value first (non-blocking: uses pre-write contents)
            mem[ptr] <= wr_data;
            ptr <= (ptr == DEPTH-1) ? {ADDR_W{1'b0}} : ptr + 1'b1;
        end
    end
endmodule