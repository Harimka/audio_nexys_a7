#!/usr/bin/env python3
"""Run read-only checks of an extracted audio_nexys_a7 source tree."""
import argparse
import pathlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('project', type=pathlib.Path, help='Extracted audio_nexys_a7 directory')
parser.add_argument('--baseline', action='store_true', help='Expect baseline defect reproduction')
args = parser.parse_args()
here = pathlib.Path(__file__).resolve().parent
src = args.project.resolve() / 'src'
for tool in ('iverilog', 'vvp'):
    if not shutil.which(tool): parser.error(f'{tool} is required')

cases = {
    'fifo': ['fifo'],
    'audio': ['tone_generator'],
    'pwm': ['pwm'],
    'buttons': ['button_ctrl'],
    'reset': ['reset_button_debouncer'],
    'vga': ['display_ctrl'],
}

keyboard_cases = {
    'tb_ps2_keyboard_digit': ['ps2_keyboard_digit'],
    'tb_ps2_keyboard_stack': ['ps2_keyboard_digit'],
    'tb_sevseg_digit_mask': ['sevseg_ctrl'],
}

with tempfile.TemporaryDirectory(prefix='audio-nexys-audit-') as temp:
    # 1. Baseline audit modules
    for name, modules in cases.items():
        target = str(pathlib.Path(temp) / (name + '.vvp'))
        compile_cmd = ['iverilog', '-g2012']
        if args.baseline:
            compile_cmd.append('-DEXPECT_BASELINE_DEFECTS')
        compile_cmd.extend(['-s', 'audit_' + name, '-o', target, str(here / 'audit_tb.sv')])
        compile_cmd.extend([str(src / 'rtl' / (m + '.sv')) for m in modules])
        subprocess.run(compile_cmd, check=True)
        subprocess.run(['vvp', target], check=True, timeout=60)

    # 2. Keyboard milestone regression tests
    keyboard_dir = here.parent / 'keyboard'
    if keyboard_dir.exists():
        for bench, modules in keyboard_cases.items():
            bench_file = keyboard_dir / (bench + '.sv')
            if bench_file.exists():
                target = str(pathlib.Path(temp) / (bench + '.vvp'))
                subprocess.run(['iverilog', '-g2012', '-s', bench, '-o', target,
                                str(bench_file)] +
                               [str(src / 'rtl' / (module + '.sv')) for module in modules],
                               check=True)
                subprocess.run(['vvp', target], check=True, timeout=60)

    # 3. Top-level elaboration checks
    rtl = [str(p) for p in sorted((src / 'rtl').glob('*.sv'))]
    checks = {
        'simulation top': ['-s', 'top_audio', str(src / 'sim/top_audio.sv')] + rtl,
        'board top, port-only clock stub': ['-s', 'audio_nexys_a7', str(src / 'top/audio_nexys_a7.sv'), str(here / 'clk_wiz_0_stub.sv')] + rtl,
        'testbench elaboration': ['-s', 'tb_audio_nexys_a7', str(src / 'tb/tb_audio_nexys_a7.sv'), str(src / 'top/audio_nexys_a7.sv'), str(here / 'clk_wiz_0_stub.sv')] + rtl,
    }
    for name, files in checks.items():
        proc = subprocess.run(['iverilog', '-g2012', '-tnull'] + files, capture_output=True, text=True)
        print(f'[{name}] exit={proc.returncode}', flush=True)
        if proc.stdout: print(proc.stdout)
        if proc.stderr: print(proc.stderr)
print('These checks do not perform Vivado synthesis, timing analysis, or hardware validation.')
