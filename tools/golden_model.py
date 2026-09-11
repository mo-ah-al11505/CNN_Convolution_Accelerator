"""
golden_model.py
Reads  ../images/in.txt  and ../images/kern.txt
Writes ../images/out_gm.txt

Matches RTL: valid convolution, stride=1, no padding,
             saturate to 16-bit signed, ReLU applied.
"""
import numpy as np
import os

IMG_SIZE = 32   # <-- must match tb.v
USE_RELU = True
OUT_BITS = 16

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "..", "images")

def read_hex(path, bits):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(int(line, 16))
    arr = np.array(vals, dtype=np.int64)
    mask = (1 << bits) - 1
    sign = 1 << (bits - 1)
    return np.where(arr & sign, arr - (1 << bits), arr)

def sat(v, bits):
    lo = -(1 << (bits-1)); hi = (1 << (bits-1)) - 1
    return max(lo, min(int(v), hi))

def main():
    img = read_hex(os.path.join(IMAGES, "in.txt"), 8)
    krn = read_hex(os.path.join(IMAGES, "kern.txt"), 8)

    H = W = IMG_SIZE
    N = int(np.sqrt(krn.size))
    if img.size != H*W:
        print(f"[ERROR] in.txt has {img.size} pixels, expected {H*W}")
        return

    img = img.reshape((H, W))
    krn = krn.reshape((N, N))

    oh = H - N + 1
    ow = W - N + 1
    out = np.zeros((oh, ow), dtype=np.int64)

    for i in range(oh):
        for j in range(ow):
            acc = 0
            for ki in range(N):
                for kj in range(N):
                    acc += int(img[i+ki, j+kj]) * int(krn[ki, kj])
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