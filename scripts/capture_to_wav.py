from __future__ import annotations

import argparse
import struct
import wave
from pathlib import Path


DEFAULT_SAMPLE_RATE = 16000
DEFAULT_FRAME_WORDS = 3
DEFAULT_CHANNELS = 2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert MicArray capture.bin payload into a stereo WAV file."
    )
    parser.add_argument(
        "-i",
        "--input",
        type=Path,
        default=Path("capture.bin"),
        help="Input raw payload file captured by scripts/test.py (default: capture.bin)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output WAV path (default: <input>.wav)",
    )
    parser.add_argument(
        "-r",
        "--sample-rate",
        type=int,
        default=DEFAULT_SAMPLE_RATE,
        help="Sample rate in Hz (default: 16000)",
    )
    parser.add_argument(
        "--frame-words",
        type=int,
        default=DEFAULT_FRAME_WORDS,
        help="Words per frame in the payload, including the error word (default: 3)",
    )
    parser.add_argument(
        "--channels",
        type=int,
        default=DEFAULT_CHANNELS,
        help="Number of audio channels to export (default: 2)",
    )
    parser.add_argument(
        "--keep-error-frames",
        action="store_true",
        help="Keep channel samples even if the frame error word is non-zero",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    input_path = args.input
    output_path = args.output or input_path.with_suffix(".wav")

    if args.frame_words < args.channels + 1:
        raise ValueError("frame_words must cover one error word plus all requested channels.")
    if args.sample_rate <= 0:
        raise ValueError("sample_rate must be positive.")

    raw = input_path.read_bytes()
    bytes_per_frame = args.frame_words * 2
    if len(raw) % bytes_per_frame != 0:
        raise ValueError(
            f"Input size {len(raw)} is not a multiple of one frame ({bytes_per_frame} bytes)."
        )

    frame_count = len(raw) // bytes_per_frame
    all_words = struct.unpack(f">{frame_count * args.frame_words}h", raw)

    pcm = bytearray()
    error_frames = 0

    for frame_idx in range(frame_count):
        base = frame_idx * args.frame_words
        error_word = all_words[base]
        samples = list(all_words[base + 1 : base + 1 + args.channels])
        if error_word != 0:
            error_frames += 1
            if not args.keep_error_frames:
                samples = [0] * args.channels
        pcm.extend(struct.pack("<" + "h" * args.channels, *samples))

    with wave.open(str(output_path), "wb") as wav_file:
        wav_file.setnchannels(args.channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(args.sample_rate)
        wav_file.writeframes(pcm)

    print(f"input: {input_path}")
    print(f"output: {output_path}")
    print(f"sample_rate: {args.sample_rate}")
    print(f"channels: {args.channels}")
    print(f"frame_count: {frame_count}")
    print(f"duration_seconds: {frame_count / args.sample_rate:.3f}")
    print(f"error_frames: {error_frames}")


if __name__ == "__main__":
    main()
