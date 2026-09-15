`timescale 1ns/1ps

// ------------------------------------------------------------
// conv_mac_tree — parallel multiply + pipelined binary adder tree.
// Single module (generate-loop based) to avoid a maze of hand-wired
// intermediate signals. Fixes the sign-extension bug: the unsigned
// pixel is explicitly zero-extended before being treated as signed,
// otherwise Verilog performs UNSIGNED multiplication whenever one
// operand of '*' is unsigned, silently discarding the kernel's sign.
// ------------------------------------------------------------
module conv_mac_tree #(
    parameter PIXEL_W  = 8,
    parameter KERNEL_W = 8,
    parameter NUM_TAPS = 9,
    parameter PROD_W   = PIXEL_W + KERNEL_W,          // 16: exact worst-case width, no truncation
    parameter SUM_W    = PROD_W + $clog2(NUM_TAPS)    // 20 for NUM_TAPS=9: safe worst-case accumulator
)(
    input  wire                                clk,
    input  wire                                rst_n,
    input  wire                                valid_in,
    input  wire        [PIXEL_W*NUM_TAPS-1:0]  win_in,     // unsigned, flattened
    input  wire signed [KERNEL_W*NUM_TAPS-1:0] kernel_in,  // signed, flattened
    output reg  signed [SUM_W-1:0]             sum_out,
    output reg                                 valid_out
);
    localparam LEVELS = $clog2(NUM_TAPS);

    // ---- Stage 1: Multiply (registered) ----
    reg signed [PROD_W-1:0] prod_reg [0:NUM_TAPS-1];
    reg                     valid_r1;

    genvar k;
    generate
        for (k = 0; k < NUM_TAPS; k = k + 1) begin : gen_mult
            wire        [PIXEL_W-1:0]  pix  = win_in[k*PIXEL_W +: PIXEL_W];
            wire signed [KERNEL_W-1:0] coef = kernel_in[k*KERNEL_W +: KERNEL_W];
            // Zero-extend the unsigned pixel by 1 bit, THEN treat as signed.
            wire signed [PIXEL_W:0] pix_s = {1'b0, pix};

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) prod_reg[k] <= {PROD_W{1'b0}};
                else        prod_reg[k] <= pix_s * coef;
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_r1 <= 1'b0;
        else        valid_r1 <= valid_in;
    end

    // ---- Stages 2..(LEVELS+1): pipelined binary reduction tree ----
    // All intermediate levels are stored in SUM_W-wide signed registers.
    // Since both source and destination are 'signed', direct assignment
    // through the always block automatically sign-extends narrower values
    // to SUM_W bits - no manual width-matching needed at any level.
    reg signed [SUM_W-1:0] level_data [0:LEVELS][0:NUM_TAPS-1];
    reg                    level_valid [0:LEVELS];

    integer i;
    always @(*) begin
        for (i = 0; i < NUM_TAPS; i = i + 1)
            level_data[0][i] = prod_reg[i];
    end
    always @(*) level_valid[0] = valid_r1;

    generate
        genvar lvl, idx;
        for (lvl = 0; lvl < LEVELS; lvl = lvl + 1) begin : gen_level
            localparam integer IN_COUNT  = (NUM_TAPS + (1<<lvl) - 1) >> lvl;
            localparam integer OUT_COUNT = (IN_COUNT + 1) >> 1;

            for (idx = 0; idx < OUT_COUNT; idx = idx + 1) begin : gen_adder
                if (2*idx+1 < IN_COUNT) begin : real_add
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) level_data[lvl+1][idx] <= {SUM_W{1'b0}};
                        else level_data[lvl+1][idx] <=
                                level_data[lvl][2*idx] + level_data[lvl][2*idx+1];
                    end
                end else begin : pass_through
                    // Odd tap out: still goes through a real register so every
                    // tap experiences the SAME number of pipeline stages.
                    always @(posedge clk or negedge rst_n) begin
                        if (!rst_n) level_data[lvl+1][idx] <= {SUM_W{1'b0}};
                        else        level_data[lvl+1][idx] <= level_data[lvl][2*idx];
                    end
                end
            end
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) level_valid[lvl+1] <= 1'b0;
                else        level_valid[lvl+1] <= level_valid[lvl];
            end
        end
    endgenerate

    always @(*) begin
        sum_out   = level_data[LEVELS][0];
        valid_out = level_valid[LEVELS];
    end
endmodule
