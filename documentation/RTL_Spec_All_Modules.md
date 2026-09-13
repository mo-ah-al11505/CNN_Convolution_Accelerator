# RTL Module Specifications — Full Accelerator Hierarchy
**Project:** FPGA-Based Edge-AI Vision Accelerator (IEEE SSCS Egypt 2026)
**Ordering:** Bottom-up (leaf/primitive modules first, top-level integration last)

Each entry gives: function, key parameters, key ports, and sub-module instantiation. Full 7-section specs (as done for `conv_mac_array`-level detail) can be expanded later for any module the team wants to code first.

---

## LEVEL 0 — Primitives (no sub-modules)

### 1. `mult_signed_unsigned`
- **Function:** Single multiply cell: 8-bit unsigned pixel × 8-bit signed kernel coefficient → 12-bit signed product.
- **Parameters:** `PIXEL_W=8`, `KERNEL_W=8`, `PROD_W=12`
- **Key ports:** `a_in[7:0]` (unsigned), `b_in[7:0]` (signed), `p_out[11:0]` (signed, registered)
- **Instantiates:** None (leaf). Instantiated **x9** inside `mac_array`.

### 2. `adder_2input`
- **Function:** Generic registered 2-input signed adder with 1-bit width growth. Reused across all adder-tree levels.
- **Parameters:** `IN_W` (configurable per level), `OUT_W = IN_W+1`
- **Key ports:** `a_in[IN_W-1:0]`, `b_in[IN_W-1:0]`, `sum_out[OUT_W-1:0]` (registered)
- **Instantiates:** None (leaf). Instantiated multiple times per level inside `adder_tree`.

### 3. `zero_pad_mux`
- **Function:** Generic 2:1 mux that forces a window cell to zero when the row/col counter indicates a border/padding position; otherwise passes the real pixel through.
- **Parameters:** `DATA_W=8`
- **Key ports:** `data_in[7:0]`, `is_border` (in, from control logic), `data_out[7:0]`
- **Instantiates:** None (leaf). Instantiated **4x** (top/bottom/left/right edge cells) inside `window_reg_array`.

---

## LEVEL 1 — Storage & Loading

### 4. `line_buffer`
- **Function:** BRAM-based single-row delay line; stores one full row of pixels (`IMG_W` deep) to generate the row-shifted stream needed for the sliding window.
- **Parameters:** `IMG_W=32` (configurable), `DATA_W=8`
- **Key ports:** `wr_data[7:0]`, `wr_en`, `rd_data[7:0]` (delayed by IMG_W cycles), `clk`, `rst_n`
- **Instantiates:** None (uses inferred/instantiated BRAM primitive). **Instantiated x2** (`line_buffer_0`, `line_buffer_1`) in `conv_accel_top`.

### 5. `kernel_rom`
- **Function:** Stores the static 3×3 kernel coefficients, initialized from a `.txt`/`.mem` file via `$readmemh`/`$readmemb`. Outputs all 9 coefficients in parallel.
- **Parameters:** `KERNEL_W=8`, `NUM_TAPS=9`, `INIT_FILE="kernel.mem"`
- **Key ports:** `coeff_out[9*8-1:0]` (flattened, combinational or registered read), `addr_in` (if multiple kernels supported)
- **Instantiates:** None (leaf memory).

### 6. `kernel_loader`
- **Function:** Optional control wrapper around `kernel_rom` — handles kernel-select addressing (bonus feature) or a simple load-enable/hold register if only one kernel is used per frame.
- **Parameters:** `NUM_KERNELS=1` (or more for bonus)
- **Key ports:** `kernel_sel_in`, `load_en`, `coeff_out[71:0]`
- **Instantiates:** `kernel_rom` (x1, or xN if multiple kernel sets stored).

---

## LEVEL 2 — Windowing & Compute Core

