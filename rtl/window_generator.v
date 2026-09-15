`timescale 1ns/1ps

// ------------------------------------------------------------
// window_generator — NxN sliding window via N-1 line buffers.
// INTERIOR-ONLY output: window_valid only asserts once a full
// NxN window of REAL pixels exists (row_cnt>=N-1 && col_cnt>=N-1).
// No zero padding -> output size is (IMG_W-N+1) x (IMG_H-N+1).
// ------------------------------------------------------------
module window_generator #(
    parameter IMG_W   = 32,
    parameter IMG_H   = 32,
    parameter N       = 3,
    parameter PIXEL_W = 8
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   pixel_valid,
    input  wire [PIXEL_W-1:0]     pixel_in,
    output wire [N*N*PIXEL_W-1:0] window_flat,   // row-major, k = i*N+j
    output reg                    window_valid,
    output reg                    frame_end       // pulses when the LAST real pixel is consumed
);
    localparam ROW_W = $clog2(IMG_H);
    localparam COL_W = $clog2(IMG_W);

    reg [ROW_W-1:0] row_cnt;
    reg [COL_W-1:0] col_cnt;

    wire is_last_row = (row_cnt == IMG_H-1);
    wire is_last_col = (col_cnt == IMG_W-1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt <= 0; col_cnt <= 0;
        end else if (pixel_valid) begin
            if (is_last_col) begin
                col_cnt <= 0;
                row_cnt <= is_last_row ? row_cnt : row_cnt + 1'b1;
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) frame_end <= 1'b0;
        else        frame_end <= pixel_valid && is_last_row && is_last_col;
    end

    // ---- N-1 chained line buffers (row delays) ----
    wire [PIXEL_W-1:0] lb_out [0:N-2];
    genvar gb;
    generate
        for (gb = 0; gb < N-1; gb = gb + 1) begin : gen_lb
            wire [PIXEL_W-1:0] lb_wr_data = (gb == 0) ? pixel_in : lb_out[gb-1];
            line_buffer #(.IMG_W(IMG_W), .DATA_W(PIXEL_W)) u_lb (
                .clk(clk), .rst_n(rst_n), .wr_en(pixel_valid),
                .wr_data(lb_wr_data), .rd_data(lb_out[gb])
            );
        end
    endgenerate

    // ---- Row source select: row N-1 (bottom, newest) = live pixel_in,
    // rows 0..N-2 (top..middle) = increasingly delayed line-buffer taps.
    // row 0 (top, oldest)    -> lb_out[N-2]  (N-1 rows delayed)
    // row N-2 (just above bottom) -> lb_out[0] (1 row delayed)
    // IMPORTANT: this row<->buffer mapping direction matters - swapping it
    // vertically flips the kernel response. Verify against an asymmetric
    // kernel (e.g. Sobel) in the golden model, not just a symmetric blur.
    wire [PIXEL_W-1:0] row_source [0:N-1];
    genvar gr;
    generate
        for (gr = 0; gr < N; gr = gr + 1) begin : gen_rowsrc
            if (gr == N-1)
                assign row_source[gr] = pixel_in;
            else
                assign row_source[gr] = lb_out[N-2-gr];
        end
    endgenerate

    // ---- NxN sliding window shift register ----
    reg [PIXEL_W-1:0] win [0:N-1][0:N-1];
    integer rr, cc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (rr = 0; rr < N; rr = rr + 1)
                for (cc = 0; cc < N; cc = cc + 1)
                    win[rr][cc] <= {PIXEL_W{1'b0}};
        end else if (pixel_valid) begin
            for (rr = 0; rr < N; rr = rr + 1) begin
                for (cc = 0; cc < N-1; cc = cc + 1)
                    win[rr][cc] <= win[rr][cc+1];
                win[rr][N-1] <= row_source[rr];
            end
        end
    end

    genvar fi, fj;
    generate
        for (fi = 0; fi < N; fi = fi + 1)
            for (fj = 0; fj < N; fj = fj + 1)
                assign window_flat[(fi*N+fj)*PIXEL_W +: PIXEL_W] = win[fi][fj];
    endgenerate

    // ---- Valid: full window of REAL data must exist (interior-only) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) window_valid <= 1'b0;
        else        window_valid <= pixel_valid && (row_cnt >= N-1) && (col_cnt >= N-1);
    end
endmodule
