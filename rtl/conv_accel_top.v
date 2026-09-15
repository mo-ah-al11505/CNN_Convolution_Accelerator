`timescale 1ns/1ps

module conv_accel_top #(
    parameter IMG_W       = 32,
    parameter IMG_H       = 32,
    parameter N           = 3,
    parameter PIXEL_W     = 8,
    parameter KERNEL_W    = 8,
    parameter FRAC_BITS   = 0,
    parameter OUT_W       = 16,
    parameter ENABLE_RELU = 0,
    parameter NUM_TAPS    = N*N,
    parameter PROD_W      = PIXEL_W + KERNEL_W,
    parameter SUM_W       = PROD_W + $clog2(NUM_TAPS)
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire [PIXEL_W-1:0]          pixel_in,
    input  wire                        pixel_valid,
    input  wire                        kernel_we,
    input  wire [$clog2(NUM_TAPS)-1:0] kernel_addr,
    input  wire signed [KERNEL_W-1:0]  kernel_data,
    output wire signed [OUT_W-1:0]     pixel_out,
    output wire                        pixel_out_valid,
    output wire                        frame_done
);
    localparam LEVELS = $clog2(NUM_TAPS);
    localparam TOTAL_LATENCY = LEVELS + 2;  // 1 (mult) + LEVELS (tree) + 1 (round/relu)

    // ---- Kernel storage ----
    wire signed [NUM_TAPS*KERNEL_W-1:0] kernel_flat;
    kernel_reg_file #(.NUM_TAPS(NUM_TAPS), .KERNEL_W(KERNEL_W)) u_kreg (
        .clk(clk), .rst_n(rst_n), .kernel_we(kernel_we),
        .kernel_addr(kernel_addr), .kernel_data(kernel_data),
        .kernel_flat(kernel_flat)
    );

    // ---- Windowing (line buffers + shift register) ----
    wire [NUM_TAPS*PIXEL_W-1:0] window_flat;
    wire window_valid;
    wire frame_end_raw;
    window_generator #(.IMG_W(IMG_W), .IMG_H(IMG_H), .N(N), .PIXEL_W(PIXEL_W)) u_wg (
        .clk(clk), .rst_n(rst_n), .pixel_valid(pixel_valid), .pixel_in(pixel_in),
        .window_flat(window_flat), .window_valid(window_valid), .frame_end(frame_end_raw)
    );

    // ---- Pipelined MAC tree ----
    wire signed [SUM_W-1:0] mac_sum;
    wire mac_valid;
    conv_mac_tree #(
        .PIXEL_W(PIXEL_W), .KERNEL_W(KERNEL_W), .NUM_TAPS(NUM_TAPS),
        .PROD_W(PROD_W), .SUM_W(SUM_W)
    ) u_mac (
        .clk(clk), .rst_n(rst_n), .valid_in(window_valid),
        .win_in(window_flat), .kernel_in(kernel_flat),
        .sum_out(mac_sum), .valid_out(mac_valid)
    );

    // ---- Output conditioning ----
    round_saturate_relu #(
        .SUM_W(SUM_W), .FRAC_BITS(FRAC_BITS), .OUT_W(OUT_W), .ENABLE_RELU(ENABLE_RELU)
    ) u_out (
        .clk(clk), .rst_n(rst_n), .valid_in(mac_valid), .sum_in(mac_sum),
        .pixel_out(pixel_out), .valid_out(pixel_out_valid)
    );

    // ---- frame_done delayed to align with the LAST pixel_out_valid,
    // not the last pixel consumed (frame_end_raw fires TOTAL_LATENCY
    // cycles before the corresponding final output actually appears) ----
    reg [TOTAL_LATENCY-1:0] frame_done_shift;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_done_shift <= {TOTAL_LATENCY{1'b0}};
        else        frame_done_shift <= {frame_done_shift[TOTAL_LATENCY-2:0], frame_end_raw};
    end
    assign frame_done = frame_done_shift[TOTAL_LATENCY-1];

endmodule
