# SSCS 2026 — Edge-AI Vision Accelerator

FPGA-based NxN convolution accelerator for grayscale images.
Target: Zynq-7000 XC7Z020 (PYNQ-Z2).

## Features
- 3×3 convolution, stride = 1, valid (no padding)
- 8-bit unsigned input, 8-bit signed kernel
- 32-bit accumulator, 16-bit signed saturated output
- ReLU activation (bonus)
- Pipelined: 1 output pixel per cycle after fill
- Verified against Python golden model

## Folder layout
    images/    input image + generated hex files
    rtl/       Verilog sources
    tools/     Python scripts (preprocess, kernel gen, golden, show)
    run.bat    one-click build & simulate

## Prerequisites
- Python 3.8+ with `numpy`, `pillow`, `matplotlib`
- ModelSim (or Questa)
- Vivado 2020+ (optional, for synthesis)

## Quick start
    run.bat sobel_x

Or step by step:
    cd tools
    python preproccess.py
    python kernal_generation.py sobel_x
    python golden_model.py
    cd ..\rtl
    vlib work
    vlog rtl.v tb.v
    vsim -c tb -do "run -all; quit"
    cd ..\tools
    python show.py

Expected: `[PASS] Hardware matches golden!`

## Changing image size
Edit `IMG_SIZE` in:
- `rtl/rtl.v` (parameter)
- `rtl/tb.v`  (localparam)
- `tools/preproccess.py`, `golden_model.py`, `show.py`

## Kernel types
`sobel_x`, `sobel_y`, `gaussian`, `laplacian`, `box_blur`

## License
Academic project — SSCS Egypt 2026 competition.