### 7. `window_reg_array`
- **Function:** Maintains the 3×3 sliding window register bank; shifts in the new pixel and the two line-buffer outputs each valid cycle, applying zero-padding at frame borders.
- **Parameters:** `N=3`, `PIXEL_W=8`
- **Key ports:** `pixel_in[7:0]`, `lb0_out[7:0]`, `lb1_out[7:0]`, `row_cnt`, `col_cnt` (in, from control), `win_out[71:0]` (flattened 3×3), `shift_en`
- **Instantiates:** `zero_pad_mux` (x4 — top, bottom, left, right border cells).

### 8. `mac_array`
- **Function:** Performs the 9 parallel multiplications between the window and kernel (pure multiply stage only — no summation).
- **Parameters:** `N=3`, `PIXEL_W=8`, `KERNEL_W=8`, `PROD_W=12`
- **Key ports:** `win_in[71:0]`, `kernel_in[71:0]`, `prod_out[9*12-1:0]` (flattened 9 products), `valid_in`, `valid_out`
- **Instantiates:** `mult_signed_unsigned` (x9).

### 9. `adder_tree`
- **Function:** 4-level pipelined binary tree that sums the 9 products from `mac_array` into a single raw signed sum.
- **Parameters:** `NUM_TAPS=9`, `IN_W=12`, `OUT_W=16`
- **Key ports:** `prod_in[9*12-1:0]`, `sum_out[15:0]` (signed, registered), `valid_in`, `valid_out`
- **Instantiates:** `adder_2input` (x8 total across the 4 levels: 4+2+1+1).

---

## LEVEL 3 — Output Conditioning

### 10. `round_saturate_unit`
- **Function:** Shifts the raw Q11.4 sum right by 4 bits (round-to-nearest), then saturates the result to the 16-bit signed range [−32768, 32767].
- **Parameters:** `SUM_W=16`, `FRAC_BITS=4`, `OUT_W=16`
- **Key ports:** `sum_in[15:0]`, `valid_in`, `pixel_out[15:0]`, `valid_out`
- **Instantiates:** None (leaf combinational + 1 register stage).

### 11. `relu_unit` *(optional/bonus)*
- **Function:** Zeros out negative output values (sign-bit check) as a simple post-processing activation.
- **Parameters:** `DATA_W=16`
- **Key ports:** `data_in[15:0]`, `valid_in`, `data_out[15:0]`, `valid_out`
- **Instantiates:** None (leaf, 1-bit mux + optional register).

---

## LEVEL 4 — Control Plane

### 12. `row_col_counter`
- **Function:** Tracks current write/read pixel position (`row_cnt`, `col_cnt`) within the frame; flags border conditions and end-of-row/end-of-frame events.
- **Parameters:** `IMG_W=32`, `IMG_H=32`
- **Key ports:** `pixel_valid_in`, `row_cnt_out`, `col_cnt_out`, `is_top_row`, `is_bottom_row`, `is_left_col`, `is_right_col`, `frame_end_flag`
- **Instantiates:** None (leaf, two counters + comparators).

### 13. `drain_counter`
- **Function:** Counts cycles during the `DRAIN` state until the pipeline (`PIPE_DEPTH`) has fully flushed remaining valid outputs.
- **Parameters:** `PIPE_DEPTH=6` (or 7 with ReLU)
- **Key ports:** `drain_en`, `drain_done`
- **Instantiates:** None (leaf counter).

### 14. `pipe_valid_shift_reg`
- **Function:** Generic shift register that delays a valid/enable pulse by `N` cycles to align with a given pipeline depth (reused for MAC array, adder tree, and overall `pixel_out_valid` generation).
- **Parameters:** `DEPTH` (instance-specific, e.g., 5 for `mac_array`+`adder_tree`, 6–7 for full datapath)
- **Key ports:** `valid_in`, `valid_out`
- **Instantiates:** None (leaf).

