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
module tb_round_saturate_relu;
    localparam SUM_W = 20, OUT_W = 16;

    reg clk = 0, rst_n = 0, valid_in = 0;
    reg signed [SUM_W-1:0] sum_in;
    wire signed [OUT_W-1:0] pixel_out_plain, pixel_out_relu, pixel_out_shift;
    wire valid_out_plain, valid_out_relu, valid_out_shift;

    integer errors = 0;

    // DUT 1: FRAC_BITS=0, no ReLU  (matches current top-level decision)
    round_saturate_relu #(.SUM_W(SUM_W), .FRAC_BITS(0), .OUT_W(OUT_W), .ENABLE_RELU(0)) dut_plain (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .sum_in(sum_in),
        .pixel_out(pixel_out_plain), .valid_out(valid_out_plain)
    );
    // DUT 2: FRAC_BITS=0, ReLU enabled
    round_saturate_relu #(.SUM_W(SUM_W), .FRAC_BITS(0), .OUT_W(OUT_W), .ENABLE_RELU(1)) dut_relu (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .sum_in(sum_in),
        .pixel_out(pixel_out_relu), .valid_out(valid_out_relu)
    );
    // DUT 3: FRAC_BITS=4 - exercises the rounding path, for future fixed-point kernels
    round_saturate_relu #(.SUM_W(SUM_W), .FRAC_BITS(4), .OUT_W(OUT_W), .ENABLE_RELU(0)) dut_shift (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .sum_in(sum_in),
        .pixel_out(pixel_out_shift), .valid_out(valid_out_shift)
    );

    always #5 clk = ~clk;

    task check_plain(input signed [SUM_W-1:0] in_val, input signed [OUT_W-1:0] exp_val);
        begin
            @(posedge clk); sum_in = in_val; valid_in = 1;
            @(posedge clk); valid_in = 0;
            #1;
            if (pixel_out_plain !== exp_val) begin
                $display("[FAIL] round_saturate_relu (plain): in=%0d expected=%0d got=%0d",
                          in_val, exp_val, pixel_out_plain);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0; sum_in = 0; valid_in = 0;
        repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);

        check_plain(20'sd1000,   16'sd1000);
        check_plain(-20'sd1000, -16'sd1000);
        check_plain(20'sd40000,  16'sd32767);   // overflow -> saturate high
        check_plain(-20'sd40000,-16'sd32768);   // underflow -> saturate low

        // ReLU: same negative input, two different DUT configs must disagree
        @(posedge clk); sum_in = -20'sd500; valid_in = 1;
        @(posedge clk); valid_in = 0;
        #1;
        if (pixel_out_relu !== 16'sd0) begin
            $display("[FAIL] relu: expected 0 got %0d", pixel_out_relu);
            errors = errors + 1;
        end
        if (pixel_out_plain !== -16'sd500) begin
            $display("[FAIL] plain (no relu) on same input: expected -500 got %0d", pixel_out_plain);
            errors = errors + 1;
        end

        // Round-to-nearest: 200/16 = 12.5 -> rounds to 13
        @(posedge clk); sum_in = 20'sd200; valid_in = 1;
        @(posedge clk); valid_in = 0;
        #1;
        if (pixel_out_shift !== 16'sd13) begin
            $display("[FAIL] round: expected 13 got %0d", pixel_out_shift);
            errors = errors + 1;
        end

        if (errors == 0) $display("[PASS] tb_round_saturate_relu: all checks passed");
        else              $display("[FAIL] tb_round_saturate_relu: %0d mismatch(es)", errors);
        $finish;
    end
endmodule


