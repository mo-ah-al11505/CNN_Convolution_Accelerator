"""
golden_model.py
Reads  ../images/in.txt  and ../images/kern.txt
Writes ../images/out_gm.txt

Matches RTL (conv_accel_top): valid convolution (interior-only, no padding),
stride=1, FRAC_BITS=0 by default (plain-integer kernel, no rounding shift),
saturate to 16-bit signed, optional ReLU.

FIXED vs. original version: the image (pixel) values are UNSIGNED (UQ8.0,
range 0-255) and must be read as such. The original read_hex() treated
EVERY value (image included) as signed two's complement, which silently
corrupted any pixel >= 128 - the exact same class of bug found in the
RTL's mult_signed_unsigned module (unsigned operand needs zero-extension,
not a raw sign-bit reinterpretation). Kernel coefficients ARE signed and
still use the signed reader.
"""
import numpy as np
import os

IMG_SIZE  = 32     # <-- must match tb.v / conv_accel_top's IMG_W/IMG_H
USE_RELU  = True   # <-- must match conv_accel_top's ENABLE_RELU parameter
OUT_BITS  = 16
FRAC_BITS = 0      # <-- must match conv_accel_top's FRAC_BITS parameter
                   #     0 = plain-integer kernel (no shift, matches current RTL decision)

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "..", "images")

def read_unsigned_hex(path, bits):
    """For UNSIGNED data (image pixels). No sign-bit reinterpretation."""
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(int(line, 16))
    return np.array(vals, dtype=np.int64)

def read_signed_hex(path, bits):
    """For SIGNED two's-complement data (kernel coefficients)."""
    arr = read_unsigned_hex(path, bits)
    mask = (1 << bits) - 1
    sign = 1 << (bits - 1)
    return np.where(arr & sign, arr - (1 << bits), arr)

def round_shift(v, frac_bits):
    """Round-to-nearest right shift, matching RTL's (v + half) >>> frac_bits.
    Python's native '>>' on ints already performs floor division (arithmetic
    shift) for negative values, so no special-casing is needed here."""
    if frac_bits == 0:
        return v
    half = 1 << (frac_bits - 1)
    return (v + half) >> frac_bits

def sat(v, bits):
    lo = -(1 << (bits-1)); hi = (1 << (bits-1)) - 1
    return max(lo, min(int(v), hi))

def main():
    img = read_unsigned_hex(os.path.join(IMAGES, "in.txt"), 8)   # UQ8.0, 0..255
    krn = read_signed_hex(os.path.join(IMAGES, "kern.txt"), 8)   # signed 8-bit

    H = W = IMG_SIZE
    N = int(np.sqrt(krn.size))
    if img.size != H*W:
        print(f"[ERROR] in.txt has {img.size} pixels, expected {H*W}")
        return

    img = img.reshape((H, W))
    krn = krn.reshape((N, N))

    oh = H - N + 1   # interior-only output (no zero padding) - matches window_generator
    ow = W - N + 1
    out = np.zeros((oh, ow), dtype=np.int64)

    for i in range(oh):
        for j in range(ow):
            acc = 0
            for ki in range(N):
                for kj in range(N):
                    acc += int(img[i+ki, j+kj]) * int(krn[ki, kj])
            acc = round_shift(acc, FRAC_BITS)
            out[i, j] = sat(acc, OUT_BITS)

    if USE_RELU:
        out = np.maximum(out, 0)

    mask = (1 << OUT_BITS) - 1
    out_path = os.path.join(IMAGES, "out_gm.txt")
    with open(out_path, "w") as f:
        for v in out.flatten():
            f.write(f"{int(v) & mask:04x}\n")

    print(f"[DONE] out_gm.txt  shape={out.shape}  range=[{out.min()}, {out.max()}]")

if __name__ == "__main__":
    main()
