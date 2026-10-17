#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <utility>
using namespace godot;
class PrimordiaDictionaryLifetime : public RefCounted {
 GDCLASS(PrimordiaDictionaryLifetime, RefCounted)
 protected:
 static void _bind_methods() { ClassDB::bind_method(D_METHOD("exercise","iterations","copy"), &PrimordiaDictionaryLifetime::exercise); }
 public:
 int exercise(int iterations, bool copy) {
  Dictionary source, target; PackedByteArray payload; payload.resize(256);
  source["a"]=1; source["b"]=2; source["payload"]=payload;
  for (int i=0;i<iterations;++i) {
   source["a"]=i;
   if (copy) { const Dictionary next=source.duplicate(true);target=next; }
   else target=source.duplicate(true);
   target=std::move(target);
  }
  return int(target["a"]);
 }
};
static void initialize_probe(ModuleInitializationLevel level) {
 if(level==MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<PrimordiaDictionaryLifetime>();
}
static void terminate_probe(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT primordia_dictionary_probe_init(
 GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr library,GDExtensionInitialization *init) {
 GDExtensionBinding::InitObject object(get,library,init);
 object.register_initializer(initialize_probe);object.register_terminator(terminate_probe);
 object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
 return object.init();
}
