#!/usr/bin/env python3
"""Convert a WAV audio file or generate a synthetic sound sample into a .mem file for FPGA BRAM."""

import argparse
import math
import struct
import sys
import wave
from pathlib import Path


def generate_synth_chime(sample_count: int = 4096, sample_rate: int = 48000) -> list[int]:
    """Generate a high-quality decaying acoustic chime (A4 440 Hz + harmonics).

    Returns list of 16-bit unsigned PCM integers (0..65535, center=32768).
    """
    samples = []
    # Fundamental: 440 Hz, Overtone 1: 880 Hz, Overtone 2: 1320 Hz
    for i in range(sample_count):
        t = i / sample_rate
        # Exponential decay envelope
        env = math.exp(-3.5 * (i / sample_count))
        # Add slight attack ramp (first 64 samples)
        if i < 64:
            env *= i / 64.0

        f1 = math.sin(2.0 * math.pi * 440.0 * t) * 0.60
        f2 = math.sin(2.0 * math.pi * 880.0 * t) * 0.25
        f3 = math.sin(2.0 * math.pi * 1320.0 * t) * 0.15

        val_norm = (f1 + f2 + f3) * env  # range roughly -1.0 .. +1.0
        val_norm = max(-1.0, min(1.0, val_norm))

        # Convert to 16-bit unsigned offset-binary (0..65535, 32768 is zero)
        pcm_u16 = int(round(32768 + val_norm * 32000))
        pcm_u16 = max(0, min(65535, pcm_u16))
        samples.append(pcm_u16)
    return samples


def load_wav(path: Path, max_samples: int = 4096) -> list[int]:
    """Read a WAV file and convert to 16-bit unsigned PCM samples."""
    with wave.open(str(path), 'rb') as wf:
        num_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        num_frames = min(wf.getnframes(), max_samples)
        raw_data = wf.readframes(num_frames)

    samples = []
    frame_size = num_channels * sampwidth
    for i in range(num_frames):
        frame = raw_data[i * frame_size : (i + 1) * frame_size]
        # Extract first channel
        if sampwidth == 1:
            # 8-bit unsigned
            val = frame[0]
            val_u16 = val << 8
        elif sampwidth == 2:
            # 16-bit signed
            val_s16 = struct.unpack('<h', frame[:2])[0]
            val_u16 = (val_s16 + 32768) & 0xFFFF
        else:
            raise ValueError(f"Unsupported sample width: {sampwidth}")
        samples.append(val_u16)

    # Pad with silence (32768) if shorter than max_samples
    while len(samples) < max_samples:
        samples.append(32768)

    return samples


def write_mem(samples: list[int], output_path: Path) -> None:
    """Write sample integers as 16-bit hexadecimal words (one per line)."""
    with open(output_path, 'w', encoding='utf-8') as f:
        for s in samples:
            f.write(f"{s:04X}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert WAV file or generate synthetic sound for FPGA BRAM.")
    parser.add_argument('input_wav', nargs='?', type=Path, help="Input .wav file (optional)")
    parser.add_argument('-o', '--output', type=Path, default=Path("src/rtl/sample_data.mem"), help="Output .mem file")
    parser.add_argument('-n', '--samples', type=int, default=4096, help="Total sample count (default 4096)")
    parser.add_argument('--synth', action='store_true', help="Force synthetic chime generation")
    args = parser.parse_args()

    if args.input_wav and args.input_wav.exists() and not args.synth:
        print(f"Reading WAV file: {args.input_wav}")
        samples = load_wav(args.input_wav, max_samples=args.samples)
    else:
        print(f"Generating synthetic chime ({args.samples} samples)...")
        samples = generate_synth_chime(sample_count=args.samples)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_mem(samples, args.output)
    print(f"Wrote {len(samples)} 16-bit samples to {args.output}")


if __name__ == '__main__':
    main()
