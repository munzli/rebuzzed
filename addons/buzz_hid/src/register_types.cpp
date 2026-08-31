#include "register_types.h"
#include "buzz_hid.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static BuzzHid *buzz_hid_singleton = nullptr;

void initialize_buzz_hid_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(BuzzHid);

	buzz_hid_singleton = memnew(BuzzHid);
	Engine::get_singleton()->register_singleton("BuzzHid", buzz_hid_singleton);
}

void uninitialize_buzz_hid_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	if (buzz_hid_singleton != nullptr) {
		Engine::get_singleton()->unregister_singleton("BuzzHid");
		memdelete(buzz_hid_singleton);
		buzz_hid_singleton = nullptr;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT buzz_hid_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_buzz_hid_module);
	init_obj.register_terminator(uninitialize_buzz_hid_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
