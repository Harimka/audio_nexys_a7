#!/usr/bin/env python3
"""Forward Arturia USB-MIDI note messages to the Nexys A7 USB-UART link."""
import argparse
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list MIDI inputs and serial ports")
    parser.add_argument("--midi", help="MIDI input name or unique substring")
    parser.add_argument("--serial", help="board serial port, e.g. /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    try:
        import mido
        import serial
        from serial.tools import list_ports
    except ImportError as exc:
        print("Missing dependency. Install with: python3 -m pip install mido python-rtmidi pyserial", file=sys.stderr)
        print(exc, file=sys.stderr)
        return 2

    midi_names = mido.get_input_names()
    serial_names = [port.device for port in list_ports.comports()]
    if args.list:
        print("MIDI inputs:")
        for name in midi_names:
            print(f"  {name}")
        print("Serial ports:")
        for name in serial_names:
            print(f"  {name}")
        return 0

    if not args.serial:
        parser.error("--serial is required (run --list first)")
    if not args.midi:
        if len(midi_names) != 1:
            parser.error("select a MIDI input with --midi (run --list first)")
        midi_name = midi_names[0]
    else:
        matches = [name for name in midi_names if args.midi.lower() in name.lower()]
        if len(matches) != 1:
            print("MIDI input match is missing or ambiguous. Available inputs:", file=sys.stderr)
            print("\n".join(f"  {name}" for name in midi_names), file=sys.stderr)
            return 2
        midi_name = matches[0]

    uart = serial.Serial(args.serial, args.baud, timeout=0, write_timeout=1)
    uart.reset_input_buffer()
    held: set[tuple[int, int]] = set()
    last_send = [0.0]

    def forward(message) -> None:
        if message.type not in ("note_on", "note_off"):
            return
        uart.write(bytes(message.bytes()))
        key = (message.channel, message.note)
        if message.type == "note_on" and message.velocity > 0:
            held.add(key)
            action = "on"
        else:
            held.discard(key)
            action = "off"
        now = time.monotonic()
        if now - last_send[0] > 0.05:
            print(f"MIDI note {action}: {message.note} velocity={message.velocity}", flush=True)
            last_send[0] = now

    try:
        with mido.open_input(midi_name, callback=forward):
            print(f"Forwarding {midi_name} -> {args.serial} at {args.baud} baud. Ctrl-C to stop.", flush=True)
            while True:
                time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping; sending Note Off for held keys.")
        for channel, note in tuple(held):
            uart.write(bytes((0x80 | channel, note, 0)))
        uart.flush()
    finally:
        uart.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
