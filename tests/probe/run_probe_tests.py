#!/usr/bin/env python3
"""Simulate the standalone PIC24 PS/2 diagnostic (no physical USB host)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sources = [
    root / 'diagnostics/usb_host_probe/audio_nexys_a7.sv',
    root / 'diagnostics/usb_host_probe/ps2_probe_rx.sv',
    root / 'src/rtl/reset_sync.sv',
    root / 'src/rtl/midi_note_decoder.sv',
    root / 'src/rtl/midi_note_state.sv',
    root / 'tests/probe/tb_usb_host_probe.sv',
]
with tempfile.TemporaryDirectory(prefix='nexys-usb-probe-') as tmp:
    target = str(Path(tmp) / 'probe.vvp')
    subprocess.run(['iverilog', '-g2012', '-Wall', '-s', 'tb_usb_host_probe',
                    '-o', target] + [str(p) for p in sources], check=True)
    subprocess.run(['vvp', target], check=True, timeout=30)
print('This is a simulated PS/2-pin test; it does not confirm MicroLab or PIC24 firmware support.')
