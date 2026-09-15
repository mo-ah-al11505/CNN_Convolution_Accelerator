"""
kernal_generation.py
Generates a 3x3 kernel and writes to ../images/kern.txt.

Usage:
    python kernal_generation.py <type>

Types: gaussian, sobel_x, sobel_y, laplacian, box_blur
"""
import sys
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "..", "images")

def make(ktype):
    if ktype == "gaussian":
        # 3x3 Gaussian (sigma ~ 0.85), scaled to sum 16
        k = np.array([[1, 2, 1],
                      [2, 4, 2],
                      [1, 2, 1]], dtype=int)
    elif ktype == "sobel_x":
        k = np.array([[-1, 0, 1],
                      [-2, 0, 2],
                      [-1, 0, 1]], dtype=int)
    elif ktype == "sobel_y":
        k = np.array([[-1, -2, -1],
                      [ 0,  0,  0],
                      [ 1,  2,  1]], dtype=int)
    elif ktype == "laplacian":
        k = np.array([[ 0,  1,  0],
                      [ 1, -4,  1],
                      [ 0,  1,  0]], dtype=int)
    elif ktype == "box_blur":
        k = np.ones((3, 3), dtype=int)
    else:
        raise ValueError(f"unknown kernel: {ktype}")
    return k

def main():
    ktype = sys.argv[1] if len(sys.argv) > 1 else "sobel_x"
    k = make(ktype)
    print(f"[INFO] kernel = {ktype}")
    print(k)

    out_path = os.path.join(IMAGES, "kern.txt")
    with open(out_path, "w") as f:
        for v in k.flatten():
            f.write(f"{int(v) & 0xff:02x}\n")
    print(f"[DONE] 3x3 {ktype} -> {out_path}")

if __name__ == "__main__":
    main()