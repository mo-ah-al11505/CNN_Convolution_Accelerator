"""
show.py
Displays input / golden / hardware side by side and prints PASS/FAIL.
"""
import os
import numpy as np
import matplotlib.pyplot as plt

IMG_SIZE = 32

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "..", "images")

def read_hex(path, bits=16):
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

def main():
    img = read_hex(os.path.join(IMAGES, "in.txt"), 8).reshape(IMG_SIZE, IMG_SIZE)
    gm  = read_hex(os.path.join(IMAGES, "out_gm.txt"), 16)
    hw  = read_hex(os.path.join(IMAGES, "out_hw.txt"), 16)

    oh = IMG_SIZE - 2
    ow = IMG_SIZE - 2
    gm = gm.reshape(oh, ow)
    hw = hw.reshape(oh, ow)

    n = min(gm.size, hw.size)
    mismatches = int(np.sum(gm.flatten()[:n] != hw.flatten()[:n]))
    if gm.size != hw.size:
        print(f"[FAIL] sizes differ: gm={gm.size}, hw={hw.size}")
    elif mismatches == 0:
        print("[PASS] Hardware matches golden!")
    else:
        print(f"[FAIL] {mismatches} mismatches")

    fig, ax = plt.subplots(1, 3, figsize=(12, 4))
    ax[0].imshow(img, cmap='gray');    ax[0].set_title("Input")
    ax[1].imshow(gm,  cmap='gray');    ax[1].set_title("Golden")
    ax[2].imshow(hw,  cmap='gray');    ax[2].set_title("Hardware")
    for a in ax: a.axis('off')
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    main()