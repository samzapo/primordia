#include "../resident_reference.h"
#include <godot_cpp/godot.hpp>
using namespace godot;
static void initialize_resident(ModuleInitializationLevel level) {
  if(level==MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<PrimordiaResidentReference>();
}
static void terminate_resident(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT primordia_resident_init(
    GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr library,GDExtensionInitialization *init) {
  GDExtensionBinding::InitObject object(get,library,init);
  object.register_initializer(initialize_resident);
  object.register_terminator(terminate_resident);
  object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return object.init();
}
