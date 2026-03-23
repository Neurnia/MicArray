#!/usr/bin/env python3
"""Capture one UART-exported window payload and save raw bytes."""

import argparse
import time
from pathlib import Path

import serial

HEADER_BYTES = bytes((0xA5, 0x5A))
WORD_BYTES = 2
DEFAULT_BAUD = 921600
DEFAULT_READ_CHUNK = 1024
DEFAULT_SERIAL_TIMEOUT = 0.1
DEFAULT_IDLE_TIMEOUT = 20.0
DEFAULT_WINDOW_LENGTH = 160000


class PartialReadTimeout(TimeoutError):
    """Timeout while collecting a fixed-length payload."""

    def __init__(self, expected_bytes, data):
        self.expected_bytes = expected_bytes
        self.data = bytes(data)
        super().__init__(
            f"Timed out while waiting for {expected_bytes} bytes "
            f"(received {len(self.data)} bytes)."
        )


def read_exact(ser, byte_count, idle_timeout):
    """Read exactly byte_count bytes or raise TimeoutError."""
    data = bytearray()
    last_data_time = time.time()

    while len(data) < byte_count:
        chunk = ser.read(min(DEFAULT_READ_CHUNK, byte_count - len(data)))
        now = time.time()

        if chunk:
            data.extend(chunk)
            last_data_time = now
        elif now - last_data_time > idle_timeout:
            raise PartialReadTimeout(byte_count, data)

    return bytes(data)


def wait_for_header(ser, idle_timeout):
    """Scan the serial stream until the 0xA55A header is found."""
    sync = bytearray()
    last_data_time = time.time()

    while True:
        byte = ser.read(1)
        now = time.time()

        if byte:
            last_data_time = now
            sync += byte
            if len(sync) > len(HEADER_BYTES):
                del sync[0]
            if bytes(sync) == HEADER_BYTES:
                return
        elif now - last_data_time > idle_timeout:
            raise TimeoutError("Timed out while waiting for UART header 0xA55A.")


def main():
    ap = argparse.ArgumentParser(
        description="Capture one UART-exported window payload and save raw bytes."
    )
    ap.add_argument(
        "-p",
        "--port",
        required=True,
        help="UART port (for example COM3 or /dev/ttyUSB0)",
    )
    ap.add_argument(
        "-b",
        "--baud",
        type=int,
        default=DEFAULT_BAUD,
        help=f"Baud rate (default: {DEFAULT_BAUD})",
    )
    ap.add_argument(
        "-o",
        "--output",
        default="capture.bin",
        help="Output file for raw payload bytes (default: capture.bin)",
    )
    ap.add_argument(
        "-w",
        "--window-length",
        type=int,
        default=DEFAULT_WINDOW_LENGTH,
        help=f"Frame count per window (default: {DEFAULT_WINDOW_LENGTH})",
    )
    ap.add_argument(
        "-t",
        "--idle-timeout",
        type=float,
        default=DEFAULT_IDLE_TIMEOUT,
        help=f"Abort if no data arrives for this many seconds (default: {DEFAULT_IDLE_TIMEOUT})",
    )
    args = ap.parse_args()

    output_path = Path(args.output)
    if output_path.exists():
        output_path.unlink()

    print(f"Listening on {args.port} @ {args.baud} ...")

    with serial.Serial(args.port, args.baud, timeout=DEFAULT_SERIAL_TIMEOUT) as ser:
        wait_for_header(ser, args.idle_timeout)

        frame_words_bytes = read_exact(ser, WORD_BYTES, args.idle_timeout)
        frame_words = int.from_bytes(frame_words_bytes, byteorder="big")
        if frame_words == 0:
            raise ValueError("frame_words from UART prefix must be non-zero.")

        payload_bytes = args.window_length * frame_words * WORD_BYTES
        try:
            payload = read_exact(ser, payload_bytes, args.idle_timeout)
        except PartialReadTimeout as exc:
            output_path.write_bytes(exc.data)
            print("Payload reception timed out.")
            print(f"frame_words: {frame_words}")
            print(f"window_length: {args.window_length}")
            print(f"received_bytes: {len(exc.data)}")
            print(f"expected_bytes: {exc.expected_bytes}")
            print(f"partial_output: {output_path}")
            raise

    output_path.write_bytes(payload)

    print("Captured one window.")
    print(f"frame_words: {frame_words}")
    print(f"window_length: {args.window_length}")
    print(f"payload_bytes: {payload_bytes}")
    print(f"output: {output_path}")


if __name__ == "__main__":
    main()
