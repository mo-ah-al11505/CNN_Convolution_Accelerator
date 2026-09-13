## 1. Kernel size — N = 3 (3×3)

**Choice:** Fixed at 3×3, but write the RTL parameterized (`parameter N = 3`) so you can claim "configurable kernel size" as a bonus almost for free.

**Why:**
- 3×3 is the sweet spot for the FOM: MAC tree cost grows as N², line buffers grow as N−1. Going to 5×5 triples resource usage (25 vs 9 multipliers, 4 vs 2 line buffers) for a competition where the FOM rewards efficiency.
- Classic edge-AI kernels (Sobel, Laplacian, Gaussian blur, most CNN first-layer filters) are 3×3 — this also directly supports the bonus "edge-detection/industrial-inspection demo."
- Parameterizing the Verilog (generate loops for the MAC tree and line buffers) costs little extra effort and lets you argue scalability in the report without paying the resource cost of building for 5×5.

## 2. Input image / feature-map size — 32×32, parameterizable

**Choice:** Meet the minimum (32×32), but drive row/column counters off `parameter IMG_W, IMG_H` so you can demo at other resolutions.

**Why:** 32×32 is the smallest reasonable size, minimizing BRAM for line buffers while still being non-trivial to verify (real windowing edge effects at borders). Larger sizes only add BRAM depth, not new design complexity, so parameterizing it is low-risk and shows design maturity to judges.

## 3. Input precision — 8-bit unsigned, Q8.0 (i.e. plain integer 0–255)

**Choice:** `UQ8.0`, no fractional bits.

**Why:**
- Grayscale pixels are natively 0–255 (standard 8-bit image format), so Q8.0 needs zero conversion/quantization logic — directly matches your test images.
- Unsigned is required by the spec anyway.
- Using fractional bits here would only matter if you were feeding normalized activations (0–1.0); for a spec that explicitly says "grayscale image or feature map," raw 8-bit pixels are the cleaner, more defensible assumption. State this clearly in your "assumptions" section.

## 4. Kernel precision — 8-bit signed, Q3.4 (sign + 3 integer bits + 4 fractional bits)

**Choice:** `SQ3.4` (range −8.0 to +7.9375, resolution 0.0625), not plain integer Q7.0.

