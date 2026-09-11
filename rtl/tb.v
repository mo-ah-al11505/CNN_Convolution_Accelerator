// ============================================================
// tb.v — Testbench
// Reads:  ../images/in.txt  (one hex byte per line)
//         ../images/kern.txt (one hex byte per line)
// Writes: ../images/out_hw.txt (one 16-bit hex per line)
// ============================================================
`timescale 1ns/1ps

module tb;
    localparam IMG_SIZE = 32;   // <-- change here and in rtl.v, tools, for real images
    localparam KRN_SIZE = 3;
    localparam NUM_PIX  = IMG_SIZE * IMG_SIZE;
    localparam NUM_OUT  = (IMG_SIZE - KRN_SIZE + 1) * (IMG_SIZE - KRN_SIZE + 1);

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    // input
    reg  [7:0] pixel_in    = 0;
    reg        pixel_valid = 0;

    // kernel
    reg        kernel_we    = 0;
    reg  [7:0] kernel_addr  = 0;
    reg  [7:0] kernel_data  = 0;

    // output
    wire signed [15:0] pixel_out;
    wire               pixel_out_valid;
    wire [15:0]        out_count;

    top_accelerator #(.IMG_SIZE(IMG_SIZE), .KRN_SIZE(KRN_SIZE)) dut (
        .clk             (clk),
        .rst             (rst),
        .pixel_in        (pixel_in),
        .pixel_valid     (pixel_valid),
        .kernel_we       (kernel_we),
        .kernel_addr     (kernel_addr),
        .kernel_data     (kernel_data),
        .pixel_out       (pixel_out),
        .pixel_out_valid (pixel_out_valid),
        .out_count       (out_count)
    );

    reg [7:0]  image_mem  [0:NUM_PIX-1];
    reg [7:0]  kernel_mem [0:KRN_SIZE*KRN_SIZE-1];

    integer    fout;
    integer    i;
    integer    written;

    always @(posedge clk) begin
        if (!rst && pixel_out_valid) begin
            $fwrite(fout, "%04x\n", pixel_out);
            written = written + 1;
        end
    end

    initial begin
        written = 0;

        $readmemh("../images/in.txt",   image_mem);
        $readmemh("../images/kern.txt", kernel_mem);

        fout = $fopen("../images/out_hw.txt", "w");
        if (fout == 0) begin
            $display("[ERROR] cannot open out_hw.txt");
            $finish;
        end

        rst = 1;
        repeat(10) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // ---- load kernel ----
        for (i = 0; i < KRN_SIZE*KRN_SIZE; i = i + 1) begin
            @(posedge clk);
            kernel_we   = 1;
            kernel_addr = i[7:0];
            kernel_data = kernel_mem[i];
        end
        @(posedge clk);
        kernel_we = 0;

        // ---- feed image ----
        for (i = 0; i < NUM_PIX; i = i + 1) begin
            @(posedge clk);
            pixel_in    = image_mem[i];
            pixel_valid = 1;
        end
        @(posedge clk);
        pixel_valid = 0;
        pixel_in    = 0;

        // ---- drain pipeline ----
        repeat (20) @(posedge clk);

        $fclose(fout);
        $display("[INFO] out_count = %0d, expected = %0d", out_count, NUM_OUT);
        if (out_count == NUM_OUT) $display("[PASS] count OK");
        else                      $display("[FAIL] count mismatch");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("[TIMEOUT]");
        $finish;
    end
endmodule