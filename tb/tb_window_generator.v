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
module tb_window_generator;
    localparam IMG_W = 32, IMG_H = 32, N = 3, PW = 8;

    reg clk = 0, rst_n = 0, pixel_valid = 0;
    reg  [PW-1:0] pixel_in;
    wire [N*N*PW-1:0] window_flat;
    wire window_valid;
    wire frame_end;

    reg [PW-1:0] image_mem [0:IMG_W*IMG_H-1];
    integer errors = 0;
    integer idx, row_chk, col_chk, ki, kj;
    reg [PW-1:0] expected;

    window_generator #(.IMG_W(IMG_W), .IMG_H(IMG_H), .N(N), .PIXEL_W(PW)) dut (
        .clk(clk), .rst_n(rst_n), .pixel_valid(pixel_valid), .pixel_in(pixel_in),
        .window_flat(window_flat), .window_valid(window_valid), .frame_end(frame_end)
    );

    always #5 clk = ~clk;

    initial begin
        $readmemh("../images/in.txt", image_mem);

        rst_n = 0; pixel_valid = 0; pixel_in = 0;
        repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);

        for (idx = 0; idx < IMG_W*IMG_H; idx = idx + 1) begin
            pixel_valid = 1;
            pixel_in    = image_mem[idx];
            @(posedge clk);
            #1;
            if (window_valid) begin
                row_chk = idx / IMG_W;
                col_chk = idx % IMG_W;
                for (ki = 0; ki < N; ki = ki + 1) begin
                    for (kj = 0; kj < N; kj = kj + 1) begin
                        expected = image_mem[(row_chk-(N-1)+ki)*IMG_W + (col_chk-(N-1)+kj)];
                        if (window_flat[(ki*N+kj)*PW +: PW] !== expected) begin
                            $display("[FAIL] window_generator: idx=%0d (row=%0d,col=%0d) win[%0d][%0d] expected=%0d got=%0d",
                                      idx, row_chk, col_chk, ki, kj, expected,
                                      window_flat[(ki*N+kj)*PW +: PW]);
                            errors = errors + 1;
                        end
                    end
                end
            end
        end
        pixel_valid = 0;

        if (errors == 0) $display("[PASS] tb_window_generator: all valid windows matched in.txt");
        else              $display("[FAIL] tb_window_generator: %0d mismatch(es)", errors);
        $finish;
    end
endmodule