**Why:**
- The spec mandates 8-bit signed, but *how* you split integer/fractional bits is your design decision — and you must justify it.
- Real 3×3 kernels (Sobel: ±1,±2,±4; Laplacian: ±1,±4,±8; Gaussian: fractional weights summing to 1) need both a bit of headroom above ±1 *and* fractional resolution for smoothing kernels. Q3.4 covers both cases — magnitude up to 8 and 1/16 resolution — better than plain integer (which loses all fractional kernels) or something like Q1.6 (range only ±2, too small for Laplacian's ±8 taps).
- This choice also gives you an easy "trade-off discussion" paragraph for the report, which judges reward.

## 5. Output precision — 16-bit signed, Q3.4-consistent accumulator

**Choice:** 16-bit signed integer accumulator, **with saturation** (not wraparound), no fractional bits carried in the final output (round/truncate after MAC).

**Why (worst-case bit-growth math — put this directly in your report):**
- Max input pixel = 255 (8-bit unsigned)
- Max kernel coefficient magnitude in Q3.4 ≈ 8 → product magnitude ≈ 255 × 8 = 2040 → needs ⌈log2(2040)⌉ + 1 sign bit ≈ 12 bits per product
- Summing 9 products (3×3): worst case ≈ 2040 × 9 = 18360 → needs 15 bits signed (2^15 = 32768 covers it) plus the sign bit
- **16-bit signed gives you ~2× headroom over the theoretical worst case** — meets the spec minimum exactly while leaving margin, so you don't need saturation logic to trigger in normal operation, only as a safety net (which you should still implement and explicitly test, since the spec asks for it).
- Rounding: since kernel is Q3.4 (4 fractional bits) and input is Q8.0, the raw product is naturally Q11.4. You right-shift by 4 (round-to-nearest, not truncate — costs 1 extra adder, negligible area) before packing into the 16-bit signed output. Document this shift+round step explicitly — judges are told to check exactly this.

## 6. Stride — 1 (fixed, per spec)

No design decision needed here, just implement it directly in the window-generation control logic.

## 7. Architecture parameters (Line Buffer + Pipelined MAC Tree specifics)

| Parameter | Choice | Justification |
|---|---|---|
| Line buffers | N−1 = 2, implemented in BRAM (shift-register-style, using dual-port or simple FIFO) | Standard sliding-window technique; BRAM is far cheaper than LUT-based shift registers for row-length buffers, directly helps your FOM (BRAM weighted 100× in the denominator, but 2 small BRAMs still beats N·row_width flip-flops) |
| Window register | 3×3 register array (9 regs) fed from line buffers + new pixel | Standard, minimal control complexity |
| Multiplier stage | 9 parallel signed×unsigned multipliers (fully combinational or 1-cycle pipelined) | Parallelism is what gives you 1 output/cycle throughput — required for the "one-output-pixel-per-cycle" bonus |
| Adder tree depth | ⌈log2(9)⌉ = 4 stages (e.g., 9→5→3→2→1, pad with zero where needed) | Balanced tree minimizes critical path vs. a linear accumulator chain, improving Fmax and therefore throughput in the FOM |
| Pipeline stages (total) | 1 (multiply) + 4 (adder tree) + 1 (output register/round-saturate) = **6 stages** | Each stage is registered to keep critical path short (one multiply or one 2-input add per stage) — this is what lets you push Fmax high, which is the main lever you control in the FOM's numerator (throughput) without touching the denominator (LUTs/DSPs/BRAMs) |
| ReLU (bonus) | Optional 7th pipeline stage: simple sign-bit mux (output = data[15] ? 0 : data) | Costs 1 comparator, no DSPs/BRAMs — cheap bonus points since FOM denominator barely moves |

## 8. Control FSM

Simple 3-state FSM is enough: `FILL` (loading first N−1 rows into line buffers, no valid output), `RUN` (steady-state, 1 pixel/cycle output), `DRAIN` (flush pipeline at end of frame). Keep it this simple — a more complex FSM only adds LUTs without helping FOM or correctness.

---

**Quick summary table for your Table 1 draft:**

| Parameter | Value |
|---|---|
| Kernel size N | 3×3 (parameterizable) |
| Input image size | 32×32 (parameterizable) |
| Input precision | UQ8.0 (8-bit unsigned) |
| Kernel precision | SQ3.4 (8-bit signed) |
| Output precision | 16-bit signed, saturating, round-to-nearest |
| Stride | 1 |
| Architecture | line buffer + parallel pipelined MAC tree |
| Multipliers/MACs | 9 parallel |
| Pipeline stages | 6 (7 with ReLU) |
| Architecture type | Line buffer + parallel pipelined MAC tree |


#

Here's the block diagram in text form, structured top-down: system-level view first, then a detailed datapath view, then the control-plane view.

## 1. System-Level Block Diagram

```
                         ┌──────────────────────────────────────────────┐
                         │              TOP: CONV_ACCEL_3x3              │
                         │                                                │
  pixel_in[7:0] ───────▶│  ┌───────────────┐                            │
  pixel_valid  ───────▶│  │  LINE BUFFER   │                            │
                         │  │  (Row Storage) │                            │
                         │  └───────┬───────┘                            │
                         │          │ 3 row streams                      │
                         │          ▼                                    │
                         │  ┌───────────────┐        ┌────────────────┐ │
  kernel_coeffs[8*8-1:0]─▶│  │ WINDOW REG     │──────▶│  MAC ARRAY     │ │
  kernel_load    ───────▶│  │ (3x3 sliding)  │       │  (9 parallel   │ │
                         │  └───────┬───────┘        │   mult+add)    │ │
                         │          │                └───────┬────────┘ │
                         │          │                        ▼          │
                         │          │                ┌────────────────┐ │
                         │          │                │  ADDER TREE    │ │
                         │          │                │  (4-stage,     │ │
                         │          │                │   pipelined)   │ │
                         │          │                └───────┬────────┘ │
                         │          │                        ▼          │
                         │          │                ┌────────────────┐ │
                         │          │                │ ROUND/SATURATE │ │
                         │          │                │  Q11.4 → Q16.0 │ │
                         │          │                └───────┬────────┘ │
                         │          │                        ▼          │
                         │          │                ┌────────────────┐ │
                         │          │                │ ReLU (optional)│ │
                         │          │                └───────┬────────┘ │
                         │          │                        ▼          │
                         │          │                                pixel_out[15:0]
                         │          │                                        │
                         │          │                                        ▼
                         │          │                                 pixel_out_valid
                         │          ▼                                                │
                         │  ┌────────────────────────────────────────────┐          │
                         │  │           CONTROL FSM + COUNTERS            │          │
                         │  │  (FILL / RUN / DRAIN, row/col address gen)  │◀─────────┘
                         │  └────────────────────────────────────────────┘
                         │                                                │
                         └──────────────────────────────────────────────┘

  clk, rst_n ─────────────────────────────▶ (global, all blocks)
```

## 2. Detailed Datapath: Line Buffer → Window Generator

```
 pixel_in ──┬──────────────────────────────────────────────────► win[0][2] (newest col, row 0)
            │
            ▼
    ┌───────────────┐
    │  LINE BUF 0    │  (BRAM, depth = IMG_W, width = 8)
    │  (delays 1 row)│
    └───────┬────────┘
            ├──────────────────────────────────────────────────► win[1][2] (row 1)
            ▼
    ┌───────────────┐
    │  LINE BUF 1    │  (BRAM, depth = IMG_W, width = 8)
    │  (delays 1 row)│
    └───────┬────────┘
            └──────────────────────────────────────────────────► win[2][2] (row 2, oldest)

        WINDOW SHIFT REGISTER (3x3, updates every valid pixel clock):

        ┌─────────┬─────────┬─────────┐
        │ win[0][0]│ win[0][1]│ win[0][2]│ ◀── row 0 (current line buffer 0 output)
        ├─────────┼─────────┼─────────┤
        │ win[1][0]│ win[1][1]│ win[1][2]│ ◀── row 1 (line buffer 1 output)
        ├─────────┼─────────┼─────────┤
        │ win[2][0]│ win[2][1]│ win[2][2]│ ◀── row 2 (line buffer 2 output, i.e. LB1 output delayed)
        └─────────┴─────────┴─────────┘
              │         │         │
              (each cell shifts right→left as new column arrives)
```

## 3. Detailed Datapath: MAC Array → Adder Tree → Output Stage

```
 win[i][j] (9 pixels, UQ8.0)         kernel[i][j] (9 coeffs, SQ3.4, loaded/held in regs)
      │                                    │
      ▼                                    ▼
 ┌─────────────────────────────────────────────────────┐
 │  MULTIPLY STAGE (Pipeline Stage 1)                    │
 │  p00=win00*k00  p01=win01*k01  p02=win02*k02          │
 │  p10=win10*k10  p11=win11*k11  p12=win12*k12          │
 │  p20=win20*k20  p21=win21*k21  p22=win22*k22          │
 │  (9x signed x unsigned multipliers, each → Q11.4)     │
 └───────────────────────┬───────────────────────────────┘
                          ▼
 ┌─────────────────────────────────────────────────────┐
 │  ADDER TREE (Pipeline Stages 2-5, registered/level)   │
 │                                                        │
 │  Level 1 (4 adds):  s0=p00+p01  s1=p02+p10  s2=p11+p12│
 │                     s3=p20+p21                        │
 │  Level 2 (2 adds):  t0=s0+s1    t1=s2+s3               │
 │  Level 3 (1 add):   u0=t0+t1                           │
 │  Level 4 (1 add):   sum = u0 + p22   (9th term folded in)│
 └───────────────────────┬───────────────────────────────┘
                          ▼
 ┌─────────────────────────────────────────────────────┐
 │  ROUND + SATURATE (Pipeline Stage 6)                  │
 │  - shift right 4 (drop fractional bits, round-to-nearest)│
 │  - saturate to [-32768, 32767] (16-bit signed)        │
 └───────────────────────┬───────────────────────────────┘
                          ▼
 ┌─────────────────────────────────────────────────────┐
 │  ReLU (Pipeline Stage 7, optional/bonus)              │
 │  out = sum[15] ? 16'd0 : sum                          │
 └───────────────────────┬───────────────────────────────┘
                          ▼
                   pixel_out[15:0]
                   pixel_out_valid
```

## 4. Control Plane: FSM + Address Generation

```
 ┌─────────────────────────────────────────────────────────┐
 │                     CONTROL FSM                           │
 │                                                             │
 │      ┌───────┐  (N-1)*IMG_W       ┌───────┐              │
 │      │ FILL  │───pixels loaded──▶ │  RUN  │              │
 │      │(load  │                    │(steady│              │
 │      │2 rows)│                    │state, │              │
 │      └───────┘                    │1 px/  │              │
 │          ▲                        │cycle  │              │
 │          │                        │output)│              │
 │          │                        └───┬───┘              │
 │          │                            │ last pixel        │
 │          │                            │ of frame          │
 │          │                            ▼                   │
 │          │                        ┌───────┐              │
 │          └────next frame──────────│ DRAIN │              │
 │                                    │(flush │              │
 │                                    │6-stage│              │
 │                                    │pipe)  │              │
 │                                    └───────┘              │
 └─────────────────────────────────────────────────────────┘
        │                    │
        ▼                    ▼
 ┌─────────────┐    ┌──────────────────┐
 │ ROW/COL      │    │  valid_out gen    │
 │ COUNTERS     │    │  (delayed by 6    │
 │ (track write │    │   cycles to match │
 │  position &  │    │   pipeline depth) │
 │  window edge │    └──────────────────┘
 │  handling)   │
 └─────────────┘
```

### Notes on the diagram / design decisions embedded in it
- **Edge/border handling** isn't shown explicitly above — you'll need to decide (and state as an assumption) whether border pixels are zero-padded or simply not output (valid-only output for the interior (N−2)×(N−2)... actually (IMG_W−2)×(IMG_H−2) region). Zero-padding is more common for CNN edge accelerators and keeps output size = input size, which I'd recommend since it's a cleaner comparison against the golden model.
- The **6-stage pipeline** (1 multiply + 4 adder-tree levels + 1 round/saturate, +1 optional ReLU) matches what we set in the parameter table — `pixel_out_valid` needs to be a shift register of `pixel_valid` delayed by exactly this many cycles.
- Kernel coefficients are assumed **static per frame** (loaded once via `kernel_load`, held in registers) — reloading mid-frame would need extra synchronization, which is unnecessary complexity for this spec.

Want me to move next to the FSM state diagram in more formal (state/transition table) form, or start drafting the actual Verilog module hierarchy that matches these blocks?