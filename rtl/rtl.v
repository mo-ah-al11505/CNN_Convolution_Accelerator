// ============================================================
// rtl.v — Complete accelerator (FIXED)
// ============================================================
`timescale 1ns/1ps

// ------------------------------------------------------------
// Window Generator (full frame buffer, safe reads)
// ------------------------------------------------------------
module window_generator #(
    parameter IMG_SIZE = 32,
    parameter KRN_SIZE = 3
)(
    input  wire                            clk,
    input  wire                            rst,
    input  wire                            shift_en,
    input  wire [7:0]                      pixel_in,
    output wire [KRN_SIZE*KRN_SIZE*8-1:0]  window_flat,
    output reg                             valid
);
    reg [7:0]  mem [0:IMG_SIZE*IMG_SIZE-1];
    reg [15:0] wr_row, wr_col;
    reg [15:0] rd_row, rd_col;
    integer    i;

    // Combinational window read (gated by 'valid' to avoid OOB)
    genvar gi, gj;
    generate
        for (gi = 0; gi < KRN_SIZE; gi = gi + 1) begin : gen_r
            for (gj = 0; gj < KRN_SIZE; gj = gj + 1) begin : gen_c
                assign window_flat[(gi*KRN_SIZE+gj)*8 +: 8] =
                    valid ? mem[(rd_row - KRN_SIZE + 1 + gi) * IMG_SIZE
                                + (rd_col - KRN_SIZE + 1 + gj)]
                          : 8'h00;
            end
        end
    endgenerate

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < IMG_SIZE*IMG_SIZE; i = i + 1)
                mem[i] <= 8'h00;
            wr_row <= 0; wr_col <= 0;
            rd_row <= 0; rd_col <= 0;
            valid  <= 1'b0;
        end
        else if (shift_en) begin
            mem[wr_row * IMG_SIZE + wr_col] <= pixel_in;
            rd_row <= wr_row;
            rd_col <= wr_col;

            if (wr_col == IMG_SIZE-1) begin
                wr_col <= 0;
                wr_row <= (wr_row == IMG_SIZE-1) ? 0 : wr_row + 1;
            end
            else
                wr_col <= wr_col + 1;

            valid <= (wr_row >= KRN_SIZE-1) && (wr_col >= KRN_SIZE-1);
        end
        else
            valid <= 1'b0;
    end
endmodule

// ------------------------------------------------------------
// MAC array (no en_valid port needed)
// ------------------------------------------------------------
module mac_array #(
    parameter KRN_SIZE = 3
)(
    input  wire                            clk,
    input  wire                            rst,
    input  wire                            en,
    input  wire [KRN_SIZE*KRN_SIZE*8-1:0]  window_flat,
    input  wire [KRN_SIZE*KRN_SIZE*8-1:0]  kernel_flat,
    output reg  signed [31:0]              acc_out
);
    localparam NUM = KRN_SIZE * KRN_SIZE;
    reg signed [15:0] prod_r [0:NUM-1];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst)
            for (i = 0; i < NUM; i = i + 1) prod_r[i] <= 16'sd0;
        else if (en)
            for (i = 0; i < NUM; i = i + 1)
                prod_r[i] <= $signed(window_flat[i*8 +: 8]) *
                             $signed(kernel_flat[i*8 +: 8]);
    end

    reg signed [31:0] sum_c;
    always @(*) begin
        sum_c = 32'sd0;
        for (i = 0; i < NUM; i = i + 1) sum_c = sum_c + prod_r[i];
    end

    always @(posedge clk or posedge rst) begin
        if (rst)          acc_out <= 32'sd0;
        else if (en)      acc_out <= sum_c;
    end
endmodule

// ------------------------------------------------------------
// Saturate 32 -> 16 signed
// ------------------------------------------------------------
module saturate_16 (
    input  wire signed [31:0] din,
    output wire signed [15:0] dout
);
    assign dout = (din >  32'sd32767)  ?  16'sd32767 :
                  (din < -32'sd32768)  ? -16'sd32768 :
                  din[15:0];
endmodule

// ------------------------------------------------------------
// ReLU
// ------------------------------------------------------------
module relu_16 (
    input  wire signed [15:0] din,
    output wire signed [15:0] dout
);
    assign dout = din[15] ? 16'sd0 : din;
endmodule

// ------------------------------------------------------------
// Top Accelerator
// ------------------------------------------------------------
module top_accelerator #(
    parameter IMG_SIZE = 32,
    parameter KRN_SIZE = 3
)(
    input  wire               clk,
    input  wire               rst,
    input  wire [7:0]         pixel_in,
    input  wire               pixel_valid,
    input  wire               kernel_we,
    input  wire [7:0]         kernel_addr,
    input  wire [7:0]         kernel_data,
    output wire signed [15:0] pixel_out,
    output wire               pixel_out_valid,
    output wire [15:0]        out_count
);
    localparam NUM = KRN_SIZE * KRN_SIZE;

    // ---- kernel memory ----
    reg [7:0] kernel_mem [0:NUM-1];
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst)
            for (i = 0; i < NUM; i = i + 1) kernel_mem[i] <= 8'h00;
        else if (kernel_we)
            kernel_mem[kernel_addr] <= kernel_data;
    end

    wire [NUM*8-1:0] kernel_flat;
    genvar gi;
    generate
        for (gi = 0; gi < NUM; gi = gi + 1)
            assign kernel_flat[gi*8 +: 8] = kernel_mem[gi];
    endgenerate

    // ---- window generator ----
    wire [NUM*8-1:0] window_flat;
    wire             win_valid;
    window_generator #(.IMG_SIZE(IMG_SIZE), .KRN_SIZE(KRN_SIZE)) u_wg (
        .clk         (clk),
        .rst         (rst),
        .shift_en    (pixel_valid),
        .pixel_in    (pixel_in),
        .window_flat (window_flat),
        .valid       (win_valid)
    );

    // ---- MAC ----
    wire signed [31:0] acc;
    mac_array #(.KRN_SIZE(KRN_SIZE)) u_mac (
        .clk         (clk),
        .rst         (rst),
        .en          (1'b1),
        .window_flat (window_flat),
        .kernel_flat (kernel_flat),
        .acc_out     (acc)
    );

    // ---- saturate + relu ----
    wire signed [15:0] sat_out, relu_out;
    saturate_16 u_sat  (.din(acc),     .dout(sat_out));
    relu_16     u_relu (.din(sat_out), .dout(relu_out));

    assign pixel_out = relu_out;

    // ---- pipeline valid (win_valid delayed by 2 for MAC latency) ----
    reg v1, v2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin v1 <= 1'b0; v2 <= 1'b0; end
        else     begin v1 <= win_valid; v2 <= v1; end
    end
    assign pixel_out_valid = v2;

    // ---- debug counter ----
    reg [15:0] cnt;
    always @(posedge clk or posedge rst) begin
        if (rst)     cnt <= 16'd0;
        else if (v2) cnt <= cnt + 16'd1;
    end
    assign out_count = cnt;

endmodule