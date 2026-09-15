"""
preproccess.py
Reads ../images/in.jpg, converts to grayscale, resizes to
IMG_SIZE x IMG_SIZE, writes hex bytes to ../images/in.txt.
"""
import numpy as np
from PIL import Image
import os

IMG_SIZE = 32   # <-- change to match rtl.v/tb.v

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGES = os.path.join(HERE, "..", "images")

def main():
    img = Image.open(os.path.join(IMAGES, "in.jpg")).convert("L")
    img = img.resize((IMG_SIZE, IMG_SIZE), Image.LANCZOS)
    arr = np.array(img, dtype=np.uint8).flatten()

    out_path = os.path.join(IMAGES, "in.txt")
    with open(out_path, "w") as f:
        for v in arr:
            f.write(f"{v:02x}\n")

    print(f"[DONE] {IMG_SIZE}x{IMG_SIZE} -> {out_path} ({arr.size} bytes)")

if __name__ == "__main__":
    main()