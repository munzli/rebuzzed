#include "buzz_hid.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// A scan for newly plugged and unplugged adapters on every single frame
// calls hid_enumerate() (which walks the whole USB/HID tree) far more
// often than needed. Once a second is frequent enough for a physical USB
// device to feel instantly connected to a player.
static constexpr double RESCAN_INTERVAL_SEC = 1.0;

void BuzzHid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("poll"), &BuzzHid::poll);
	ClassDB::bind_method(D_METHOD("get_connected_devices"), &BuzzHid::get_connected_devices);
	ClassDB::bind_method(D_METHOD("is_button_pressed", "device", "button_index"), &BuzzHid::is_button_pressed);
}

BuzzHid::BuzzHid() {
	if (hid_init() != 0) {
		UtilityFunctions::print("[BuzzHid] hid_init() failed.");
	}
	rescan();
}

BuzzHid::~BuzzHid() {
	close_all();
	hid_exit();
}

void BuzzHid::poll() {
	time_since_rescan += 1.0 / 60.0;
	if (time_since_rescan >= RESCAN_INTERVAL_SEC) {
		time_since_rescan = 0.0;
		rescan();
	}

	for (Device &dev : devices) {
		if (dev.handle == nullptr) {
			continue;
		}
		unsigned char report[64];
		// Non-blocking: rescan() set hid_set_nonblocking() when it opened
		// the device. As a result, this returns 0 immediately when no new
		// report is waiting, instead of stalling the frame of the game.
		int result;
		while ((result = hid_read(dev.handle, report, sizeof(report))) > 0) {
			decode_report(report, result, dev.buttons);
		}
		if (result < 0) {
			// The adapter was unplugged. The next rescan() notices this, and
			// drops it from the list. This avoids a removal here,
			// mid-iteration.
			hid_close(dev.handle);
			dev.handle = nullptr;
		}
	}
}

void BuzzHid::decode_report(const unsigned char *report, int len, bool (&out)[BUTTON_COUNT]) {
	// See the layout comment in buzz_hid.h. This checks each index against
	// the actual report length, in case a future or different adapter
	// revision sends a shorter report than expected.
	for (int i = 0; i < BUTTON_COUNT; i++) {
		int byte_index = 2 + i / 8;
		int bit_index = i % 8;
		out[i] = byte_index < len && (report[byte_index] & (1 << bit_index)) != 0;
	}
}

Array BuzzHid::get_connected_devices() const {
	Array result;
	for (int i = 0; i < (int)devices.size(); i++) {
		if (devices[i].handle != nullptr) {
			result.push_back(i);
		}
	}
	return result;
}

bool BuzzHid::is_button_pressed(int device, int button_index) const {
	if (device < 0 || device >= (int)devices.size()) {
		return false;
	}
	if (button_index < 0 || button_index >= BUTTON_COUNT) {
		return false;
	}
	return devices[device].buttons[button_index];
}

void BuzzHid::rescan() {
	struct hid_device_info *list = hid_enumerate(VENDOR_ID, 0);

	std::vector<std::string> seen_paths;

	for (struct hid_device_info *cur = list; cur != nullptr; cur = cur->next) {
		// Generic Desktop page (0x01), Joystick usage (0x04). This matches
		// what scripts/debug/buzz_hid_diag.py found for this device. This
		// check does not match on product_id: different Buzz adapter
		// hardware revisions ship with different USB product IDs (0x0002 on
		// some units, 0x1000 on others).
		if (cur->usage_page != 0x01 || cur->usage != 0x04) {
			continue;
		}

		std::string path = cur->path;
		seen_paths.push_back(path);

		bool already_open = false;
		for (const Device &dev : devices) {
			if (dev.path == path && dev.handle != nullptr) {
				already_open = true;
				break;
			}
		}
		if (already_open) {
			continue;
		}

		hid_device *handle = hid_open_path(cur->path);
		if (handle == nullptr) {
			continue;
		}
		hid_set_nonblocking(handle, 1);

		Device dev;
		dev.handle = handle;
		dev.path = path;
		devices.push_back(dev);

		String product_name = cur->product_string != nullptr ? String(cur->product_string) : String("(unknown)");
		UtilityFunctions::print("[BuzzHid] Controller connected: ", product_name, " (", path.c_str(), ")");
	}

	hid_free_enumeration(list);

	// This drops entries for adapters that are no longer plugged in. This
	// happens either because poll() already closed the handle after a
	// failed read, or because an adapter vanished between rescans without
	// notice.
	for (int i = (int)devices.size() - 1; i >= 0; i--) {
		bool still_listed = false;
		for (const std::string &path : seen_paths) {
			if (devices[i].path == path) {
				still_listed = true;
				break;
			}
		}
		if (!still_listed || devices[i].handle == nullptr) {
			if (devices[i].handle != nullptr) {
				hid_close(devices[i].handle);
			}
			UtilityFunctions::print("[BuzzHid] Controller disconnected: ", devices[i].path.c_str());
			devices.erase(devices.begin() + i);
		}
	}
}

void BuzzHid::close_all() {
	for (Device &dev : devices) {
		if (dev.handle != nullptr) {
			hid_close(dev.handle);
			dev.handle = nullptr;
		}
	}
	devices.clear();
}
