# Building for macOS

A working macOS build needs two things:

- An export of the game itself
- A separate build of the `buzz_hid` GDExtension.

The Buzz controller needs this extension to work on macOS. Without it, the
app still starts, but the controller does not work.

## Why buzz_hid exists

Godot 4.5 and later versions use SDL3 for controller support. On macOS,
SDL3 never finds the Buzz controller through `Input`, even though the
adapter correctly declares itself as a HID Joystick (`usage_page=0x01`,
`usage=0x04`). The adapter has no analog axes. This appears to be why
SDL's joystick backend does not find it.

This is invisible from GDScript: `Input.get_connected_joypads()` returns an
empty array. Godot gives no error.

`addons/buzz_hid/` works around this by talking to the adapter directly
over HID (via [hidapi](https://github.com/libusb/hidapi)), and bypasses
`Input`/SDL entirely. It registers itself as an engine singleton. If
`buzz_hid` is present, `scripts/autoload/input_manager.gd` uses it
automatically. If not, it falls back to the normal `Input` path. Linux
and Windows builds are unaffected, and need no extra steps.

See `addons/buzz_hid/src/buzz_hid.h` for the HID report format that
`buzz_hid` targets. See `scripts/debug/buzz_hid_diag.py` for the
diagnostic tool used to find this format from a real device.

## 1. Export templates

Find the Godot version in use with `godot --version`. Download the
matching export templates from the
[Godot releases page](https://github.com/godotengine/godot/releases).
Install the macOS templates at:

```
~/.local/share/godot/export_templates/<version>/macos.zip
```

(Location varies by OS — on macOS this is normally under
`~/Library/Application Support/Godot/export_templates/<version>/`.)

## 2. Build the buzz_hid extension

This step needs Xcode Command Line Tools (`xcode-select --install`) and
[SCons](https://scons.org/) (`pip3 install scons`).

Fetch the two source dependencies (neither is vendored — see
`.gitignore`):

```bash
cd addons/buzz_hid
git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp.git
git clone --depth 1 https://github.com/libusb/hidapi.git third_party/hidapi
```

Pick a godot-cpp branch that matches the project's Godot minor version,
for example `4.7`. If that branch does not exist, use the nearest older
branch instead. GDExtension is forward-compatible, so a `4.5` build still
loads in a `4.7.x` editor. If you change the branch, update
`compatibility_minimum` in `buzz_hid.gdextension` to match.

Build both configurations, as a universal binary (arm64 and x86_64):

```bash
scons platform=macos target=template_debug arch=universal
scons platform=macos target=template_release arch=universal
```

Local testing, for example the **Play** button or
`scenes/debug/controller_test.tscn`, uses the `target=template_debug`
build. An exported build uses the `target=template_release` build.

SCons compiles hidapi's macOS backend source
(`third_party/hidapi/mac/hid.c`) directly into `buzz_hid`'s own `.dylib`.
As a result, the built extension has no external runtime dependency beyond
IOKit and CoreFoundation, both part of macOS.

Verify there is no stray external dependency before you export the game:

```bash
otool -L bin/libbuzz_hid.macos.template_release.dylib
```

Every line must be a system path (`/usr/lib/...` or
`/System/Library/Frameworks/...`).

## 3. Export the game

The project includes a `macOS` preset in `export_presets.cfg`. The preset
uses `Universal` architecture, to match `buzz_hid`'s build. Other
architecture combinations are untested.

A universal macOS export also needs ETC2 ASTC texture import. The project
already enables this in `project.godot`
(`rendering/textures/vram_compression/import_etc2_astc`). Without it,
Godot refuses to export.

```bash
godot --headless --export-release "macOS" builds/macos/rebuzzed.zip
```

`buzz_hid`'s `.dylib` is just a `res://` resource, like any other. Godot
finds it automatically and bundles it into
`Rebuzzed.app/Contents/Frameworks/`.

Quiz data lives outside the exported binary and the `.pck` file (see
[Quiz content](../README.md#quiz-content)). Copy the `data/` folder next to
the exported `.app` after the build.

## 4. Running an unsigned build

Nothing here is code-signed or notarized. On first launch, macOS's
Gatekeeper blocks the app ("cannot be opened because the developer cannot
be verified", or similar). To get past this, do either of the following:

- Right-click the `.app` and choose **Open**, once.
- Strip the quarantine flag directly:

```bash
xattr -cr Rebuzzed.app
```
