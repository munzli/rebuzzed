#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <hidapi/hidapi.h>
#include <string>
#include <vector>

namespace godot {

// This class talks to the Sony/Logitech Buzz! USB controller adapter
// directly, over hidapi. This bypasses the joystick subsystem of Godot and
// SDL entirely. Godot uses SDL3 for joypad support since version 4.5. On
// macOS, SDL3 does not find this device: the adapter correctly declares
// itself as a HID Joystick (usage_page=0x01, usage=0x04), but has zero
// analog axes. This appears to be why SDL's joystick backend does not
// find it. See scripts/debug/buzz_hid_diag.py for how the team found
// this.
//
// Report format (confirmed against a real device, see the output of
// scripts/debug/buzz_hid_diag.py): a 5-byte input report, where the 20
// buttons pack sequentially, one bit each. The sequence starts at byte[2]
// bit 0: byte[2] bits 0-7 are buttons 0-7, byte[3] bits 0-7 are buttons
// 8-15, byte[4] bits 0-3 are buttons 16-19. This is the same button order
// as InputManager.BUTTON_MAP (red, yellow, green, orange, blue per
// player, 4 players). As a result, raw index N here means the same thing
// as raw index N already does for the working joypad path on Linux and
// Windows.
class BuzzHid : public Object {
	GDCLASS(BuzzHid, Object);

protected:
	static void _bind_methods();

public:
	static constexpr int VENDOR_ID = 0x054C;
	static constexpr int BUTTON_COUNT = 20;

	BuzzHid();
	~BuzzHid();

	// Call this once per frame (see InputManager._process()). This scans
	// again for newly connected and disconnected adapters at intervals, and
	// reads any pending HID reports from adapters that are already open.
	void poll();

	Array get_connected_devices() const;
	bool is_button_pressed(int device, int button_index) const;

private:
	struct Device {
		hid_device *handle = nullptr;
		std::string path;
		bool buttons[BUTTON_COUNT] = {};
	};

	std::vector<Device> devices;
	double time_since_rescan = 0.0;

	void rescan();
	void close_all();
	static void decode_report(const unsigned char *report, int len, bool (&out)[BUTTON_COUNT]);
};

}