### 15. `fsm_control`
- **Function:** Top-level state machine (`IDLE → FILL → RUN → DRAIN → DONE`) that sequences the whole accelerator, using status flags from `row_col_counter` and `drain_counter` to drive transitions and generate `shift_en`, `drain_en`, `ready`, `frame_done`.
- **Parameters:** None (control-only; behavior depends on `row_col_counter`/`drain_counter` parameters)
- **Key ports:** `start_frame`, `pixel_valid_in`, `frame_flags_in` (from `row_col_counter`), `drain_done_in`, `ready_out`, `frame_done_out`, `shift_en_out`
- **Instantiates:** None directly (it *consumes* outputs of `row_col_counter`/`drain_counter`, which are siblings instantiated at the top level, not children of the FSM).

---

## LEVEL 5 — Top-Level Integration

### 16. `conv_accel_top`
- **Function:** Top wrapper that connects all modules above into the complete streaming convolution accelerator: accepts one pixel per cycle, outputs one convolved pixel per cycle (after pipeline latency), fully sequenced by `fsm_control`.
- **Parameters:** All parameters above, passed down: `N`, `IMG_W`, `IMG_H`, `PIXEL_W`, `KERNEL_W`, `SUM_W`, `PIPE_DEPTH`, `ENABLE_RELU`
- **Key ports:** `clk`, `rst_n`, `start_frame`, `pixel_in[7:0]`, `pixel_valid`, `pixel_out[15:0]`, `pixel_out_valid`, `frame_done`, `ready`
- **Instantiates:**
  `line_buffer` (x2), `kernel_loader` (x1, → `kernel_rom` x1), `window_reg_array` (x1, → `zero_pad_mux` x4), `mac_array` (x1, → `mult_signed_unsigned` x9), `adder_tree` (x1, → `adder_2input` x8), `round_saturate_unit` (x1), `relu_unit` (x1, optional), `row_col_counter` (x1), `drain_counter` (x1), `pipe_valid_shift_reg` (x1 or more, as needed for alignment), `fsm_control` (x1).

---

## VERIFICATION-SIDE MODULES *(not synthesized — testbench hierarchy, listed for completeness)*

### 17. `image_rom`
- **Function:** Stores test input image/feature-map pixels, loaded from `.txt`/`.mem` file, streamed into `conv_accel_top` by the testbench.

### 18. `expected_output_rom`
- **Function:** Stores golden-model expected output values for direct comparison against hardware output.

### 19. `golden_model` *(Python/MATLAB/C++, not RTL)*
- **Function:** Reference software implementation of the same NxN convolution, used to generate `expected_output_rom` contents and validate correctness/rounding behavior.

### 20. `result_checker` / `scoreboard`
- **Function:** Compares `pixel_out`/`pixel_out_valid` against `expected_output_rom` contents cycle-by-cycle inside the testbench; reports pass/fail and mismatch locations.

### 21. `tb_conv_accel_top`
- **Function:** Top-level testbench: instantiates `conv_accel_top`, `image_rom`, `expected_output_rom`, `result_checker`, drives `clk`/`rst_n`/`start_frame`, and streams pixels in.

---

## OPTIONAL BONUS MODULES

### 22. `kernel_select_mux`
- **Function:** Selects among multiple stored kernel sets in `kernel_rom` for multi-kernel support (bonus feature).

### 23. `edge_detect_wrapper`
- **Function:** Thin wrapper around `conv_accel_top` pre-loaded with a Sobel/Laplacian kernel, used for the optional edge-detection/industrial-inspection demo.

---

## Instantiation Tree Summary

```
conv_accel_top
├── line_buffer            (x2)
├── kernel_loader
│   └── kernel_rom
├── window_reg_array
│   └── zero_pad_mux        (x4)
├── mac_array
│   └── mult_signed_unsigned (x9)
├── adder_tree
│   └── adder_2input         (x8)
├── round_saturate_unit
├── relu_unit                (optional)
├── row_col_counter
├── drain_counter
├── pipe_valid_shift_reg     (x1 or more)
└── fsm_control
```
