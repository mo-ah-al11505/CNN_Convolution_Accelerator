// ============================================================
// tb_all_modules.v — Self-checking testbenches for every module.
//
// Each testbench is a separate top-level module below. Set whichever
// one you want to run as the simulation's "top module" in your tool
// (ModelSim/Vivado/Icarus: -top <module_name>).
//
// tb_window_generator, tb_conv_mac_tree, and tb_conv_accel_top read the
// SAME ../images/in.txt / kern.txt / out_gm.txt files the (corrected)
// golden_model.py uses, so RTL and golden model are always checked
// against identical test vectors. Run golden_model.py FIRST to
// (re)generate out_gm.txt before running tb_conv_accel_top.
//
// Adjust the "../images/..." paths below if your directory layout
// differs from golden_model.py's assumed ../images/ structure.
// ============================================================
`timescale 1ns/1ps


`timescale 1ns/1ps

// ------------------------------------------------------------
module tb_conv_mac_tree;
    localparam PW = 8, KW = 8, NUM_TAPS = 9;
    localparam PROD_W = PW + KW;
    localparam SUM_W  = PROD_W + $clog2(NUM_TAPS);

    reg clk = 0, rst_n = 0, valid_in = 0;
    reg [PW*NUM_TAPS-1:0] win_in;
    reg signed [KW*NUM_TAPS-1:0] kernel_in;
    wire signed [SUM_W-1:0] sum_out;
    wire valid_out;

    reg [PW-1:0] pix_mem [0:8];
    reg signed [KW-1:0] krn_mem [0:8];
    integer i;
    integer errors = 0;
    reg signed [SUM_W-1:0] expected_sum;

    conv_mac_tree #(.PIXEL_W(PW), .KERNEL_W(KW), .NUM_TAPS(NUM_TAPS)) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .win_in(win_in), .kernel_in(kernel_in),
        .sum_out(sum_out), .valid_out(valid_out)
    );

    always #5 clk = ~clk;

    initial begin
        $readmemh("../images/in.txt",   pix_mem, 0, 8);   // only first 9 pixels used
        $readmemh("../images/kern.txt", krn_mem, 0, 8);

        for (i = 0; i < 9; i = i + 1) begin
            win_in[i*PW +: PW]    = pix_mem[i];
            kernel_in[i*KW +: KW] = krn_mem[i];
        end

        // Same zero-extend-then-signed-multiply convention as the RTL fix
        expected_sum = 0;
        for (i = 0; i < 9; i = i + 1)
            expected_sum = expected_sum + ($signed({1'b0, pix_mem[i]}) * krn_mem[i]);

        rst_n = 0; valid_in = 0;
        repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);

        valid_in = 1;
        @(posedge clk);
        valid_in = 0;

        while (!valid_out) @(posedge clk);
        #1;

        if (sum_out !== expected_sum) begin
            $display("[FAIL] conv_mac_tree: expected %0d got %0d", expected_sum, sum_out);
            errors = errors + 1;
        end else begin
            $display("[INFO] conv_mac_tree: sum matched (%0d)", sum_out);
        end

        if (errors == 0) $display("[PASS] tb_conv_mac_tree: all checks passed");
        else              $display("[FAIL] tb_conv_mac_tree: %0d mismatch(es)", errors);
        $finish;
    end
endmodule


