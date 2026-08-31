#!/usr/bin/env python3
"""Diagnostic tool for the Sony/Logitech Buzz! USB controller on macOS.

Run this BEFORE we write any Godot extension code. It does two things:

1. Lists every HID device from Sony's vendor ID (0x054c), showing what
   usage_page/usage it declares. This tells us WHY Godot/SDL does or
   doesn't see it as a joystick.
2. Opens the Buzz controller and dumps raw input report bytes as they
   change, so we can press each of the 20 buttons and see exactly which
   byte/bit each one flips.

Setup (Terminal, one time):
    pip3 install hidapi

Usage:
    python3 buzz_hid_diag.py
"""

import sys

try:
    import hid
except ImportError:
    print("Missing dependency. Run:  pip3 install hidapi")
    sys.exit(1)

SONY_VID = 0x054C


def list_candidates():
    print("Scanning for Sony-vendor (0x054c) HID devices...\n")
    devices = [d for d in hid.enumerate() if d["vendor_id"] == SONY_VID]

    if not devices:
        print("No Sony-vendor HID devices found at all.")
        print("This would mean macOS/IOKit isn't even seeing the raw USB")
        print("device as a HID device, which points at a USB/driver issue")
        print("rather than a joystick-classification issue.")
        return []

    for d in devices:
        print(f"  path            : {d['path']}")
        print(f"  product_string  : {d.get('product_string')}")
        print(f"  manufacturer    : {d.get('manufacturer_string')}")
        print(f"  vendor_id       : {hex(d['vendor_id'])}")
        print(f"  product_id      : {hex(d['product_id'])}")
        print(f"  usage_page      : {hex(d.get('usage_page', 0))}")
        print(f"  usage           : {hex(d.get('usage', 0))}")
        print(f"  interface_number: {d.get('interface_number')}")
        print()

    return devices


def dump_reports(path):
    print("Opening device and reading raw input reports.")
    print("Press each of the 20 buttons ONE AT A TIME (press and release),")
    print("in this order, pausing briefly between each:")
    print("  Player 1: Red, Blue, Orange, Green, Yellow")
    print("  Player 2: Red, Blue, Orange, Green, Yellow")
    print("  Player 3: Red, Blue, Orange, Green, Yellow")
    print("  Player 4: Red, Blue, Orange, Green, Yellow")
    print()
    print("Every line below is one raw report. Ctrl+C to stop.\n")

    device = hid.device()
    device.open_path(path)
    device.set_nonblocking(False)

    last = None
    try:
        while True:
            report = device.read(64)
            if not report:
                continue
            if report != last:
                hex_bytes = " ".join(f"{b:02x}" for b in report)
                print(f"len={len(report):2d}  bytes: {hex_bytes}")
                last = report
    except KeyboardInterrupt:
        pass
    finally:
        device.close()


def main():
    devices = list_candidates()
    if not devices:
        return

    if len(devices) == 1:
        chosen = devices[0]
    else:
        print(f"Found {len(devices)} candidate device(s). Using the first one:")
        print(f"  {devices[0]['product_string']} ({hex(devices[0]['product_id'])})")
        print("If that's the wrong one, edit this script to pick a different index.\n")
        chosen = devices[0]

    dump_reports(chosen["path"])


if __name__ == "__main__":
    main()
