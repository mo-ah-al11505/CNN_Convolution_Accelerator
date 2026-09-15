`timescale 1ns/1ps

// ------------------------------------------------------------
module tb_conv_accel_top;
    localparam IMG_W = 32, IMG_H = 32, N = 3, PW = 8, KW = 8, OUT_W = 16;
    localparam OH = IMG_H - N + 1, OW = IMG_W - N + 1;
    localparam NUM_TAPS = N*N;

    reg clk = 0, rst_n = 0, pixel_valid = 0, kernel_we = 0;
    reg [PW-1:0] pixel_in;
    reg [$clog2(NUM_TAPS)-1:0] kernel_addr;
    reg signed [KW-1:0] kernel_data;
    wire signed [OUT_W-1:0] pixel_out;
    wire pixel_out_valid;
    wire frame_done;

    conv_accel_top #(
        .IMG_W(IMG_W), .IMG_H(IMG_H), .N(N), .PIXEL_W(PW), .KERNEL_W(KW),
        .FRAC_BITS(0), .OUT_W(OUT_W), .ENABLE_RELU(1)   // <-- keep in sync with golden_model.py
    ) dut (
        .clk(clk), .rst_n(rst_n), .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .kernel_we(kernel_we), .kernel_addr(kernel_addr), .kernel_data(kernel_data),
        .pixel_out(pixel_out), .pixel_out_valid(pixel_out_valid), .frame_done(frame_done)
    );

    reg [PW-1:0] image_mem [0:IMG_W*IMG_H-1];
    reg signed [KW-1:0] krn_mem [0:NUM_TAPS-1];
    reg signed [OUT_W-1:0] expected_mem [0:OH*OW-1];

    integer i;
    integer out_idx = 0;
    integer errors = 0;
    integer out_file;   // file handle for out_hw.txt (consumed by py_tools/show.py)

    always #5 clk = ~clk;

    initial begin
        $readmemh("../images/in.txt",     image_mem);
        $readmemh("../images/kern.txt",   krn_mem, 0, NUM_TAPS-1);
        $readmemh("../images/out_gm.txt", expected_mem);   // run golden_model.py first!

        // Open out_hw.txt up front so the scoreboard's always block can
        // write to it as outputs stream out - same directory/relative
        // path convention as the other $readmemh calls above.
        out_file = $fopen("../images/out_hw.txt", "w");
        if (out_file == 0) begin
            $display("[FAIL] tb_conv_accel_top: could not open ../images/out_hw.txt for writing");
            $finish;
        end

        rst_n = 0; pixel_valid = 0; kernel_we = 0; kernel_addr = 0; kernel_data = 0; pixel_in = 0;
        repeat (2) @(posedge clk); rst_n = 1; @(posedge clk);

        // Load kernel via the runtime-programmable write port
        for (i = 0; i < NUM_TAPS; i = i + 1) begin
            kernel_we = 1; kernel_addr = i; kernel_data = krn_mem[i];
            @(posedge clk);
        end
        kernel_we = 0;
        @(posedge clk);

        // Stream the image, one pixel per cycle
        for (i = 0; i < IMG_W*IMG_H; i = i + 1) begin
            pixel_valid = 1;
            pixel_in    = image_mem[i];
            @(posedge clk);
        end
        pixel_valid = 0;

        repeat (20) @(posedge clk);   // let the pipeline drain

        $fclose(out_file);

        if (out_idx !== OH*OW) begin
            $display("[FAIL] conv_accel_top: expected %0d output pixels, got %0d", OH*OW, out_idx);
            errors = errors + 1;
        end

        if (errors == 0) $display("[PASS] tb_conv_accel_top: all %0d output pixels matched out_gm.txt", OH*OW);
        else              $display("[FAIL] tb_conv_accel_top: %0d error(s) total", errors);
        $finish;
    end

    // Scoreboard: compare every pixel_out_valid cycle against the golden
    // model's pre-computed output, in strict raster order, AND write the
    // same value to out_hw.txt (matching out_gm.txt's format exactly:
    // one 4-digit signed-16-bit two's-complement hex value per line) so
    // show.py can load and visualize it independently of this testbench's
    // own pass/fail check.
    always @(posedge clk) begin
        if (rst_n && pixel_out_valid) begin
            $fwrite(out_file, "%04x\n", pixel_out[15:0]);

            if (pixel_out !== expected_mem[out_idx]) begin
                $display("[FAIL] conv_accel_top: output #%0d expected=%0d got=%0d",
                          out_idx, expected_mem[out_idx], pixel_out);
                errors = errors + 1;
            end
            out_idx = out_idx + 1;
        end
    end
endmodule