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
module tb_line_buffer;
    localparam IMG_W = 4;

    reg clk = 0, rst_n = 0, wr_en = 0;
    reg  [7:0] wr_data;
    wire [7:0] rd_data;

    integer errors = 0;
    integer i;

    line_buffer #(.IMG_W(IMG_W), .DATA_W(8)) dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en),
        .wr_data(wr_data), .rd_data(rd_data)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n = 0; wr_en = 0; wr_data = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Ramp 10, 11, 12, ... ; rd_data must equal the value written IMG_W cycles ago
        for (i = 0; i < 2*IMG_W; i = i + 1) begin
            wr_en   = 1;
            wr_data = 10 + i;
            @(posedge clk);
            #1;
            if (i >= IMG_W) begin
                if (rd_data !== (10 + i - IMG_W)) begin
                    $display("[FAIL] line_buffer: cycle %0d expected %0d got %0d",
                              i, 10 + i - IMG_W, rd_data);
                    errors = errors + 1;
                end
            end
        end
        wr_en = 0;

        if (errors == 0) $display("[PASS] tb_line_buffer: all checks passed");
        else              $display("[FAIL] tb_line_buffer: %0d mismatch(es)", errors);
        $finish;
    end
endmodule


