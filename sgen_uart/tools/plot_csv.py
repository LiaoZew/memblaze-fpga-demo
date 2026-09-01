#!/usr/bin/env python3
"""Plot a CSV captured from the sgen_uart JTAG UART.

Usage:
    python plot_csv.py data.csv            # simple
    python plot_csv.py data.csv -o wave.png

Input format (printed by the MicroBlaze firmware):
    index,value
    0,3212
    1,6393
    ...
"""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def main():
    src = sys.argv[1]
    out = None
    if "-o" in sys.argv:
        out = sys.argv[sys.argv.index("-o") + 1]

    idx, val = [], []
    with open(src, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("==="):
                continue
            try:
                i, v = line.split(",")
                idx.append(int(i))
                val.append(int(v))
            except ValueError:
                continue

    if not val:
        print("no data in %s" % src)
        return 1

    plt.figure(figsize=(10, 4))
    plt.plot(idx, val, "-", linewidth=1)
    plt.xlabel("sample")
    plt.ylabel("16-bit value")
    plt.title("sgen_uart waveform (%d samples)" % len(val))
    plt.grid(True)
    if out:
        plt.savefig(out, dpi=150)
        print("saved", out)
    else:
        plt.savefig("waveform.png", dpi=150)
        print("saved waveform.png")
    return 0

if __name__ == "__main__":
    sys.exit(main())