# Arturia MicroLab mk3 → UART → wavetable FPGA voice

> Superseded architecture (2026-10-24): the user requires the laptop only for programming. This laptop bridge does not satisfy that requirement. Keep it only as a bench diagnostic; do not give its wiring steps as the requested final setup. See [DIRECT_USB_MIDI.md](DIRECT_USB_MIDI.md).

## What this prototype does

The Arturia MicroLab mk3 is a USB-MIDI keyboard, not an audio source. This prototype sends its MIDI Note On/Off messages through a Linux computer, then through the Nexys A7's `PROG UART` USB cable to the FPGA. The FPGA parses MIDI over UART, generates a monophonic sine tone from an RTL wavetable, and sends it to the board's mono audio output.

```text
MicroLab mk3 --USB-MIDI--> Linux laptop --USB-UART, 115200 8-N-1--> FPGA
                                                               | MIDI parser
                                                               | sine wavetable
                                                               v
                                                        PWM -> headphones
```

This is a bench prototype requiring the laptop during play. The user explicitly excludes a laptop during play. The board's `USB HOST` port is not used: this project does not implement USB-MIDI host support.

## Wiring

1. Leave the board's `PROG UART` Micro-USB cable connected to the Linux laptop; Vivado uses it for programming and the FTDI USB-UART channel carries MIDI bytes to FPGA pin C4 (`UART_TXD_IN`).
2. Unplug the MicroLab cable from the board's `USB HOST` connector. Connect the MicroLab's USB-C lead to a USB host port on the laptop. Use a hub if the laptop does not have two ports available.
3. Leave headphones/active speaker in the board's `MONO AUDIO OUT`.

The two data links have distinct jobs: Arturia USB to laptop carries USB-MIDI; board `PROG UART` to laptop carries UART bytes into the FPGA. Do not plug the keyboard USB into the Nexys `USB HOST` for this prototype.

## FPGA build and programming

Use this updated project source tree, not the old bitstream. From the repository root:

```bash
make deploy
```

In Vivado, run **Generate Bitstream**, then **Open Hardware Manager → Open Target → Auto Connect → Program Device** and program the new `audio_nexys_a7.bit`. The project Tcl includes all `src/rtl/*.sv` files automatically. Set board switch `SW15=1` to select MIDI; `SW15=0` retains the original button-controlled demo. The existing switches `SW[2:0]` do not set the MIDI note.

## Laptop bridge (Ubuntu/Linux)

Install Python dependencies in a virtual environment from the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install mido python-rtmidi pyserial
python tools/midi_uart_bridge.py --list
```

The list should show a MicroLab MIDI input and the board USB-UART serial port, commonly `/dev/ttyUSB0` or `/dev/ttyUSB1`. Start the bridge with the exact port name (or a unique substring):

```bash
python tools/midi_uart_bridge.py --midi MicroLab --serial /dev/ttyUSB0
```

Change both arguments to match `--list`. A key press should print `MIDI note on`; release should print `MIDI note off`. If Linux reports permission denied for `/dev/ttyUSB*`, add the account to the `dialout` group and log out/in, or ask the lab administrator. Do not run the bridge and a serial terminal on the same port at once.

## Current implementation limits

- Monophonic, last Note On wins. A matching Note Off silences it; it does not restore an older held key.
- MIDI Note On, Note Off, velocity-zero Note On, running status and channels 1–16 are parsed. Real-time MIDI bytes are ignored. Other message types, including sustain CC64 and pitch bend, are ignored.
- Velocity scales the sine amplitude. Board BTNU/BTND volume control is retained.
- `SW15=1` chooses MIDI; no BTNC press is needed in MIDI mode. `SW15=0` selects the original demo path.
- The display still shows the original demo's note/octave state; it is not a MIDI activity monitor.
- UART is 115200 baud, 8 data bits, no parity, one stop bit. The bridge transmits standard three-byte MIDI messages; the RTL receiver also accepts MIDI running status.
- The line rate is deliberately higher than DIN MIDI's 31.25 kbaud because this is MIDI over the laptop's USB-UART bridge, not a 5-pin DIN link.

## Tests and verification state

Run the MIDI RTL unit test:

```bash
iverilog -g2012 -s tb_midi_uart_receiver -o /tmp/midi_uart_tb \
  tests/midi/tb_midi_uart_receiver.sv \
  src/rtl/uart_rx.sv src/rtl/midi_uart_receiver.sv src/rtl/midi_wavetable.sv
vvp /tmp/midi_uart_tb
```

The test checks Note On/Off, velocity-zero Note On, running status, and wavetable phase advance. It does not test USB enumeration, serial permissions, Vivado synthesis/timing, or physical audio. Those still require the lab laptop and board.

## UART source review

The user-provided [Methoda UART examples](https://github.com/YuraThomas/Methoda/tree/main/Interfaces/My_UART/UART_up) were inspected for the educational FSM organization. The project uses its own receiver with a two-flop RX synchronizer, half-bit start validation, configurable clock/baud parameters, and a one-cycle data-valid pulse; no source code was copied. The reference repository is MIT-licensed; inspected revision `80b2d908b18afbe6623da05266936f8ac58cc8e7`.
