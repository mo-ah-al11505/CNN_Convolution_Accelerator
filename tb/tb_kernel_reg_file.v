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
module tb_kernel_reg_file;
    localparam NUM_TAPS = 9, KW = 8;

    reg clk = 0, rst_n = 0, we = 0;
    reg [$clog2(NUM_TAPS)-1:0] addr;
    reg signed [KW-1:0] data;
    wire signed [NUM_TAPS*KW-1:0] kernel_flat;

    integer errors = 0;
    integer i;
    reg signed [KW-1:0] expect_mem [0:NUM_TAPS-1];

    kernel_reg_file #(.NUM_TAPS(NUM_TAPS), .KERNEL_W(KW)) dut (
        .clk(clk), .rst_n(rst_n), .kernel_we(we),
        .kernel_addr(addr), .kernel_data(data), .kernel_flat(kernel_flat)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n = 0; we = 0; addr = 0; data = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Sobel-X - deliberately includes negative coefficients
        expect_mem[0] = -1; expect_mem[1] = 0; expect_mem[2] = 1;
        expect_mem[3] = -2; expect_mem[4] = 0; expect_mem[5] = 2;
        expect_mem[6] = -1; expect_mem[7] = 0; expect_mem[8] = 1;

        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            we = 1; addr = i; data = expect_mem[i];
            @(posedge clk);
        end
        we = 0;
        @(posedge clk); #1;

        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            if ($signed(kernel_flat[i*KW +: KW]) !== expect_mem[i]) begin
                $display("[FAIL] kernel_reg_file: tap %0d expected %0d got %0d",
                          i, expect_mem[i], $signed(kernel_flat[i*KW +: KW]));
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("[PASS] tb_kernel_reg_file: all checks passed");
        else              $display("[FAIL] tb_kernel_reg_file: %0d mismatch(es)", errors);
        $finish;
    end
endmodule


