`timescale 1ns/1ps

// ------------------------------------------------------------
// kernel_reg_file — runtime-programmable kernel coefficient store
// ------------------------------------------------------------
module kernel_reg_file #(
    parameter NUM_TAPS = 9,
    parameter KERNEL_W = 8
)(
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              kernel_we,
    input  wire [$clog2(NUM_TAPS)-1:0]       kernel_addr,
    input  wire signed [KERNEL_W-1:0]        kernel_data,
    output wire signed [NUM_TAPS*KERNEL_W-1:0] kernel_flat
);
    reg signed [KERNEL_W-1:0] mem [0:NUM_TAPS-1];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1) mem[i] <= {KERNEL_W{1'b0}};
        end else if (kernel_we) begin
            mem[kernel_addr] <= kernel_data;
        end
    end

    genvar g;
    generate
        for (g = 0; g < NUM_TAPS; g = g + 1)
            assign kernel_flat[g*KERNEL_W +: KERNEL_W] = mem[g];
    endgenerate
endmodule
