#!/usr/bin/env python3
"""Run read-only checks of an extracted audio_nexys_a7 source tree."""
import argparse
import pathlib
import shutil
import subprocess
import tempfile

parser=argparse.ArgumentParser()
parser.add_argument('project',type=pathlib.Path,help='Extracted audio_nexys_a7 directory')
args=parser.parse_args()
here=pathlib.Path(__file__).resolve().parent
src=args.project.resolve()/'src'
for tool in ('iverilog','vvp'):
    if not shutil.which(tool): parser.error(f'{tool} is required')
cases={'fifo':['fifo'],'audio':['tone_generator'],'pwm':['pwm'],
       'buttons':['button_ctrl'],'reset':['reset_button_debouncer'],'vga':['display_ctrl']}
with tempfile.TemporaryDirectory(prefix='audio-nexys-audit-') as temp:
    midi_rtl = ['uart_rx', 'midi_note_decoder', 'midi_note_state',
                'midi_uart_receiver', 'usb_midi_note_decoder', 'usb_midi_voice',
                'midi_wavetable']
    for bench in ('tb_midi_uart_receiver', 'tb_midi_protocol', 'tb_usb_midi_voice'):
        target = str(pathlib.Path(temp) / (bench + '.vvp'))
        subprocess.run(['iverilog', '-g2012', '-s', bench, '-o', target,
                        str(here.parent / 'midi' / (bench + '.sv'))] +
                       [str(src / 'rtl' / (module + '.sv')) for module in midi_rtl],
                       check=True)
        subprocess.run(['vvp', target], check=True, timeout=60)
    for name,modules in cases.items():
        target=str(pathlib.Path(temp)/(name+'.vvp'))
        subprocess.run(['iverilog','-g2012','-s','audit_'+name,'-o',target,
                        str(here/'audit_tb.sv')]+[str(src/'rtl'/(m+'.sv')) for m in modules],check=True)
        subprocess.run(['vvp',target],check=True,timeout=60)
    rtl=[str(p) for p in sorted((src/'rtl').glob('*.sv'))]
    checks={
      'simulation top': ['-s','top_audio',str(src/'sim/top_audio.sv')]+rtl,
      'board top, port-only clock stub': ['-s','audio_nexys_a7',str(src/'top/audio_nexys_a7.sv'),str(here/'clk_wiz_0_stub.sv')]+rtl,
      'testbench elaboration': ['-s','tb_audio_nexys_a7',str(src/'tb/tb_audio_nexys_a7.sv'),str(src/'top/audio_nexys_a7.sv'),str(here/'clk_wiz_0_stub.sv')]+rtl,
    }
    for name,files in checks.items():
        proc=subprocess.run(['iverilog','-g2012','-tnull']+files,capture_output=True,text=True)
        print(f'[{name}] exit={proc.returncode}',flush=True)
        if proc.stdout: print(proc.stdout)
        if proc.stderr: print(proc.stderr)
print('These checks do not perform Vivado synthesis, timing analysis, or hardware validation.')
