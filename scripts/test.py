#!/usr/bin/env python3
# Read raw PCM frames over UART and save as 24-bit little-endian PCM file.
import argparse
import serial
import time
from pathlib import Path

HEADER = 0xA5
TAIL   = 0x0A
FRAME_LEN = 5  # A5, 3 data, 0A

def main():
    ap = argparse.ArgumentParser(description="Read raw PCM frames over UART and save 24-bit LE PCM.")
    ap.add_argument("-p", "--port", required=True, help="UART port (e.g., COM3 or /dev/ttyUSB0)")
    ap.add_argument("-b", "--baud", type=int, default=921600, help="Baud rate (default: 921600)")
    ap.add_argument("-o", "--output", default="capture.pcm", help="Output PCM file (24-bit LE, mono)")
    ap.add_argument("-t", "--timeout", type=float, default=8.0, help="Stop if no data for this many seconds")
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.1)
    buf = bytearray()
    last_data_time = time.time()

    print(f"Listening on {args.port} @ {args.baud} ...")

    try:
        while True:
            chunk = ser.read(1024)
            now = time.time()
            if chunk:
                last_data_time = now
                buf.extend(chunk)
                # Parse frames in-stream
                parsed = bytearray()
                i = 0
                while i + FRAME_LEN <= len(buf):
                    if buf[i] != HEADER:
                        i += 1
                        continue
                    if buf[i + 4] != TAIL:
                        i += 1
                        continue
                    # data bytes: MSB, mid, LSB (UART order). Convert to little-endian for PCM.
                    msb = buf[i + 1]
                    mid = buf[i + 2]
                    lsb = buf[i + 3]
                    parsed.extend((lsb, mid, msb))
                    i += FRAME_LEN
                # trim processed bytes
                if i:
                    del buf[:i]
                if parsed:
                    # append to file immediately to avoid RAM bloat
                    with open(args.output, "ab") as f:
                        f.write(parsed)
            else:
                if now - last_data_time > args.timeout:
                    print(f"No data for {args.timeout}s, stopping.")
                    break
    finally:
        ser.close()

    size = Path(args.output).stat().st_size if Path(args.output).exists() else 0
    samples = size // 3
    print(f"Wrote {size} bytes ({samples} samples) to {args.output}")

if __name__ == "__main__":
    main()
