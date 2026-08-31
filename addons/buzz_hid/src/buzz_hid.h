#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <hidapi/hidapi.h>
#include <string>
#include <vector>

namespace godot {

// Talks to the Sony/Logitech Buzz! USB controller adaptor directly via
// hidapi, bypassing Godot's/SDL's joystick subsystem entirely. SDL3 (which
// Godot uses for joypad support since 4.5) does not surface this device on
// macOS -- it correctly self-declares as a HID Joystick (usage_page=0x01,
// usage=0x04), but has zero analog axes, which SDL's joystick backend
// appears to require. See scripts/debug/buzz_hid_diag.py for how this was
// diagnosed.
//
// Report format (empirically confirmed against a real device, see
// scripts/debug/buzz_hid_diag.py output): a 5-byte input report where the
// 20 buttons pack sequentially, one bit each, starting at byte[2] bit 0:
// byte[2] bits 0-7 = buttons 0-7, byte[3] bits 0-7 = buttons 8-15,
// byte[4] bits 0-3 = buttons 16-19. This is the same button order as
// InputManager.BUTTON_MAP (red, yellow, green, orange, blue per player,
// 4 players), so raw index N here means exactly the same thing as raw
// index N already does for the working joypad path on Linux/Windows.
class BuzzHid : public Object {
	GDCLASS(BuzzHid, Object);

protected:
	static void _bind_methods();

public:
	static constexpr int VENDOR_ID = 0x054C;
	static constexpr int BUTTON_COUNT = 20;

	BuzzHid();
	~BuzzHid();

	// Call this once per frame (see InputManager._process()). Rescans for
	// newly connected/disconnected adaptors periodically, and reads any
	// pending HID reports from already-open ones.
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
