# RTL Module Specifications — Full Accelerator Hierarchy (Detailed Functionality)
**Project:** FPGA-Based Edge-AI Vision Accelerator (IEEE SSCS Egypt 2026)
**Ordering:** Bottom-up (leaf/primitive modules first, top-level integration last)

Functionality sections below are written at the signal/cycle level so they can be translated almost directly into `always @(posedge clk)` blocks and combinational logic.

---

## LEVEL 0 — Primitives (no sub-modules)

### 1. `mult_signed_unsigned`
**Function:**
Computes a single tap of the convolution: `p = win_pixel × kernel_coeff`. Since `win_pixel` is unsigned (UQ8.0) and `kernel_coeff` is signed (SQ3.4), the unsigned operand must first be zero-extended by one bit and reinterpreted as signed before multiplication, otherwise the tool will infer an unsigned×signed mismatch or silently misinterpret the MSB. Concretely:
```
wire signed [8:0] a_signed = {1'b0, a_in};   // zero-extend unsigned pixel, now safely "signed"
wire signed [7:0] b_signed = b_in;           // kernel already signed
wire signed [16:0] p_full  = a_signed * b_signed;
```
Only the lower 12 bits of `p_full` are retained as `p_out` (per the bit-growth analysis — 12 bits is sufficient for the worst-case product magnitude of 255×127). The result is registered on the rising edge of `clk`, gated by an internal or external `valid_in` signal — if `valid_in` is low, the register should either hold its previous value or clear to zero (team's choice, but must be consistent with how `mac_array` treats gaps in the stream, e.g. during `DRAIN`). Reset (`rst_n`, async active-low) clears `p_out` to 0 immediately regardless of clock.

**Parameters:** `PIXEL_W=8`, `KERNEL_W=8`, `PROD_W=12`
**Key ports:** `a_in[7:0]` (unsigned), `b_in[7:0]` (signed), `p_out[11:0]` (signed, registered)
**Instantiates:** None (leaf). Instantiated **x9** inside `mac_array`.

---

### 2. `adder_2input`
**Function:**
A single reusable building block for every level of the adder tree. It adds two signed operands of width `IN_W` and produces a registered result of width `IN_W+1` (the extra bit is mandatory — dropping it silently truncates and will cause golden-model mismatches on borderline test vectors). Because the two inputs may arrive from different tree levels with different original widths, **always sign-extend the narrower operand to match `IN_W` before adding**, never zero-extend (both operands here are signed after Stage 1). Implementation:
```
wire signed [IN_W:0] sum_full = $signed(a_in) + $signed(b_in);
always @(posedge clk or negedge rst_n)
  if (!rst_n) sum_out <= 0;
  else        sum_out <= sum_full;
```
This module is instantiated multiple times per adder-tree level, each instance independent (no shared state), which is what makes the tree fully parallel/pipelined rather than a serial accumulator.

**Parameters:** `IN_W` (per-instance), `OUT_W = IN_W+1`
**Key ports:** `a_in[IN_W-1:0]`, `b_in[IN_W-1:0]`, `sum_out[OUT_W-1:0]` (registered)
**Instantiates:** None (leaf). Instantiated multiple times per level inside `adder_tree`.

---

### 3. `zero_pad_mux`
**Function:**
Implements the zero-padding decision for a single window cell. Rather than physically shrinking/growing the window at frame edges, this mux forces a cell's value to `8'd0` whenever the control logic determines that cell corresponds to a "virtual" out-of-frame pixel (row −1, row `IMG_H`, col −1, or col `IMG_W`). The `is_border` input is purely combinational, driven by comparators on `row_cnt`/`col_cnt` from `row_col_counter` — this module itself contains **no counters**, it is a pure 2:1 mux:
```
assign data_out = is_border ? 8'd0 : data_in;
```
Four instances are needed inside `window_reg_array`: one gating the entire top row of the window (`is_border = (row_cnt == 0)`), one for the bottom row (`row_cnt == IMG_H-1`), one for the left column (`col_cnt == 0`), and one for the right column (`col_cnt == IMG_W-1`). Corner cells (e.g., top-left) will have **two** conditions ORed together upstream, or you can cascade two muxes — either is acceptable, just be explicit about which approach you chose in the report since it affects how many LUTs this costs.

**Parameters:** `DATA_W=8`
**Key ports:** `data_in[7:0]`, `is_border` (in, from control logic), `data_out[7:0]`
**Instantiates:** None (leaf). Instantiated **4x** inside `window_reg_array`.

---

## LEVEL 1 — Storage & Loading

### 4. `line_buffer`
**Function:**
Acts as a "row delay" using FPGA block RAM as a circular buffer of depth `IMG_W`. Every cycle that `wr_en` is high, the incoming pixel is written to the current write address, and simultaneously the pixel written `IMG_W` cycles ago is read out — effectively delaying the entire stream by exactly one image row. This is the classic sliding-window trick that avoids storing the whole image in on-chip memory.
Implementation approach: use a single dual-port BRAM (or two single-port BRAMs if the target FPGA's inference tool prefers it) with one write pointer and one read pointer, both wrapping modulo `IMG_W`:
```
always @(posedge clk) begin
  if (wr_en) begin
    mem[wr_ptr] <= wr_data;
    rd_data     <= mem[wr_ptr];   // read-before-write at the SAME address one row later
    wr_ptr      <= (wr_ptr == IMG_W-1) ? 0 : wr_ptr + 1;
  end
end
```
Note the subtlety: the read address must trail the write address by exactly `IMG_W` locations, which in a circular buffer of depth `IMG_W` is mathematically the **same address**, just one full lap later — so a single pointer naturally implements the 1-row delay as long as write and read happen on the same address each cycle. Two instances are chained: `line_buffer_0` delays the live pixel stream by 1 row (giving "row above"), and `line_buffer_1` takes `line_buffer_0`'s output and delays it by another row (giving "two rows above"). Together with the live `pixel_in`, this produces the three row-streams needed to fill the 3×3 window every cycle.

**Parameters:** `IMG_W=32` (configurable), `DATA_W=8`
**Key ports:** `wr_data[7:0]`, `wr_en`, `rd_data[7:0]` (delayed by IMG_W cycles), `clk`, `rst_n`
**Instantiates:** None (uses inferred/instantiated BRAM primitive). **Instantiated x2** in `conv_accel_top`.

---

### 5. `kernel_rom`
**Function:**
Holds the 9 kernel coefficients as a small initialized memory (or simply 9 registers if you prefer regs over inferred ROM — for only 9×8 bits, either is fine and a register-based implementation is arguably simpler and avoids BRAM/ROM inference quirks). If using `$readmemh`, the coefficients are loaded once at simulation/config time from a plain text file (`kernel.mem`), one hex value per line, in row-major order matching the `kernel_in` flattening convention used everywhere else (`k = i*N+j`). All 9 values are exposed on a single flattened output bus, updated combinationally (or on a single registered load pulse if you want a clean single-cycle load boundary):
```
initial $readmemh("kernel.mem", coeff_mem);
assign coeff_out = {coeff_mem[8], coeff_mem[7], ..., coeff_mem[0]};  // pack MSB-first or LSB-first, pick one and document it
```
For FPGA synthesis (not just simulation), replace `$readmemh` with either a ROM initialized via a `.coe`/`.mif` file (Xilinx/Intel-specific) or simply hard-code the coefficients as parameters if the kernel never needs to change post-synthesis — document whichever route you take, since "kernel coefficients should be programmable/configurable" per the spec, a register-file approach with a load port is the safer choice if you want partial credit for runtime configurability.

**Parameters:** `KERNEL_W=8`, `NUM_TAPS=9`, `INIT_FILE="kernel.mem"`
**Key ports:** `coeff_out[9*8-1:0]` (flattened), `addr_in` (if multiple kernels supported)
**Instantiates:** None (leaf memory).

---

### 6. `kernel_loader`
**Function:**
A thin control wrapper that decides *which* kernel gets presented to `mac_array` and *when* it updates. In the simplest (non-bonus) case, this module does almost nothing: it just registers the ROM output once at reset/start-of-frame and holds it static for the entire frame (kernels are not expected to change mid-frame per our architecture assumptions). If implementing the multi-kernel bonus, this module instead multiplexes between several stored kernel sets based on `kernel_sel_in`, updating the registered output only on a `load_en` pulse (to avoid glitching the MAC array mid-computation):
```
always @(posedge clk or negedge rst_n)
  if (!rst_n)         coeff_out <= 0;
  else if (load_en)   coeff_out <= kernel_rom_out;   // latch new kernel only on explicit load
```
This registered-and-held behavior is important: it guarantees `mac_array` always sees a stable, glitch-free kernel value throughout a frame, decoupling kernel-switching timing from the pixel-streaming timing entirely.

**Parameters:** `NUM_KERNELS=1` (or more for bonus)
**Key ports:** `kernel_sel_in`, `load_en`, `coeff_out[71:0]`
**Instantiates:** `kernel_rom` (x1, or xN if multiple kernel sets stored).

---

## LEVEL 2 — Windowing & Compute Core

### 7. `window_reg_array`
**Function:**
This is the module that actually assembles the 3×3 neighborhood consumed by `mac_array`, and is the trickiest data-movement block in the whole design — get this right and the rest is comparatively mechanical. Every cycle that `shift_en` is asserted (driven by the FSM during `RUN`/`DRAIN`), three new pixels arrive simultaneously — `pixel_in` (current row), `lb0_out` (row above), `lb1_out` (row two above) — and the entire 3×3 register array shifts one column to the left, discarding the oldest column and admitting these three new values into the rightmost column:
```
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    win_reg <= 0;
  end else if (shift_en) begin
    // shift each row left by one cell, then load new rightmost column
    win_reg[0] <= {win_reg[0][1:0], row0_new_pixel};  // top row    <- lb1_out (masked by zero_pad_mux)
    win_reg[1] <= {win_reg[1][1:0], row1_new_pixel};  // middle row <- lb0_out
    win_reg[2] <= {win_reg[2][1:0], row2_new_pixel};  // bottom row <- pixel_in (masked by zero_pad_mux)
  end
end
```
Before being shifted in, each of the three new pixels passes through its corresponding `zero_pad_mux` instance, which overrides it to zero if `row_cnt`/`col_cnt` indicates a border condition. Note the ordering subtlety: which physical line-buffer output maps to which conceptual window row (top/middle/bottom) depends on your line-buffer chaining direction — document this mapping explicitly in code comments, since getting it backwards produces a vertically-flipped kernel response that will silently pass a symmetric-kernel golden-model test (e.g. box blur) but fail on any asymmetric kernel (e.g. Sobel), which is a classic bug in first-time convolution RTL. Once shifted, `win_out` is simply the flattened concatenation of all 9 register cells, valid on the same cycle `shift_en` was asserted (this module itself adds no extra pipeline latency — its output is combinational-from-register, available the same cycle it updates).

**Parameters:** `N=3`, `PIXEL_W=8`
**Key ports:** `pixel_in[7:0]`, `lb0_out[7:0]`, `lb1_out[7:0]`, `row_cnt`, `col_cnt` (in), `win_out[71:0]`, `shift_en`
**Instantiates:** `zero_pad_mux` (x4 — top, bottom, left, right border cells).

---

### 8. `mac_array`
**Function:**
Purely a fan-out/fan-in wrapper: unpacks the flattened 72-bit `win_in` and 72-bit `kernel_in` buses into 9 separate 8-bit operand pairs, feeds each pair into its own `mult_signed_unsigned` instance, and re-packs the 9 resulting 12-bit products into a single flattened 108-bit `prod_out` bus. There is no arithmetic performed in this module itself — all 9 multiplications happen inside the child instances in parallel on the same clock edge:
```
genvar k;
generate
  for (k = 0; k < 9; k = k+1) begin : gen_mult
    mult_signed_unsigned u_mult (
      .clk(clk), .rst_n(rst_n),
      .a_in(win_in[k*8 +: 8]),
      .b_in(kernel_in[k*8 +: 8]),
      .p_out(prod_out[k*12 +: 12])
    );
  end
endgenerate
```
`valid_out` is simply `valid_in` delayed by 1 cycle (matching the single register stage inside each `mult_signed_unsigned`), generated either locally or by an instance of `pipe_valid_shift_reg` with `DEPTH=1`.

**Parameters:** `N=3`, `PIXEL_W=8`, `KERNEL_W=8`, `PROD_W=12`
**Key ports:** `win_in[71:0]`, `kernel_in[71:0]`, `prod_out[9*12-1:0]`, `valid_in`, `valid_out`
**Instantiates:** `mult_signed_unsigned` (x9).

---

### 9. `adder_tree`
**Function:**
Sums the 9 products from `mac_array` using a balanced binary tree built entirely from `adder_2input` instances, structured in 4 pipelined levels so that no single combinational path ever adds more than 2 numbers before hitting a register — this is what keeps the critical path short and Fmax high. The tree is deliberately unbalanced at the very top (9 is not a power of 2), so one tap is folded in one level later than the rest; this asymmetry is normal and does not affect correctness as long as every path from a leaf product to the final sum passes through the same *number* of pipeline registers (padding the "odd one out" with a pass-through register at each level, not letting it skip ahead) — otherwise different taps would arrive at the final adder on different cycles, corrupting the result. Concretely:
```
Level 1 (4 real adds + 1 pass-through register): p0+p1, p2+p3, p4+p5, p6+p7, [p8 passed through a register]
Level 2 (2 real adds + 1 pass-through):          s0+s1, s2+s3,          [s4 passed through a register]
Level 3 (1 real add + 1 pass-through):            t0+t1,                 [t2 passed through a register]
Level 4 (1 real add, final):                      u0+u1  =  sum_out
```
The "pass-through register" at each level is important and easy to forget: it must be a real register (not a wire), instantiated as a trivial 1-input `adder_2input` with `b_in` tied to 0, or a plain DFF — otherwise that tap's data arrives one cycle early relative to the others at the next level, and the final sum will be silently wrong on some tap but not others (a bug that is very hard to catch without a golden-model bit-exact comparison, which is exactly why the spec requires one). `valid_out` is `valid_in` delayed by 4 cycles (one per tree level), generated via a `pipe_valid_shift_reg` instance with `DEPTH=4`.

**Parameters:** `NUM_TAPS=9`, `IN_W=12`, `OUT_W=16`
**Key ports:** `prod_in[9*12-1:0]`, `sum_out[15:0]` (signed, registered), `valid_in`, `valid_out`
**Instantiates:** `adder_2input` (x8 total across the 4 levels: 4+2+1+1).

---

## LEVEL 3 — Output Conditioning

### 10. `round_saturate_unit`
**Function:**
Converts the raw Q11.4 fixed-point sum from `adder_tree` into the final Q16.0 integer output pixel. Two operations happen here, and order matters: **round first, then saturate**. Rounding is a right-shift by `FRAC_BITS=4` with round-to-nearest (add 0.5 in the shifted-out units, i.e. add `1 << (FRAC_BITS-1)` before shifting, not simple truncation, which would introduce a systematic negative bias):
```
wire signed [15:0] rounded = (sum_in + (1 <<< (FRAC_BITS-1))) >>> FRAC_BITS;
```
Saturation then clamps this rounded value to the representable 16-bit signed range, which mainly matters if `SUM_W` were ever widened beyond 16 bits upstream (defensive coding) or if kernel coefficients larger than the assumed worst case are loaded:
```
wire signed [15:0] saturated =
    (rounded > 16'sd32767)  ? 16'sd32767  :
    (rounded < -16'sd32768) ? -16'sd32768 :
    rounded;
```
Both operations can be combined into a single always block with the result registered on `clk`, gated by `valid_in`, producing `pixel_out`/`valid_out` one cycle later. This is the **only** module in the datapath permitted to perform non-linear (min/max/round) operations — keeping this logic isolated here (rather than scattered across the adder tree) is what makes bit-exact golden-model verification tractable, since you only need to unit-test this one small module's rounding/saturation behavior in isolation.

**Parameters:** `SUM_W=16`, `FRAC_BITS=4`, `OUT_W=16`
**Key ports:** `sum_in[15:0]`, `valid_in`, `pixel_out[15:0]`, `valid_out`
**Instantiates:** None (leaf combinational + 1 register stage).

---

### 11. `relu_unit` *(optional/bonus)*
**Function:**
Applies `output = max(0, input)` by inspecting only the sign bit of the incoming 16-bit signed value — no comparator or subtraction needed, just a mux on `data_in[15]`:
```
always @(posedge clk or negedge rst_n)
  if (!rst_n)      data_out <= 0;
  else if (valid_in) data_out <= data_in[15] ? 16'sd0 : data_in;
```
Because this only reads the MSB, it costs effectively zero extra logic delay compared to a plain register, so it's a very cheap bonus feature to add once `round_saturate_unit` is working. `valid_out` is `valid_in` delayed by 1 cycle. If unused, this module is simply bypassed (`pixel_out = round_saturate_unit`'s output directly) with `ENABLE_RELU=0` at the top level.

**Parameters:** `DATA_W=16`
**Key ports:** `data_in[15:0]`, `valid_in`, `data_out[15:0]`, `valid_out`
**Instantiates:** None (leaf, 1-bit mux + register).

---

## LEVEL 4 — Control Plane

### 12. `row_col_counter`
**Function:**
Maintains the accelerator's notion of "where am I in the frame" — the single source of truth that every border-detection and end-of-frame decision derives from. Two counters increment on every cycle that `pixel_valid_in` is high: `col_cnt` increments each cycle and wraps to 0 when it reaches `IMG_W-1`, at which point `row_cnt` increments by one:
```
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    row_cnt <= 0; col_cnt <= 0;
  end else if (pixel_valid_in) begin
    if (col_cnt == IMG_W-1) begin
      col_cnt <= 0;
      row_cnt <= (row_cnt == IMG_H-1) ? row_cnt : row_cnt + 1;
    end else begin
      col_cnt <= col_cnt + 1;
    end
  end
end
```
Four combinational border flags are derived directly from these counters and fed to the `zero_pad_mux` instances: `is_top_row = (row_cnt == 0)`, `is_bottom_row = (row_cnt == IMG_H-1)`, `is_left_col = (col_cnt == 0)`, `is_right_col = (col_cnt == IMG_W-1)`. A `frame_end_flag` pulses combinationally when `row_cnt == IMG_H-1 && col_cnt == IMG_W-1 && pixel_valid_in`, which is exactly the condition `fsm_control` watches to transition `RUN → DRAIN`.

**Parameters:** `IMG_W=32`, `IMG_H=32`
**Key ports:** `pixel_valid_in`, `row_cnt_out`, `col_cnt_out`, `is_top_row`, `is_bottom_row`, `is_left_col`, `is_right_col`, `frame_end_flag`
**Instantiates:** None (leaf, two counters + comparators).

---

### 13. `drain_counter`
**Function:**
A simple free-running counter that only operates while the FSM is in `DRAIN`, counting how many "empty" cycles have elapsed since the last real pixel was consumed. Since the pipeline depth (`PIPE_DEPTH`) is a fixed, known constant, this counter doesn't need to watch any data signals — it just counts up to `PIPE_DEPTH-1` and asserts `drain_done`:
```
always @(posedge clk or negedge rst_n) begin
  if (!rst_n)            cnt <= 0;
  else if (!drain_en)    cnt <= 0;              // reset when not draining (ready for next frame)
  else if (cnt < PIPE_DEPTH-1) cnt <= cnt + 1;
end
assign drain_done = (cnt == PIPE_DEPTH-1);
```
While `drain_en` is asserted, the FSM should also make sure no *new* pixel is written into `line_buffer`/`window_reg_array` (i.e., `shift_en` should either stay low or shift in dummy zeros) — this counter only tracks time elapsed, it doesn't itself gate any datapath signals.

**Parameters:** `PIPE_DEPTH=6` (or 7 with ReLU)
**Key ports:** `drain_en`, `drain_done`
**Instantiates:** None (leaf counter).

---

### 14. `pipe_valid_shift_reg`
**Function:**
A parameterized shift register of flip-flops used purely to delay a 1-bit valid/enable pulse by a fixed number of cycles, so that a "this data is real" flag travels alongside the data through however many pipeline stages a given path has. Reused at multiple points (inside `mac_array`, `adder_tree`, and once more at the very top to generate the final `pixel_out_valid` from the original `pixel_valid`/`shift_en`):
```
reg [DEPTH-1:0] shift_reg;
always @(posedge clk or negedge rst_n)
  if (!rst_n)  shift_reg <= 0;
  else         shift_reg <= {shift_reg[DEPTH-2:0], valid_in};
assign valid_out = shift_reg[DEPTH-1];
```
Using one central, reusable, parameterized module for this (rather than hand-rolling ad-hoc delay chains in three different places) reduces the chance of an off-by-one cycle error, which is one of the most common sources of "output looks almost right but is shifted by 1 pixel" bugs in pipelined designs.

**Parameters:** `DEPTH` (instance-specific)
**Key ports:** `valid_in`, `valid_out`
**Instantiates:** None (leaf).

---

### 15. `fsm_control`
**Function:**
The top-level sequencer implementing the 5-state machine (`IDLE → FILL → RUN → DRAIN → DONE`) defined earlier. It does not perform any data movement itself — it only watches status flags (`frame_end_flag` from `row_col_counter`, `drain_done` from `drain_counter`, `col_cnt == IMG_W-1` during `FILL`) and drives the enable/control signals that every other module reacts to (`shift_en`, `drain_en`, `ready`, `frame_done`):
```
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= IDLE;
  else case (state)
    IDLE:  if (start_frame)                     state <= FILL;
    FILL:  if (col_cnt == IMG_W-1 && pixel_valid_in) state <= RUN;
    RUN:   if (frame_end_flag)                   state <= DRAIN;
    DRAIN: if (drain_done)                       state <= DONE;
    DONE:                                        state <= IDLE;   // single-cycle pulse, or wait for ack
    default: state <= IDLE;
  endcase
end
```
Output signals are simple combinational (Moore-style) functions of `state`: `ready = (state == IDLE)`, `shift_en = (state == FILL) || (state == RUN)` (note: also asserted during `FILL` so the first row gets written into `line_buffer_0`), `drain_en = (state == DRAIN)`, `frame_done = (state == DONE)`. Because `row_col_counter` and `drain_counter` are **siblings** of `fsm_control` at the top level (not children of it), `fsm_control` reads their outputs as inputs and its own outputs feed back into their enable ports — this creates a tight but well-defined combinational/sequential loop that must be drawn carefully in the top-level port map to avoid connecting the wrong direction.

**Parameters:** None (control-only)
**Key ports:** `start_frame`, `pixel_valid_in`, `frame_end_flag` (from `row_col_counter`), `drain_done_in`, `ready_out`, `frame_done_out`, `shift_en_out`, `drain_en_out`
**Instantiates:** None directly (consumes sibling outputs, does not own them).

---

## LEVEL 5 — Top-Level Integration

### 16. `conv_accel_top`
**Function:**
Wires every module above into the complete streaming pipeline and is where the exact cycle-alignment between the control path and the data path must be double-checked once all sub-modules are written. The overall data flow per accepted pixel is:
`pixel_in → line_buffer_0/1 (row delays, 0 extra pipeline cycles felt by window logic since BRAM read is same-cycle) → window_reg_array (assembles 3×3, 0 added latency beyond the register update itself) → mac_array (1 cycle) → adder_tree (4 cycles) → round_saturate_unit (1 cycle) → relu_unit (1 cycle, optional) → pixel_out`.//
The corresponding `valid` signal must be threaded through this exact same chain via `pipe_valid_shift_reg` instances (or the valid ports built into each module) so that `pixel_out_valid` asserts on precisely the cycle `pixel_out` becomes meaningful — off-by-one errors here are the most common integration bug and should be caught immediately by comparing against the golden model's very first few output pixels rather than waiting to check the whole frame. `fsm_control`'s `shift_en`/`drain_en` outputs gate `line_buffer` write-enables and `window_reg_array`'s shift-enable identically, ensuring the datapath and control path never desynchronize. During `DRAIN`, `shift_en` should be de-asserted for new external pixels but the pipeline registers inside `mac_array`/`adder_tree`/`round_saturate_unit` must still be allowed to continue clocking (just with `valid` propagating as 0) so the last real results flush out correctly — do not gate the clock or hold these registers during drain, only gate what data/valid enters the front of the pipe.

**Parameters:** `N`, `IMG_W`, `IMG_H`, `PIXEL_W`, `KERNEL_W`, `SUM_W`, `PIPE_DEPTH`, `ENABLE_RELU`
**Key ports:** `clk`, `rst_n`, `start_frame`, `pixel_in[7:0]`, `pixel_valid`, `pixel_out[15:0]`, `pixel_out_valid`, `frame_done`, `ready`
**Instantiates:**
`line_buffer` (x2), `kernel_loader` (x1 → `kernel_rom` x1), `window_reg_array` (x1 → `zero_pad_mux` x4), `mac_array` (x1 → `mult_signed_unsigned` x9), `adder_tree` (x1 → `adder_2input` x8), `round_saturate_unit` (x1), `relu_unit` (x1, optional), `row_col_counter` (x1), `drain_counter` (x1), `pipe_valid_shift_reg` (x1 or more), `fsm_control` (x1).

---

## VERIFICATION-SIDE MODULES *(not synthesized — testbench hierarchy)*

### 17. `image_rom`
**Function:** Stores test input pixels (from `.txt`/`.mem`, one value per line) and streams them out to `tb_conv_accel_top`, typically one pixel per clock while asserting `pixel_valid`, pausing/holding if the DUT ever needs backpressure (not required in this design since the accelerator never stalls mid-frame).

### 18. `expected_output_rom`
**Function:** Stores the golden-model's expected output values in the same order the DUT is expected to emit them, so `result_checker` can compare index-for-index against `pixel_out` as it streams out.

### 19. `golden_model` *(Python/MATLAB/C++, not RTL)*
**Function:** Performs the identical zero-padded 3×3 convolution in floating-point or matched fixed-point arithmetic, including the same rounding rule (round-to-nearest at 4 fractional bits) and saturation logic, so that a bit-exact (not just "close enough") comparison against the RTL is possible — this is worth emphasizing in your verification report since bit-exact matching is what the competition's correctness scoring likely expects.

### 20. `result_checker` / `scoreboard`
**Function:** Latches `pixel_out` whenever `pixel_out_valid` is high, compares it against the next expected value from `expected_output_rom`, and logs a pass/fail plus the exact frame coordinate of any mismatch (derived from an internal output-side pixel counter, separate from the DUT's internal `row_cnt`/`col_cnt` so the checker doesn't depend on DUT internals being exposed).

### 21. `tb_conv_accel_top`
**Function:** Instantiates the DUT (`conv_accel_top`) alongside `image_rom`, `expected_output_rom`, and `result_checker`; generates `clk`/`rst_n`, pulses `start_frame`, and lets the simulation run until `frame_done` is observed, then reports the scoreboard's final pass/fail tally.

---

## OPTIONAL BONUS MODULES

### 22. `kernel_select_mux`
**Function:** A simple address mux placed ahead of `kernel_rom`'s read port, letting `kernel_sel_in` (from a top-level input or a register) choose which of several pre-stored 9-coefficient sets is currently active — enables switching kernels between frames without needing to re-synthesize.

### 23. `edge_detect_wrapper`
**Function:** A thin top-level wrapper that instantiates `conv_accel_top` with a kernel input hard-wired (or ROM-initialized) to a Sobel or Laplacian coefficient set, intended purely as a demo target to show a recognizable edge-detected image output for the optional board demonstration.

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
