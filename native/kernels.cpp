#include "music_mixer.h"
#include "simulation_workers.h"
#include "mutual_matching.h"
#include "resident_reference.h"
#include "chemical_neighbors.h"
#include "liquid_particles.h"
#include "parcel_transport.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <vector>
#include <unordered_map>
using namespace godot;
namespace {
constexpr double TAU = 6.283185307179586, PI = TAU / 2;
double wrap(double x, double n) { return x - std::floor(x / n) * n; }
Vector2 wrapv(Vector2 p) { return Vector2(wrap(p.x, 4096), wrap(p.y, 2560)); }
Vector2 delta(Vector2 a, Vector2 b) {
  return Vector2(wrap(b.x - a.x + 2048, 4096) - 2048,
                 wrap(b.y - a.y + 1280, 2560) - 1280);
}
// GDScript's Medium.offset evaluates component subtraction/wrap in doubles
// before constructing Vector2. Preserve that order for migrated script consumers.
Vector2 perception_delta(Vector2 a, Vector2 b) {
  double x=double(b.x)-double(a.x), y=double(b.y)-double(a.y);
  return Vector2(x-4096*std::floor((x+2048)/4096),y-2560*std::floor((y+1280)/2560));
}
int mod(int x, int n) { return (x % n + n) % n; }
int node(int x, int y) { return mod(y, 40) * 64 + mod(x, 64); }
double activity(Vector2 p, Vector2 camera, Vector2 half) {
  // Match Medium.visibility: full rectangle + 64 world units, then 64 fade.
  Vector2 beyond = delta(camera, p).abs() - half - Vector2(64,64);
  double t = std::clamp(1 - std::max(beyond.x,beyond.y) / 64., 0., 1.);
  return t * t * (3 - 2 * t);
}
Vector2 sample(const PackedVector2Array &v, Vector2 p) {
  p = wrapv(p) / 64 - Vector2(.5, .5);
  int x = std::floor(p.x), y = std::floor(p.y);
  return v[node(x, y)]
      .lerp(v[node(x + 1, y)], p.x - x)
      .lerp(v[node(x, y + 1)].lerp(v[node(x + 1, y + 1)], p.x - x), p.y - y);
}
double acid_sample(const PackedFloat32Array &v, Vector2 p) {
  p = wrapv(p) / 64 - Vector2(.5, .5);
  int x = std::floor(p.x), y = std::floor(p.y);
  double fx = p.x - x, fy = p.y - y;
  return ((1 - fx) * v[node(x, y)] + fx * v[node(x + 1, y)]) * (1 - fy) +
         ((1 - fx) * v[node(x, y + 1)] + fx * v[node(x + 1, y + 1)]) * fy;
}
struct Keys {
  const Variant p = String("p");
  const Variant v = String("v");
  const Variant alive = String("alive");
  const Variant age = String("age");
  const Variant angle = String("angle");
  const Variant spin = String("spin");
  const Variant previous = String("previous");
  const Variant updated = String("updated");
  const Variant previous_angle = String("previous_angle");
  const Variant direction = String("direction");
  const Variant amount = String("amount");
  const Variant capacity = String("capacity");
  const Variant kind = String("kind");
  const Variant reaction_activity = String("reaction_activity");
  const Variant contact_radius = String("contact_radius");
  const Variant reacted = String("reacted");
  const Variant transport_at = String("transport_at");
  const Variant transport_jump = String("transport_jump");
  const Variant chemical_at = String("chemical_at");
};
// Ordinary scenes retain authoritative numeric slots plus sparse metadata.
// The scoped dictionary handoff remains a separately selectable reference path.
struct PacketState {
  Vector2 p, v, dir, previous;
  double angle, previous_angle, spin, age, amount, capacity, transport_at, chemical_at;
  int kind, updated, reacted;
  bool alive, jump;
};
struct ChemicalOriginal { Vector2 v; double amount=0,capacity=0,chemical_at=0; int kind=0,reacted=-1; bool alive=false, has_clock=false; };
struct PacketSlot {
  Dictionary d;
  PacketState value{};
  ChemicalOriginal original;
  uint64_t epoch = 0, handle=0;
  uint32_t mask=0;
  bool moved = false, chemical = false, transport_loaded=false, chemical_loaded=false;
  bool has_transport_clock=false, has_chemical_clock=false;
};
struct RenderPacket {
  Vector2 p, previous;
  double angle, previous_angle, amount;
  int kind, updated;
  bool alive;
  uint64_t epoch = 0;
};
struct Particle {
  Dictionary *d=nullptr; // Cold metadata remains outside numeric scratch.
  Vector2 p, v, dir;
  double amount, capacity, active, radius, elapsed;
  int kind, identity, neighbor_bin;
  uint64_t handle=0;
  bool alive, reacted, initial_alive, initial_reacted;
  Vector2 initial_v;
  double initial_amount, initial_capacity;
  int initial_kind;
};
} // namespace
class PrimordiaGrid : public RefCounted {
  GDCLASS(PrimordiaGrid, RefCounted)
  Keys keys;
  double size = 64;
  int cols = 64, rows = 40;
  std::vector<std::vector<int>> bins = std::vector<std::vector<int>>(2560);
  std::vector<int> locations;
  std::vector<int> moved_bins;
  int key(Vector2 p) const {
    return mod(int(std::floor(p.y / size)), rows) * cols +
           mod(int(std::floor(p.x / size)), cols);
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "size"),
                         &PrimordiaGrid::configure);
    ClassDB::bind_method(D_METHOD("clear"), &PrimordiaGrid::clear);
    ClassDB::bind_method(D_METHOD("rebuild", "particles"),
                         &PrimordiaGrid::rebuild);
    ClassDB::bind_method(D_METHOD("update", "particles", "ids"),
                         &PrimordiaGrid::update);
    ClassDB::bind_method(D_METHOD("rebuild_positions", "positions"), &PrimordiaGrid::rebuild_positions);
    ClassDB::bind_method(D_METHOD("update_positions", "positions", "ids"), &PrimordiaGrid::update_positions);
    ClassDB::bind_method(D_METHOD("insert", "id", "position"),
                         &PrimordiaGrid::insert);
    ClassDB::bind_method(D_METHOD("move", "id", "old", "position"),
                         &PrimordiaGrid::move);
    ClassDB::bind_method(D_METHOD("query_kind_rect", "particles", "position", "half", "kind"),
                         &PrimordiaGrid::query_kind_rect);
    ClassDB::bind_method(D_METHOD("query_rect", "position", "half"),
                         &PrimordiaGrid::query_rect);
  }

public:
  void configure(double s) {
    size = s;
    cols = int(std::round(4096 / s));
    rows = int(std::round(2560 / s));
    bins.clear();
    bins.resize(cols * rows);
    locations.clear();
    moved_bins.clear();
  }
  void clear() {
    locations.clear();
    moved_bins.clear();
    for (auto &b : bins)
      b.clear();
  }
  void rebuild(Array particles) {
    clear();
    for (int i = 0; i < particles.size(); ++i) {
      Dictionary p = particles[i];
      insert(i, p[keys.p]);
    }
  }
  void rebuild_positions(PackedVector2Array positions) {
    clear(); for (int i=0;i<positions.size();++i) insert(i,positions[i]);
  }
  void insert(int id, Vector2 p) {
    if (id >= int(locations.size())) locations.resize(id + 1, -1);
    locations[id] = key(p);
    bins[locations[id]].push_back(id);
  }
  void update(Array particles, Array ids) {
    // Read only moved packets. Match a full rebuild's stable identity order,
    // including when a hybrid reference operation used move() beforehand.
    for (int k = 0; k < ids.size(); ++k) {
      int id = int(ids[k]);
      Dictionary p = particles[id];
      int to = key(p[keys.p]);
      int from = locations[id];
      if (from == to) continue;
      auto &old = bins[from];
      auto found = std::find(old.begin(), old.end(), id);
      if (found != old.end()) old.erase(found);
      bins[to].push_back(id);
      locations[id] = to;
      std::sort(bins[from].begin(), bins[from].end());
      std::sort(bins[to].begin(), bins[to].end());
    }
    // A hybrid reference move may already have changed locations. Repair its
    // insertion order even when update() now sees from == to.
    std::sort(moved_bins.begin(), moved_bins.end());
    moved_bins.erase(std::unique(moved_bins.begin(), moved_bins.end()), moved_bins.end());
    for (int id : moved_bins) std::sort(bins[id].begin(),bins[id].end());
    moved_bins.clear();
  }
  void update_positions(PackedVector2Array positions, Array ids) {
    // Read only moved packets. Match a full rebuild's stable identity order,
    // including when a hybrid reference operation used move() beforehand.
    for (int k = 0; k < ids.size(); ++k) {
      int id = int(ids[k]);
      int to = key(positions[id]);
      int from = locations[id];
      if (from == to) continue;
      auto &old = bins[from];
      auto found = std::find(old.begin(), old.end(), id);
      if (found != old.end()) old.erase(found);
      bins[to].push_back(id);
      locations[id] = to;
      std::sort(bins[from].begin(), bins[from].end());
      std::sort(bins[to].begin(), bins[to].end());
    }
    // A hybrid reference move may already have changed locations. Repair its
    // insertion order even when update() now sees from == to.
    std::sort(moved_bins.begin(), moved_bins.end());
    moved_bins.erase(std::unique(moved_bins.begin(), moved_bins.end()), moved_bins.end());
    for (int id : moved_bins) std::sort(bins[id].begin(),bins[id].end());
    moved_bins.clear();
  }
  void move(int id, Vector2 old, Vector2 p) {
    int a = key(old), b = key(p);
    if (a == b)
      return;
    auto &v = bins[a];
    auto it = std::find(v.begin(), v.end(), id);
    if (it != v.end())
      v.erase(it);
    bins[b].push_back(id);
    locations[id] = b;
    moved_bins.push_back(a); moved_bins.push_back(b);
  }
  TypedArray<int64_t> query_kind_rect(Array particles, Vector2 p, Vector2 h, int kind) const {
    TypedArray<int64_t> out;
    int lx = std::floor((p.x-h.x)/size), ly = std::floor((p.y-h.y)/size),
        hx = std::floor((p.x+h.x)/size), hy = std::floor((p.y+h.y)/size);
    for (int x=lx;x<std::min(hx+1,lx+cols);++x)
      for (int y=ly;y<std::min(hy+1,ly+rows);++y)
        for (int id : bins[mod(y,rows)*cols+mod(x,cols)]) {
          Dictionary packet = particles[id];
          // Read current chemistry, never cache a species tag across reactions.
          if (int(packet[keys.kind]) == kind && bool(packet[keys.alive]))
            out.push_back(id);
        }
    return out;
  }
  TypedArray<int64_t> query_rect(Vector2 p, Vector2 h) const {
    TypedArray<int64_t> out;
    int lx = std::floor((p.x - h.x) / size),
        ly = std::floor((p.y - h.y) / size),
        hx = std::floor((p.x + h.x) / size),
        hy = std::floor((p.y + h.y) / size);
    for (int x = lx; x < std::min(hx + 1, lx + cols); ++x)
      for (int y = ly; y < std::min(hy + 1, ly + rows); ++y)
        for (int id : bins[mod(y, rows) * cols + mod(x, cols)])
          out.push_back(id);
    return out;
  }
};
class PrimordiaKernels : public RefCounted {
  GDCLASS(PrimordiaKernels, RefCounted)
  Keys keys;
  struct Stem {
    Vector2 a, b;
    double radius;
  };
  std::vector<Stem> stems;
  std::array<std::vector<int>, 640> stem_bins;
  static int stem_key(Vector2 p) {
    return mod(int(std::floor(p.y / 128)), 20) * 32 +
           mod(int(std::floor(p.x / 128)), 32);
  }
  static Vector2 closest_stem(Vector2 p, Vector2 a, Vector2 b) {
    Vector2 edge = b - a;
    return a + edge * std::clamp(
                          double((p - a).dot(edge)) /
                              std::max(double(edge.length_squared()), .00001),
                          0., 1.);
  }
  static double circle_time(Vector2 p, Vector2 travel, Vector2 center,
                            double radius) {
    Vector2 d = p - center;
    double a = travel.length_squared(), b = d.dot(travel),
           c = d.length_squared() - radius * radius;
    if (c <= 0)
      return b < 0 ? 0. : 2.;
    double discriminant = b * b - a * c;
    if (a < .000001 || discriminant < 0)
      return 2.;
    double t = (-b - std::sqrt(discriminant)) / a;
    return t >= 0 && t <= 1 ? t : 2.;
  }
  static double stem_time(Vector2 p, Vector2 travel, Vector2 a, Vector2 b,
                          double radius) {
    double t = std::min(circle_time(p, travel, a, radius),
                        circle_time(p, travel, b, radius));
    Vector2 axis = (b - a).normalized(), normal(-axis.y, axis.x);
    double side = (p - a).dot(normal), speed = travel.dot(normal);
    if (std::abs(speed) > .000001)
      for (int sign : {-1, 1}) {
        if (speed * sign >= 0)
          continue;
        double hit = (sign * radius - side) / speed,
               along = (p + travel * hit - a).dot(axis);
        if (hit >= 0 && hit <= 1 && along >= 0 && along <= a.distance_to(b))
          t = std::min(t, hit);
      }
    return t;
  }
  bool packet_frame = false;
  Array packet_source, render_source;
  uint64_t packet_epoch = 0, render_epoch = 0;
  int render_revision = -1, render_count = -1;
  bool packed_render_state=false;
  bool reuse_chemistry_scratch=true;
  int simulation_threads=8;
  bool parallel_transport=true, parallel_contacts=true, compact_geometry=false;
  bool pair_matching=false;
  std::vector<uint64_t> matching_seen;
  uint64_t matching_epoch=0,matching_jobs=0,matching_fallbacks=0;
  std::vector<PairChoice> pair_choices;
  std::vector<PairOutcome> pair_outcomes;
  std::vector<Vector2> contact_positions;
  std::vector<double> contact_radii;
  std::vector<int> contact_identities;
  uint64_t transport_jobs=0, contact_jobs=0, contact_fallbacks=0;
  struct TransportJob { int id; double dt,nx,ny,angular; };
  std::vector<TransportJob> transport_jobs_buffer;
  std::vector<uint64_t> transport_seen;
  uint64_t transport_epoch=0;
  struct ContactList { std::vector<int> ids; bool complete=true; };
  std::vector<ContactList> contact_lists;

  LiquidParticles liquid;
  ParcelTransport parcels;
  double physical_radius=0;
  std::vector<PacketSlot> packet_slots;
  std::vector<int> packet_touched;
  PackedVector2Array packet_positions;
  std::vector<RenderPacket> render_packets;
  std::array<std::vector<std::array<float,12>>,11> render_instances;

  // The pool owns hot state. Metadata is sparse and never a second mutable pose.
  bool pool_enabled=false;
  uint64_t next_handle=1, pool_imports=0, pool_exports=0, pool_batches=0;
  std::unordered_map<uint64_t,int> handles;
  std::vector<int> signal_slots;
  static constexpr uint32_t CLOCK_T=1, CLOCK_C=2, UPDATED=4, REACTED=8, JUMP=16;
  PacketSlot import_slot(Dictionary d) {
    PacketSlot s; auto &v=s.value;
    v.p=d[keys.p]; v.previous=d.get(keys.previous,v.p); v.v=d.get(keys.v,Vector2());
    v.angle=d.get(keys.angle,0.); v.previous_angle=d.get(keys.previous_angle,v.angle);
    v.spin=d.get(keys.spin,0.); v.age=d.get(keys.age,0.); v.dir=d.get(keys.direction,Vector2());
    v.kind=d[keys.kind]; v.alive=d.get(keys.alive,true);
    v.amount=d[keys.amount]; v.capacity=d.get(keys.capacity,v.amount);
    v.updated=d.get(keys.updated,-1); v.reacted=d.get(keys.reacted,-1);
    v.transport_at=d.get(keys.transport_at,0.); v.chemical_at=d.get(keys.chemical_at,0.);
    v.jump=d.get(keys.transport_jump,false);
    for (auto pair : {std::pair<Variant,uint32_t>(keys.transport_at,CLOCK_T),{keys.chemical_at,CLOCK_C},
                      {keys.updated,UPDATED},{keys.reacted,REACTED},{keys.transport_jump,JUMP}})
      if (d.has(pair.first)) s.mask|=pair.second;
    s.has_transport_clock=s.mask&CLOCK_T; s.has_chemical_clock=s.mask&CLOCK_C;
    s.transport_loaded=s.chemical_loaded=true;
    s.handle=next_handle++;
    s.d=d.duplicate(true);
    for (auto key : {keys.p,keys.previous,keys.v,keys.angle,keys.previous_angle,keys.spin,keys.age,
                    keys.direction,keys.kind,keys.alive,keys.amount,keys.capacity,
                    keys.updated,keys.reacted,keys.transport_at,keys.chemical_at,keys.transport_jump})
      s.d.erase(key);
    s.d.erase("_handle"); s.d.erase("_index"); s.d.erase(keys.reaction_activity); s.d.erase(keys.contact_radius);
    ++pool_imports;
    return s;
  }
  Dictionary snapshot(int id) {
    if (id<0 || id>=int(packet_slots.size())) return Dictionary();
    const auto &s=packet_slots[id]; const auto &v=s.value;
    Dictionary d=s.d.duplicate(true);
    d[keys.p]=v.p; d[keys.previous]=v.previous; d[keys.v]=v.v;
    d[keys.angle]=v.angle; d[keys.previous_angle]=v.previous_angle; d[keys.spin]=v.spin;
    d[keys.age]=v.age; d[keys.direction]=v.dir; d[keys.kind]=v.kind; d[keys.alive]=v.alive;
    d[keys.amount]=v.amount; d[keys.capacity]=v.capacity;
    if (s.mask&UPDATED) d[keys.updated]=v.updated;
    if (s.mask&REACTED) d[keys.reacted]=v.reacted;
    if (s.has_transport_clock) d[keys.transport_at]=v.transport_at;
    if (s.has_chemical_clock) d[keys.chemical_at]=v.chemical_at;
    if (s.mask&JUMP) d[keys.transport_jump]=v.jump;
    d["_handle"]=int64_t(s.handle); d["_index"]=id;
    ++pool_exports; return d;
  }
  // Small native consumers share these numeric reads/writes with the retained
  // dictionary backend. No packet snapshot is made by a biological query.
  struct Access {
    PacketSlot *slot; Dictionary d; Keys *keys;
    Variant get(Variant key, Variant fallback=Variant()) const {
      if (!slot) return d.get(key,fallback);
      const auto &v=slot->value;
      if (key==keys->kind) return v.kind;
      if (key==keys->alive) return v.alive;
      if (key==keys->p) return v.p;
      if (key==keys->previous) return v.previous;
      if (key==keys->v) return v.v;
      if (key==keys->direction) return v.dir;
      if (key==keys->amount) return v.amount;
      if (key==keys->angle) return v.angle;
      if (key==keys->previous_angle) return v.previous_angle;
      return slot->d.get(key,fallback);
    }
    int kind() const { return slot ? slot->value.kind : int(d[keys->kind]); }
    bool alive() const { return slot ? slot->value.alive : bool(d[keys->alive]); }
    Vector2 position() const { return slot ? slot->value.p : Vector2(d[keys->p]); }
    double amount() const { return slot ? slot->value.amount : double(d[keys->amount]); }
    Variant operator[](Variant key) const { return get(key); }
    void set(Variant key,Variant value) {
      if (!slot) { d[key]=value; return; }
      auto &v=slot->value;
      if (key==keys->alive) v.alive=value;
      else if (key==keys->amount) v.amount=value;
      else if (key==keys->p) v.p=value;
      else if (key==keys->previous) v.previous=value;
      else slot->d[key]=value;
    }
  };
  Access access(Array particles,int id) {
    return pool_enabled ? Access{&packet_slots[id],Dictionary(),&keys} :
                          Access{nullptr,particles[id],&keys};
  }

  PacketSlot &packet(int id) {
    auto &slot=packet_slots[id];
    if (pool_enabled || slot.epoch==packet_epoch) return slot;
    slot.epoch=packet_epoch;
    slot.moved=slot.chemical=slot.transport_loaded=slot.chemical_loaded=false;
    slot.d=packet_source[id];
    auto &v=slot.value;
    v.p=slot.d[keys.p]; v.alive=slot.d[keys.alive];
    Variant clock=slot.d.get(keys.transport_at,Variant());
    slot.has_transport_clock=clock.get_type()!=Variant::NIL;
    v.transport_at=slot.has_transport_clock ? double(clock) : 0.;
    v.jump=slot.d.get(keys.transport_jump,false);
    slot.original.alive=v.alive;
    packet_positions.set(id,v.p);
    packet_touched.push_back(id);
    return slot;
  }
  void load_transport(PacketSlot &slot) {
    if (pool_enabled || slot.transport_loaded) return;
    auto &v=slot.value; auto &o=slot.original; auto &d=slot.d;
    v.kind=d[keys.kind]; v.v=d[keys.v]; v.angle=d[keys.angle];
    v.age=d[keys.age]; v.spin=d[keys.spin];
    o.kind=v.kind; o.v=v.v;
    slot.transport_loaded=true;
  }
  void load_chemistry(PacketSlot &slot) {
    if (pool_enabled || slot.chemical_loaded) return;
    auto &v=slot.value; auto &o=slot.original; auto &d=slot.d;
    if (!slot.moved) {
      v.kind=d[keys.kind]; v.v=d[keys.v]; v.dir=d[keys.direction];
      o.kind=v.kind; o.v=v.v;
    }
    v.amount=d[keys.amount]; v.capacity=d[keys.capacity];
    v.reacted=d.get(keys.reacted,-1);
    Variant clock=d.get(keys.chemical_at,Variant());
    slot.has_chemical_clock=clock.get_type()!=Variant::NIL;
    v.chemical_at=slot.has_chemical_clock ? double(clock) : 0.;
    o.has_clock=slot.has_chemical_clock;
    o.amount=v.amount; o.capacity=v.capacity; o.reacted=v.reacted; o.chemical_at=v.chemical_at;
    slot.chemical_loaded=true;
  }
  std::vector<Particle> foreground_scratch, background_scratch;
  std::vector<Dictionary> chemistry_dictionaries;
  ChemicalNeighbors neighbors;

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("parcel_configure", "enabled"), &PrimordiaKernels::parcel_configure);
    ClassDB::bind_method(D_METHOD("parcel_protect", "centers", "radii"), &PrimordiaKernels::parcel_protect);
    ClassDB::bind_method(D_METHOD("parcel_metrics"), &PrimordiaKernels::parcel_metrics);
    ClassDB::bind_method(D_METHOD("particle_engine_configure", "engine", "radius", "iterations"), &PrimordiaKernels::particle_engine_configure, DEFVAL(4.0), DEFVAL(1));
    ClassDB::bind_method(D_METHOD("particle_solver_probe", "positions", "velocities", "dt"), &PrimordiaKernels::particle_solver_probe);
    ClassDB::bind_method(D_METHOD("particle_engine_metrics"), &PrimordiaKernels::particle_engine_metrics);
    ClassDB::bind_method(D_METHOD("particle_engine_reset_metrics"), &PrimordiaKernels::particle_engine_reset_metrics);
    ClassDB::bind_method(D_METHOD("pair_matching_configure", "enabled"), &PrimordiaKernels::pair_matching_configure);
    ClassDB::bind_method(D_METHOD("thread_configure", "threads", "transport", "contacts", "compact"), &PrimordiaKernels::thread_configure, DEFVAL(true), DEFVAL(true), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("thread_metrics"), &PrimordiaKernels::thread_metrics);
    ClassDB::bind_method(D_METHOD("hotloop_configure", "scratch_reuse"), &PrimordiaKernels::hotloop_configure);
    ClassDB::bind_method(D_METHOD("neighbor_configure", "backend", "cache", "metrics"), &PrimordiaKernels::neighbor_configure, DEFVAL(false), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("neighbor_metrics"), &PrimordiaKernels::neighbor_metrics);
    ClassDB::bind_method(D_METHOD("neighbor_reset_metrics"), &PrimordiaKernels::neighbor_reset_metrics);
    ClassDB::bind_method(D_METHOD("pool_start"), &PrimordiaKernels::pool_start);
    ClassDB::bind_method(D_METHOD("pool_size"), &PrimordiaKernels::pool_size);
    ClassDB::bind_method(D_METHOD("pool_spawn"), &PrimordiaKernels::pool_spawn);
    ClassDB::bind_method(D_METHOD("pool_patch"), &PrimordiaKernels::pool_patch);
    ClassDB::bind_method(D_METHOD("pool_snapshot"), &PrimordiaKernels::pool_snapshot);
    ClassDB::bind_method(D_METHOD("pool_resolve"), &PrimordiaKernels::pool_resolve);
    ClassDB::bind_method(D_METHOD("pool_snapshots"), &PrimordiaKernels::pool_snapshots);
    ClassDB::bind_method(D_METHOD("pool_stop"), &PrimordiaKernels::pool_stop);
    ClassDB::bind_method(D_METHOD("pool_metrics"), &PrimordiaKernels::pool_metrics);
    ClassDB::bind_method(D_METHOD("pool_expire"), &PrimordiaKernels::pool_expire);
    ClassDB::bind_method(D_METHOD("pool_compact"), &PrimordiaKernels::pool_compact);
    ClassDB::bind_method(D_METHOD("pool_filter"), &PrimordiaKernels::pool_filter);
    ClassDB::bind_method(D_METHOD("pool_sense"), &PrimordiaKernels::pool_sense);
    ClassDB::bind_method(D_METHOD("pool_needed"), &PrimordiaKernels::pool_needed);
    ClassDB::bind_method(D_METHOD("pool_decoys"), &PrimordiaKernels::pool_decoys);
    ClassDB::bind_method(D_METHOD("pool_toxins"), &PrimordiaKernels::pool_toxins);
    ClassDB::bind_method(D_METHOD("pool_exposure"), &PrimordiaKernels::pool_exposure);
    ClassDB::bind_method(D_METHOD("pool_inspection"), &PrimordiaKernels::pool_inspection);
    ClassDB::bind_method(D_METHOD("pool_material"), &PrimordiaKernels::pool_material);
    ClassDB::bind_method(D_METHOD("packet_begin", "particles"), &PrimordiaKernels::packet_begin);
    ClassDB::bind_method(D_METHOD("packet_end"), &PrimordiaKernels::packet_end);
    ClassDB::bind_method(D_METHOD("packet_positions"), &PrimordiaKernels::get_packet_positions);
    ClassDB::bind_method(D_METHOD("invalidate_particle_render", "id"), &PrimordiaKernels::invalidate_particle_render, DEFVAL(-1));
    ClassDB::bind_method(D_METHOD("particle_render_ready", "particles", "revision"), &PrimordiaKernels::particle_render_ready);
    ClassDB::bind_method(D_METHOD("obstacle_configure", "segments", "bins"),
                         &PrimordiaKernels::obstacle_configure);
    ClassDB::bind_method(
        D_METHOD("obstacle_particles", "particles", "ids", "revision", "bounds"),
        &PrimordiaKernels::obstacle_particles, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("membrane_mesh", "outline"), &PrimordiaKernels::membrane_mesh);
    ClassDB::bind_method(D_METHOD("membrane_compress", "points", "previous", "angle", "depth", "radius"),
                         &PrimordiaKernels::membrane_compress);
    ClassDB::bind_method(
        D_METHOD("membrane_edges", "points", "lengths", "lambda", "alpha"),
        &PrimordiaKernels::membrane_edges);
    ClassDB::bind_method(
        D_METHOD("membrane_area", "points", "lambda", "alpha", "target"),
        &PrimordiaKernels::membrane_area);

    ClassDB::bind_method(D_METHOD("render_particles", "particles", "ids",
                                  "bodies", "camera", "half", "alpha",
                                  "revision", "capacities", "cache"),
                         &PrimordiaKernels::render_particles, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("feed", "particles", "ids", "body", "organ", "camera", "half"),
                         &PrimordiaKernels::feed);
    ClassDB::bind_method(D_METHOD("coarse_feed", "particles", "ids", "body", "organ", "rates", "camera", "half", "rng", "habitat"),
                         &PrimordiaKernels::coarse_feed);
    ClassDB::bind_method(D_METHOD("contacts_pass", "bodies", "pair", "dt", "deform"),
                         &PrimordiaKernels::contacts_pass);
    ClassDB::bind_method(
        D_METHOD("exclude", "particles", "ids", "bodies", "camera", "half"),
        &PrimordiaKernels::exclude);
    ClassDB::bind_method(D_METHOD("compact_particles", "particles", "cursor"), &PrimordiaKernels::compact_particles);
    ClassDB::bind_method(D_METHOD("background_ids", "particles", "cursor", "visits", "camera", "half", "clock"), &PrimordiaKernels::background_ids);
    ClassDB::bind_method(D_METHOD("settle_transport", "particles", "ids", "background"), &PrimordiaKernels::settle_transport);
    ClassDB::bind_method(D_METHOD("transport", "particles", "ids", "flow",
                                  "camera", "half", "dt", "revision", "rng", "clock", "background"),
                         &PrimordiaKernels::transport, DEFVAL(-1.0), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("chemistry", "particles", "ids", "acid",
                                  "camera", "half", "dt", "revision", "rng", "clock", "background", "dirty_writes", "collisions", "tight_bounds", "lazy_acid"),
                         &PrimordiaKernels::chemistry, DEFVAL(-1.0), DEFVAL(false), DEFVAL(true), DEFVAL(true), DEFVAL(true), DEFVAL(true));
    ClassDB::bind_method(
        D_METHOD("fluid_step", "velocity", "activity", "tide", "dt", "driven"),
        &PrimordiaKernels::fluid_step);
    ClassDB::bind_method(
        D_METHOD("acid_step", "values", "velocity", "activity", "dt"),
        &PrimordiaKernels::acid_step);
  }

public:

  void pair_matching_configure(bool enabled) { pair_matching=enabled; }
  bool thread_configure(int threads,bool transport,bool contacts,bool compact) {
    if (threads<1 || threads>8) return false;
    simulation_threads=threads;parallel_transport=transport;parallel_contacts=contacts;compact_geometry=compact;
    return true;
  }
  Dictionary thread_metrics() const {
    Dictionary d; d["compact_geometry"]=compact_geometry;d["threads"]=simulation_threads;d["transport_jobs"]=int64_t(transport_jobs);
    d["matching_jobs"]=int64_t(matching_jobs);d["matching_fallbacks"]=int64_t(matching_fallbacks);
    d["contact_jobs"]=int64_t(contact_jobs);d["contact_fallbacks"]=int64_t(contact_fallbacks);
    return d;
  }
  void hotloop_configure(bool scratch_reuse) {
    reuse_chemistry_scratch=scratch_reuse;
  }
  bool neighbor_configure(String backend, bool cache, bool metrics) {
    int b=backend=="legacy" ? 0 : backend=="packed" ? 1 : backend=="bvh" ? 2 : backend=="quadtree" ? 3 : -1;
    if (b<0 || (physical_radius>0 && cache)) return false;
    neighbors.configure(b,cache,metrics); return true;
  }
  void neighbor_reset_metrics() { neighbors.reset_metrics(); }
  Dictionary neighbor_metrics() {
    Dictionary d;
    d["backend"]=neighbors.backend==0 ? "legacy" : neighbors.backend==1 ? "packed" : neighbors.backend==2 ? "bvh" : "quadtree";
    d["cache"]=neighbors.caching; d["instrumented"]=neighbors.metrics;
    d["index_builds"]=int64_t(neighbors.index_builds()); d["calls"]=int64_t(neighbors.chemistry_calls());
    d["coarse_calls"]=int64_t(neighbors.coarse_calls()); d["cache_hits"]=int64_t(neighbors.cache_hits());
    d["cache_misses"]=int64_t(neighbors.cache_misses()); d["cache_overflows"]=int64_t(neighbors.cache_overflows());
    d["candidates"]=int64_t(neighbors.candidate_count()); d["owned_candidates"]=int64_t(neighbors.owned_count());
    d["contacts"]=int64_t(neighbors.contact_count()); d["memory_bytes"]=int64_t(neighbors.memory_bytes());
    d["index_build_ms"]=neighbors.build_time(); d["search_sort_ms"]=neighbors.search_time();
    d["cache_build_ms"]=neighbors.cache_time();
    return d;
  }
  void pool_start(Array particles) {
    packet_slots.clear(); handles.clear(); signal_slots.clear();
    packet_positions.resize(0);
    pool_enabled=true; packet_frame=true;
    for (int i=0;i<particles.size();++i) pool_spawn(particles[i]);
    render_packets.clear(); packet_touched.clear(); packet_source=Array(); render_source=Array();
  }
  int pool_size() const { return packet_slots.size(); }
  int pool_spawn(Dictionary d) {
    int id=packet_slots.size(); packet_slots.push_back(import_slot(d));
    handles[packet_slots.back().handle]=id;
    packet_positions.push_back(packet_slots.back().value.p);
    if (packet_slots.back().value.kind==3) signal_slots.push_back(id);
    return id;
  }
  void pool_patch(int id,Dictionary d) {
    auto &s=packet_slots[id]; auto &v=s.value;
    // Emission-time metadata/capacity corrections only, never a general sync.
    if (d.has("report")) s.d["report"]=Dictionary(d["report"]).duplicate(true);
    if (d.has("expires_at")) s.d["expires_at"]=d["expires_at"];
    if (d.has(keys.capacity)) v.capacity=d[keys.capacity];
    if (d.has(keys.transport_at)) { v.transport_at=d[keys.transport_at]; s.has_transport_clock=true; }
    if (d.has(keys.alive)) v.alive=d[keys.alive];
  }
  Dictionary pool_snapshot(int id) { return snapshot(id); }
  Dictionary pool_resolve(int64_t handle) {
    auto found=handles.find(handle); return found==handles.end() ? Dictionary() : snapshot(found->second);
  }
  Array pool_snapshots() {
    Array out; for (int i=0;i<pool_size();++i) out.push_back(snapshot(i)); return out;
  }
  Array pool_stop() {
    Array out=pool_snapshots(); pool_enabled=false; packet_frame=false;
    handles.clear(); signal_slots.clear(); packet_slots.clear(); packet_positions.resize(0);
    invalidate_particle_render(); return out;
  }
  void parcel_configure(bool enabled) {parcels.enabled=enabled;parcels.reset_metrics();}
  bool parcel_protect(PackedVector2Array centers,PackedFloat32Array radii) {
    if (centers.size()!=radii.size()) {parcels.invalidate_protection();return false;}
    for (int i=0;i<centers.size();++i) if (!centers[i].is_finite() || !std::isfinite(radii[i]) || radii[i]<0) {parcels.invalidate_protection();return false;}
    parcels.protect(centers,radii);return true;
  }
  Dictionary parcel_metrics() const {
    Dictionary d;d["enabled"]=parcels.enabled;d["calls"]=int64_t(parcels.calls);
    d["parcels"]=int64_t(parcels.parcels);d["children"]=int64_t(parcels.children);
    d["saved_integrations"]=int64_t(parcels.saved_integrations);
    d["rejected_shear"]=int64_t(parcels.rejected_shear);d["prepare_ms"]=parcels.prepare_ms;
    return d;
  }
  bool particle_engine_configure(String engine,double radius=4,int iterations=1) {
    if (engine!="current" && engine!="uniform" && engine!="liquidfun") return false;
    // Existing cached lists certify chemical radii, not a second physical radius.
    if (engine!="current" && neighbors.caching) return false;
    if (!liquid.configure(engine=="liquidfun",radius,iterations)) return false;
    physical_radius=engine!="current" ? radius : 0;
    return true;
  }
  Dictionary particle_engine_metrics() const {
    Dictionary d;d["engine"]=liquid.enabled ? "liquidfun" : physical_radius>0 ? "uniform" : "current";
    d["radius"]=liquid.enabled ? liquid.radius : physical_radius;d["iterations"]=liquid.iterations;
    d["calls"]=int64_t(liquid.calls);d["rebuilds"]=int64_t(liquid.rebuilds);
    d["solver_points"]=liquid.points;d["periodic_images"]=liquid.ghosts;
    d["solver_capacity"]=liquid.capacity;d["contacts"]=liquid.contacts;
    d["prepare_ms"]=liquid.prepare_ms;d["solve_ms"]=liquid.solve_ms;d["apply_ms"]=liquid.apply_ms;
    d["simd"]="portable C++ / 32-bit particle indices";
    d["pin"]="7f20402173fd143a3988c921bc384459c6a858f2";
    return d;
  }
  Dictionary particle_solver_probe(PackedVector2Array p,PackedVector2Array v,double dt) {
    Dictionary out;
    if (!liquid.enabled || p.size()!=v.size() || p.size()>100000 || !std::isfinite(dt) || dt<=0 || dt>.05) return out;
    std::vector<Vector2> positions,velocities;
    for (int i=0;i<p.size();++i) {
      if (!p[i].is_finite() || !v[i].is_finite()) return out;
      positions.push_back(wrapv(p[i]));velocities.push_back(v[i]);
    }
    liquid.solve(positions,velocities,dt);
    for (int i=0;i<p.size();++i) {p.set(i,wrapv(positions[i]));v.set(i,velocities[i]);}
    out["positions"]=p;out["velocities"]=v;out["metrics"]=particle_engine_metrics();return out;
  }
  void particle_engine_reset_metrics() {liquid.clear_metrics();parcels.reset_metrics();}
  Dictionary pool_metrics() const {
    Dictionary d; d["enabled"]=pool_enabled; d["particles"]=pool_enabled ? pool_size() : 0;
    d["imports"]=int64_t(pool_imports); d["exports"]=int64_t(pool_exports);
    d["consumer_batches"]=int64_t(pool_batches); d["mirror_writes"]=pool_enabled ? Variant(0) : Variant();
    d["numeric_capacity_bytes"]=int64_t(packet_slots.capacity()*sizeof(PacketSlot));
    d["signal_slots"]=int64_t(signal_slots.size()); return d;
  }
  int pool_expire(double time) {
    int count=0;
    for (int id : signal_slots) {
      auto &s=packet_slots[id];
      if (s.value.alive && double(s.d.get("expires_at",0.))<=time) {
        s.value.alive=false; ++count;
      }
    }
    return count;
  }
  int pool_compact(int cursor) {
    int before=0, kept=0; handles.clear(); signal_slots.clear();
    for (int i=0;i<pool_size();++i) {
      if (!packet_slots[i].value.alive) continue;
      if (i<cursor) ++before;
      if (i!=kept) packet_slots[kept]=std::move(packet_slots[i]);
      handles[packet_slots[kept].handle]=kept;
      if (packet_slots[kept].value.kind==3) signal_slots.push_back(kept);
      ++kept;
    }
    packet_slots.resize(kept); packet_positions.resize(kept);
    for (int i=0;i<kept;++i) packet_positions.set(i,packet_slots[i].value.p);
    return kept ? before%kept : 0;
  }
  TypedArray<int64_t> pool_filter(TypedArray<int64_t> ids,int kind,bool hidden,Vector2 camera,Vector2 half) {
    ++pool_batches; TypedArray<int64_t> out;
    for (int k=0;k<ids.size();++k) {
      int id=ids[k]; const auto &v=packet_slots[id].value;
      if (v.alive && (kind<0 || v.kind==kind) && (!hidden || activity(v.p,camera,half)<=0)) out.push_back(id);
    }
    return out;
  }
  Dictionary pool_sense(TypedArray<int64_t> ids,Vector2 receptor,double reach,Vector2 center,
                        int owner,int lineage,double time,bool graze) {
    ++pool_batches; Dictionary food,reports;
    for (int k=0;k<ids.size();++k) {
      auto &s=packet_slots[int64_t(ids[k])]; const auto &p=s.value;
      if (!p.alive || int(s.d.get("owner",-1))==owner) continue;
      double distance=perception_delta(receptor,p.p).length(); if (distance>reach) continue;
      if (graze && p.kind==0 && p.amount>0) {
        Vector2 d=perception_delta(center,p.p); Vector2 keyf=(d/std::max(80.,reach/4.)).floor();
        Vector2i key(int(keyf.x),int(keyf.y));
        if (!food.has(key)) {
          Dictionary bin; bin["mass"]=0.; bin["moment"]=Vector2(); bin["nearest"]=d; bin["distance"]=distance; food[key]=bin;
        }
        Dictionary bin=food[key]; bin["mass"]=double(bin["mass"])+p.amount;
        bin["moment"]=Vector2(bin["moment"])+d*p.amount;
        if (distance<double(bin["distance"])) { bin["nearest"]=d; bin["distance"]=distance; }
      } else if (!graze && p.kind==3 && double(s.d.get("expires_at",0.))>time) {
        Dictionary report=s.d.get("report",Dictionary());
        if (report.is_empty() || int(report["lineage"])==lineage) continue;
        Variant id=report["id"];
        if (reports.has(id)) {
          Dictionary seen=reports[id], old=seen["report"];
          if (double(old["emitted_at"])>=double(report["emitted_at"])) continue;
        }
        Dictionary detected; detected["report"]=report; detected["distance"]=distance;
        detected["expires_at"]=s.d["expires_at"]; reports[id]=detected;
      }
    }
    Dictionary out; out["food"]=food; out["reports"]=reports; return out;
  }
  bool pool_needed(TypedArray<int64_t> ids,Vector2 at,double reach,int wanted,bool coarse,
                   int lineage,Dictionary inherited,Vector2 camera,Vector2 half) {
    ++pool_batches;
    for (int k=0;k<ids.size();++k) {
      const auto &s=packet_slots[int64_t(ids[k])]; const auto &p=s.value;
      if (!p.alive || p.kind!=wanted || (!coarse && activity(p.p,camera,half)<=0)) continue;
      int owner=s.d.get("owner",-1);
      if (wanted==4 && int(inherited.get(owner,owner))==lineage) continue;
      if (perception_delta(at,p.p).length_squared()<=reach*reach) return true;
    }
    return false;
  }
  void pool_decoys(TypedArray<int64_t> ids,Object *cell,Dictionary organ,Dictionary inherited,
                   Vector2 camera,Vector2 half) {
    ++pool_batches;
    Vector2 at=cell->call("organ_position",organ), forward=Vector2(cell->call("organ_normal",organ)).rotated(cell->get("angle"));
    double radius=12*double(organ["scale"]); int lineage=cell->call("lineage_id");
    for (int k=0;k<ids.size();++k) {
      auto &s=packet_slots[int64_t(ids[k])]; auto &p=s.value; int owner=s.d.get("owner",-1);
      if (!p.alive || p.kind!=10 || int(inherited.get(owner,owner))==lineage || activity(p.p,camera,half)<=0) continue;
      Vector2 d=perception_delta(at,p.p); if (d.length()>radius+3.5*std::clamp(std::sqrt(p.amount/.3),.8,1.7)) continue;
      Vector2 n=d.normalized(); if (forward.dot(n)<.25 || p.dir.dot(-n)<.5) continue;
      organ["blocked"]=std::min(1.,double(organ["blocked"])+.65);
      cell->set("waste",double(cell->get("waste"))+p.amount); p.alive=false;
      cell->set("render_revision",int(cell->get("render_revision"))+1);
    }
  }
  void pool_toxins(TypedArray<int64_t> ids,Array cells,Dictionary cell_bins,bool spatial,
                     Dictionary inherited,Vector2 camera,Vector2 half,int player,Object *director) {
    ++pool_batches;
    for (int k=0;k<ids.size();++k) {
      auto &s=packet_slots[int64_t(ids[k])]; auto &p=s.value;
      if (!p.alive || p.kind!=4 || activity(p.p,camera,half)<=0) continue;
      Array candidates;
      if (spatial) candidates=cell_bins.get(Vector2i(mod(int(std::floor(p.p.x/128)),32),mod(int(std::floor(p.p.y/128)),20)),Array());
      else for (int i=0;i<cells.size();++i) candidates.push_back(i);
      int owner=s.d.get("owner",-1);
      for (int i=0;i<candidates.size();++i) {
        Object *cell=cells[int(candidates[i])];
        if (bool(cell->get("dead")) || double(cell->get("activity"))<=0 ||
            int(cell->call("lineage_id"))==int(inherited.get(owner,owner))) continue;
        Vector2 d=perception_delta(cell->get("position"),p.p);
        if (d.length()>double(cell->call("support",d.angle()))+5) continue;
        double debris=cell->call("damage",p.amount*75,d.angle());
        cell->set("waste",double(cell->get("waste"))+(debris+p.amount));
        cell->set("death_hint","Membrane failed after toxin exposure");
        if (owner==player) director->call("record","toxin",p.amount*75);
        p.alive=false; break;
      }
    }
  }
  void pool_exposure(TypedArray<int64_t> ids,Object *cell,double dt,Dictionary inherited,
                     Vector2 camera,Vector2 half,Ref<RandomNumberGenerator> rng) {
    ++pool_batches; double radius=double(cell->call("extent"))+24; Vector2 at=cell->get("position");
    int lineage=cell->call("lineage_id"); Array organs=cell->get("organs");
    for (int k=0;k<ids.size();++k) {
      auto &s=packet_slots[int64_t(ids[k])]; auto &p=s.value; int owner=s.d.get("owner",-1);
      if (!p.alive || (p.kind!=4 && p.kind!=10) || activity(p.p,camera,half)>0 || int(inherited.get(owner,owner))==lineage) continue;
      Vector2 d=perception_delta(at,p.p);
      if (d.length()>radius || rng->randf()>=1-std::exp(-2*std::max(0.,dt))) continue;
      if (p.kind==10) {
        bool bound=false;
        for (int i=0;i<organs.size();++i) {
          Dictionary organ=organs[i]; String kind=organ["kind"];
          if (kind!="feeding" && kind!="sensing" && kind!="hunting") continue;
          Vector2 contact=perception_delta(cell->call("organ_position",organ),p.p);
          if (contact.length()>12*double(organ["scale"])+3.5*std::clamp(std::sqrt(p.amount/.3),.8,1.7)) continue;
          Vector2 forward=Vector2(cell->call("organ_normal",organ)).rotated(cell->get("angle")), n=contact.normalized();
          if (forward.dot(n)<.25 || p.dir.dot(-n)<.5) continue;
          organ["blocked"]=std::min(1.,double(organ["blocked"])+.65); bound=true; break;
        }
        if (!bound) continue;
      }
      p.alive=false; cell->set("waste",double(cell->get("waste"))+p.amount);
      if (p.kind==4) {
        double debris=cell->call("damage",p.amount*75,d.angle());
        cell->set("waste",double(cell->get("waste"))+debris);
        cell->set("death_hint","Membrane failed after toxin exposure");
      }
    }
  }
  Array pool_inspection(TypedArray<int64_t> ids,Vector2 at,double alpha,int revision,double time,double zoom) {
    Array out;
    static const double radii[]={4,2.5,3,2.5,5,3,4,4,3,3,3.5};
    for (int k=0;k<ids.size();++k) {
      int id=ids[k]; const auto &s=packet_slots[id]; const auto &p=s.value;
      if (!p.alive || (p.kind==3 && double(s.d.get("expires_at",0.))<=time)) continue;
      Vector2 pos=p.updated==revision ? p.previous+perception_delta(p.previous,p.p)*alpha : p.p;
      double radius=radii[p.kind]*std::clamp(std::sqrt(p.amount/.3),.8,1.7)*zoom;
      if (perception_delta(at,pos).length()*zoom<=std::max(radius+3,7.)+10) {
        Dictionary candidate; candidate["index"]=id; candidate["packet"]=snapshot(id); out.push_back(candidate);
      }
    }
    return out;
  }
  double pool_material() const {
    double total=0;
    for (const auto &s : packet_slots) if (s.value.alive && s.value.kind!=1 && s.value.kind!=3)
      total+=s.value.amount+double(s.d.get("product",0.));
    return total;
  }

  void packet_begin(Array particles) {
    if (pool_enabled) { packet_frame=true; return; }
    packet_source = particles;
    packet_frame = true;
    ++packet_epoch;
    packet_slots.resize(particles.size());
    packet_positions.resize(particles.size());
    packet_touched.clear();
    ++render_epoch; render_packets.resize(particles.size());
    render_source=particles; render_count=particles.size(); render_revision=-1;
    packed_render_state=true;
  }
  PackedVector2Array get_packet_positions() const { return packet_positions; }
  void invalidate_particle_render(int id=-1) {
    if (id>=0) {
      if (id<int(render_packets.size())) render_packets[id].epoch=0;
    } else { render_revision=-1; packed_render_state=false; }
  }
  void particle_render_ready(Array particles,int revision) {
    if (pool_enabled) return;
    if (!packed_render_state || !UtilityFunctions::is_same(render_source,particles)) {
      invalidate_particle_render(); return;
    }
    render_packets.resize(particles.size()); render_count=particles.size();
    render_revision=revision;
  }
  void packet_end() {
    if (pool_enabled) { packet_frame=true; return; }
    if (!packet_frame) return;
    for (int id : packet_touched) {
      auto &slot=packet_slots[id]; auto &a=slot.value; const auto &b=slot.original;
      Dictionary &d=slot.d;
      if (slot.moved) {
        auto &pose=render_packets[id];
        pose.p=a.p; pose.previous=a.previous; pose.angle=a.angle;
        pose.previous_angle=a.previous_angle; pose.kind=a.kind; pose.updated=a.updated;
        pose.alive=a.alive; pose.amount=slot.chemical ? a.amount : double(d[keys.amount]);
        pose.epoch=render_epoch;
      }
      // Transport mirrors are already current for compatibility observers.
      // Publish only chemical changes; geometry/velocity were shared numerically.
      if (slot.chemical && a.v!=b.v) d[keys.v]=a.v;
      if (slot.chemical) {
        if (a.kind!=b.kind) d[keys.kind]=a.kind;
        if (a.amount!=b.amount) d[keys.amount]=a.amount;
        if (a.capacity!=b.capacity) d[keys.capacity]=a.capacity;
        if (a.alive!=b.alive) d[keys.alive]=a.alive;
        if (a.reacted!=b.reacted) d[keys.reacted]=a.reacted;
        if (a.chemical_at!=b.chemical_at || (!b.has_clock && slot.has_chemical_clock)) d[keys.chemical_at]=a.chemical_at;
        // Activity/radius are private scratch values in this numeric path.
      }
    }
    packet_frame=false;
    packet_source = Array();
  }
  void obstacle_configure(Array segments, Dictionary source_bins) {
    stems.clear();
    for (int i = 0; i < segments.size(); ++i) {
      Dictionary segment = segments[i];
      stems.push_back({segment["a"], segment["b"], double(segment["r"])});
    }
    for (int i = 0; i < 640; ++i) {
      stem_bins[i].clear();
      Array ids = source_bins.get(i, Array());
      for (int j = 0; j < ids.size(); ++j)
        stem_bins[i].push_back(int(ids[j]));
    }
  }
  bool obstacle_particles(Array particles, Array ids, int revision, bool bounds) {
    bool changed = false;
    std::vector<int> candidates;
    for (int index = 0; index < ids.size(); ++index) {
      Dictionary packet = particles[int(ids[index])];
      if (!bool(packet[keys.alive]) || int(packet.get(keys.kind, 0)) == 3 ||
          int(packet.get(keys.updated, -1)) != revision)
        continue;
      Vector2 p = packet[keys.previous], end = packet[keys.p],
              travel = delta(p, end), velocity = packet[keys.v];
      candidates.clear();
      if (stem_key(p) == stem_key(end))
        candidates = stem_bins[stem_key(p)];
      else {
        Vector2 finish = p + travel;
        int lx = std::floor((std::min(p.x, finish.x) - 4) / 128),
            hx = std::floor((std::max(p.x, finish.x) + 4) / 128);
        int ly = std::floor((std::min(p.y, finish.y) - 4) / 128),
            hy = std::floor((std::max(p.y, finish.y) + 4) / 128);
        for (int y = ly; y <= hy && y < ly + 20; ++y)
          for (int x = lx; x <= hx && x < lx + 32; ++x)
            for (int id : stem_bins[mod(y, 20) * 32 + mod(x, 32)])
              if (std::find(candidates.begin(), candidates.end(), id) ==
                  candidates.end())
                candidates.push_back(id);
      }
      if (candidates.empty())
        continue;
      bool touched = false;
      for (int iteration = 0; iteration < 6; ++iteration) {
        bool pushed = false;
        for (int id : candidates) {
          const auto &s = stems[id];
          Vector2 a = p + delta(p, s.a), b = a + s.b - s.a;
          double reach = 4 + s.radius + .2;
          if (bounds && (p.x < std::min(a.x,b.x)-reach || p.x > std::max(a.x,b.x)+reach ||
              p.y < std::min(a.y,b.y)-reach || p.y > std::max(a.y,b.y)+reach)) continue;
          Vector2 d = p - closest_stem(p, a, b);
          if (d.length_squared() >= reach * reach)
            continue;
          Vector2 n = d.length_squared() > .000001
                          ? d.normalized()
                          : (b - a).orthogonal().normalized();
          p += n * (reach - d.length());
          velocity -= n * std::min(0., double(velocity.dot(n)));
          pushed = true;
          touched = true;
        }
        if (!pushed)
          break;
      }
      for (int iteration = 0; iteration < 4; ++iteration) {
        double earliest = 2.;
        Vector2 normal;
        for (int id : candidates) {
          const auto &s = stems[id];
          Vector2 a = p + delta(p, s.a), b = a + s.b - s.a;
          double reach = 4 + s.radius + .05;
          Vector2 end = p + travel;
          if (bounds && (std::max(p.x,end.x) < std::min(a.x,b.x)-reach ||
              std::min(p.x,end.x) > std::max(a.x,b.x)+reach ||
              std::max(p.y,end.y) < std::min(a.y,b.y)-reach ||
              std::min(p.y,end.y) > std::max(a.y,b.y)+reach)) continue;
          double t = stem_time(p, travel, a, b, 4 + s.radius + .05);
          if (t >= earliest)
            continue;
          earliest = t;
          Vector2 at = p + travel * t;
          normal = (at - closest_stem(at, a, b)).normalized();
        }
        if (earliest > 1) {
          p += travel;
          break;
        }
        touched = true;
        p += travel * earliest + normal * .08;
        travel *= 1 - earliest;
        travel -= normal * std::min(0., double(travel.dot(normal)));
        velocity -= normal * std::min(0., double(velocity.dot(normal)));
        if (travel.length_squared() < .000001)
          break;
      }
      if (touched) {
        packet[keys.p] = wrapv(p);
        packet[keys.previous] = wrapv(p);
        packet[keys.v] = velocity;
        changed = true;
      }
    }
    return changed;
  }
  Array membrane_mesh(const PackedVector2Array &outline) {
    // Same four explicit rings and triangles as the reference artwork. Batching
    // removes temporary script arrays; there is no silhouette or LOD change.
    static const double rings[] = {.76,.90,1.,1.95};
    int n = outline.size();
    PackedVector2Array vertices, uv;
    PackedColorArray colors;
    PackedInt32Array indices;
    vertices.resize(1+4*n); uv.resize(1+4*n); colors.resize(1+4*n);
    indices.resize(n*21);
    Vector2 *v = vertices.ptrw(), *t = uv.ptrw();
    Color *c = colors.ptrw(); int32_t *ix = indices.ptrw();
    v[0] = Vector2(); t[0] = Vector2(); c[0] = Color(.5,.5,0,1);
    for (int ring=0;ring<4;++ring)
      for (int i=0;i<n;++i) {
        int at = 1+ring*n+i;
        v[at] = outline[i]*rings[ring]; t[at] = Vector2(rings[ring],0);
        Vector2 normal = outline[i].normalized();
        c[at] = Color(normal.x*.5+.5,normal.y*.5+.5,0,1);
      }
    int cursor = 0;
    for (int i=0;i<n;++i) {
      int next = (i+1)%n;
      ix[cursor++] = 0; ix[cursor++] = 1+i; ix[cursor++] = 1+next;
      for (int ring=1;ring<4;++ring) {
        int a=1+(ring-1)*n+i, b=1+(ring-1)*n+next,
            c=1+ring*n+i, d=1+ring*n+next;
        for (int index : {a,c,d,a,d,b}) ix[cursor++] = index;
      }
    }
    Array out; out.resize(Mesh::ARRAY_MAX);
    out[Mesh::ARRAY_VERTEX] = vertices; out[Mesh::ARRAY_TEX_UV] = uv;
    out[Mesh::ARRAY_COLOR] = colors; out[Mesh::ARRAY_INDEX] = indices;
    return out;
  }
  Array membrane_compress(PackedVector2Array points, PackedVector2Array previous,
                          double angle, double depth, double radius) {
    double before = 0, after = 0;
    int count = points.size();
    for (int i=0;i<count;++i) before += points[i].cross(points[(i+1)%count])*.5;
    for (int i=0;i<count;++i) {
      double distance = std::abs(wrap(points[i].angle()-angle+PI,TAU)-PI);
      if (distance >= .65) continue;
      double weight = .5+.5*std::cos(PI*distance/.65);
      Vector2 corrected = points[i].normalized()*std::max(radius*.58,points[i].length()-depth*weight);
      previous.set(i,previous[i]+(corrected-points[i]));
      points.set(i,corrected);
    }
    for (int i=0;i<count;++i) after += points[i].cross(points[(i+1)%count])*.5;
    double scale = std::sqrt(std::max(.001,before)/std::max(.001,after)), maximum = 0;
    for (int i=0;i<count;++i) {
      Vector2 corrected = points[i]*scale;
      previous.set(i,previous[i]+(corrected-points[i]));
      points.set(i,corrected);
      maximum = std::max(maximum,double(corrected.length()));
    }
    Array result;
    result.push_back(points); result.push_back(previous); result.push_back(maximum);
    return result;
  }
  Array membrane_edges(PackedVector2Array points,
                       const PackedFloat32Array &lengths,
                       PackedFloat32Array lambda, double alpha) {
    Vector2 *p = points.ptrw();
    float *l = lambda.ptrw();
    int count = points.size();
    for (int i = 0; i < count; ++i) {
      int j = (i + 1) % count;
      Vector2 d = p[j] - p[i];
      double length = d.length();
      if (length < .0001)
        continue;
      double dl = (-(length - lengths[i]) - alpha * l[i]) / (2 + alpha);
      l[i] += dl;
      p[i] -= d / length * dl;
      p[j] += d / length * dl;
    }
    Array out;
    out.push_back(points);
    out.push_back(lambda);
    return out;
  }
  Array membrane_area(PackedVector2Array points, double lambda, double alpha,
                      double target) {
    int count = points.size();
    std::vector<Vector2> gradients(count);
    double denominator = alpha, area = 0;
    for (int i = 0; i < count; ++i) {
      Vector2 next = points[(i + 1) % count],
              prev = points[(i + count - 1) % count];
      area += points[i].cross(next) * .5;
      gradients[i] = Vector2(next.y - prev.y, prev.x - next.x) * .5;
      denominator += gradients[i].length_squared();
    }
    double dl =
        (-(area - target) - alpha * lambda) / std::max(denominator, .0001);
    lambda += dl;
    Vector2 *p = points.ptrw();
    for (int i = 0; i < count; ++i)
      p[i] += gradients[i] * dl;
    Array out;
    out.push_back(points);
    out.push_back(lambda);
    return out;
  }
  Array render_particles(Array particles, TypedArray<int64_t> ids, Array bodies,
                         Vector2 camera, Vector2 half, double alpha,
                         int revision, PackedInt32Array capacities, bool cache) {
    struct Body {
      Vector2 p;
      double angle, extent;
      PackedVector2Array outline;
      Object *object;
    };
    std::vector<Body> cells;
    std::array<std::vector<int>, 640> near;
    for (int i = 0; i < bodies.size(); ++i) {
      Object *o = bodies[i];
      if (bool(o->get("dead")) || double(o->get("activity")) <= 0)
        continue;
      Body b;
      b.object = o;
      Vector2 previous = o->get("previous_position"),
              position = o->get("position");
      b.p = previous + delta(previous, position) * alpha;
      double old = o->get("previous_angle");
      b.angle =
          old + (wrap(double(o->get("angle")) - old + PI, TAU) - PI) * alpha;
      b.extent = o->call("extent");
      Object *membrane = o->get("membrane");
      b.outline = membrane->call("outline");
      int id = cells.size();
      cells.push_back(b);
      int lx = std::floor((b.p.x - b.extent - 8) / 128),
          ly = std::floor((b.p.y - b.extent - 8) / 128),
          hx = std::floor((b.p.x + b.extent + 8) / 128),
          hy = std::floor((b.p.y + b.extent + 8) / 128);
      for (int x = lx; x < std::min(hx + 1, lx + 32); ++x)
        for (int y = ly; y < std::min(hy + 1, ly + 20); ++y)
          near[mod(y, 20) * 32 + mod(x, 32)].push_back(id);
    }
    auto &instances=render_instances;
    for (auto &batch : instances) batch.clear();
    if (!pool_enabled && cache && (render_revision!=revision || render_count!=particles.size() ||
                  !UtilityFunctions::is_same(render_source,particles))) {
      render_source=particles; render_revision=revision; render_count=particles.size();
      ++render_epoch; render_packets.resize(particles.size());
    }
    static const double radii[] = {4, 2.5, 3, 2.5, 5, 3, 4, 4, 3, 3, 3.5};
    for (int k = 0; k < ids.size(); ++k) {
      int id=ids[k];
      RenderPacket fresh, *pose=pool_enabled ? &fresh : cache ? &render_packets[id] : &fresh;
      if (pool_enabled) {
        const auto &v=packet_slots[id].value;
        pose->p=v.p; pose->previous=v.previous; pose->angle=v.angle; pose->previous_angle=v.previous_angle;
        pose->amount=v.amount; pose->kind=v.kind; pose->alive=v.alive; pose->updated=v.updated;
      } else if (!cache || pose->epoch!=render_epoch) {
        Dictionary d=particles[id];
        pose->p=d[keys.p]; pose->previous=d[keys.previous];
        pose->angle=d[keys.angle]; pose->previous_angle=d[keys.previous_angle];
        pose->amount=d[keys.amount]; pose->kind=int(d[keys.kind]);
        pose->alive=d[keys.alive]; pose->updated=int(d.get(keys.updated,-1));
        pose->epoch=render_epoch;
      }
      if (!pose->alive) continue;
      Vector2 at=pose->p;
      double heading=pose->angle;
      if (pose->updated == revision) {
        Vector2 previous = pose->previous;
        at = previous + delta(previous, at) * alpha;
        double old = pose->previous_angle;
        heading = old + (wrap(heading - old + PI, TAU) - PI) * alpha;
      }
      // Dissolved pheromones are drawn at their true position, even inside cells.
      if (pose->kind != 3) {
        for (int c : near[mod(int(std::floor(at.y / 128)), 20) * 32 +
                          mod(int(std::floor(at.x / 128)), 32)]) {
          const Body &b = cells[c];
          Vector2 d = delta(b.p, at);
          double len = d.length();
          if (len * len > std::pow(b.extent + 8, 2))
            continue;
          double angle = d.angle(), local = angle - b.angle;
          Vector2 ray(std::cos(local), std::sin(local));
          int guess = int(std::floor(wrap(local, TAU) / TAU * 28)) * 4;
          double radius = -1;
          for (int phase = guess - 4; phase < guess + 8; ++phase) {
            int n = mod(phase, b.outline.size());
            Vector2 point = b.outline[n],
                    edge = b.outline[(n + 1) % b.outline.size()] - point;
            double denom = ray.cross(edge);
            if (std::abs(denom) < .000001)
              continue;
            double t = point.cross(ray) / denom,
                   distance = point.cross(edge) / denom;
            if (t >= -.00001 && t <= 1.00001 && distance >= 0) {
              radius = distance;
              break;
            }
          }
          if (radius < 0)
            radius = double(b.object->call(
                "support", local + double(b.object->get("angle"))));
          radius += 7;
          if (len < radius)
            at = b.p + Vector2(std::cos(angle), std::sin(angle)) * radius;
        }
      }
      at = delta(camera, at);
      if (std::abs(at.x) > half.x + 20 || std::abs(at.y) > half.y + 20)
        continue;
      int kind = pose->kind;
      double diameter =
          2 * radii[kind] *
          std::clamp(std::sqrt(pose->amount / .3), .8, 1.7);
      float co = std::cos(heading) * diameter,
            si = std::sin(heading) * diameter;
      instances[kind].push_back({co, -si, 0, at.x, si, co, 0, at.y, 1, 1, 1,
                                 (kind == 1 || kind == 3) ? 0.6f : 1.0f});
    }
    Array out;
    PackedInt32Array counts;
    counts.resize(11);
    for (int kind = 0; kind < 11; ++kind) {
      int count = instances[kind].size(),
          capacity = std::max(1, capacities[kind]);
      while (capacity < count)
        capacity *= 2;
      PackedFloat32Array data;
      data.resize(capacity * 12);
      float *w = data.ptrw();
      for (int i = 0; i < count; ++i)
        std::copy(instances[kind][i].begin(), instances[kind][i].end(),
                  w + i * 12);
      out.push_back(data);
      counts.set(kind, count);
    }
    out.push_back(counts);
    return out;
  }
  Vector2i contacts_pass(Array bodies, Callable pair, double dt, bool deform) {
    struct Body { Object *object, *membrane; Vector2 p; double reach; bool dead, active; };
    std::vector<Body> cells;
    for (int i=0;i<bodies.size();++i) {
      Object *o = bodies[i], *m = o->get("membrane");
      cells.push_back({o,m,o->get("position"),double(m->get("maximum_radius"))*1.05,
                       bool(o->get("dead")),double(o->get("activity"))>0});
    }
    int checks = 0, hits = 0;
    for (int i=0;i<int(cells.size());++i) {
      auto &a = cells[i];
      if (a.dead) continue;
      for (int j=i+1;j<int(cells.size());++j) {
        auto &b = cells[j];
        if (b.dead || (!a.active && !b.active)) continue;
        ++checks;
        double reach = a.reach+b.reach+.2;
        if (delta(a.p,b.p).length_squared() > reach*reach) continue;
        if (bool(pair.call(a.object,b.object,dt,deform))) {
          ++hits;
          // Only this pair can move/dent during the unchanged narrow phase.
          // Refresh both immediately, retaining sequential traversal exactly.
          a.p = a.object->get("position"); b.p = b.object->get("position");
          a.reach = double(a.membrane->get("maximum_radius"))*1.05;
          b.reach = double(b.membrane->get("maximum_radius"))*1.05;
        }
      }
    }
    return Vector2i(checks,hits);
  }
  double coarse_feed(Array particles, TypedArray<int64_t> ids, Object *body, Dictionary mouth,
                     Dictionary rates, Vector2 camera, Vector2 half,
                     Ref<RandomNumberGenerator> rng, Object *habitat) {
    Vector2 center = body->get("position");
    double radius = rates["radius"], dt = rates["dt"], intake = rates["intake"],
           substrate = body->get("substrate"), eaten = body->get("eaten"),
           foreign = body->get("foreign_intake"), oxygen = body->get("oxygen"),
           carbon = body->get("carbon"), gut = body->call("gut_capacity"),
           oxygen_cap = body->call("oxygen_capacity"), carbon_cap = 30 * double(body->call("growth_scale"));
    int owner = body->get("id");
    bool photo = int(body->call("count","photosynthesis")) > 0;
    bool solid = bool(habitat->get("enabled")) && !bool(habitat->get("particles_permeable"));
    for (int k=0;k<ids.size();++k) {
      auto p = access(particles,int64_t(ids[k]));
      int kind = p.kind();
      if (!p.alive() || (kind != 0 && kind != 1 && kind != 5)) continue;
      Vector2 at = p.position();
      if (activity(at,camera,half) > 0 || delta(center,at).length() > radius) continue;
      double capacity = 0, rate = 0;
      if (kind == 0 && !mouth.is_empty()) {
        capacity = std::max(0.,gut-substrate); rate = rates["nutrient"];
      } else if (kind == 1) {
        capacity = std::max(0.,oxygen_cap-oxygen); rate = rates["oxygen"];
      } else if (kind == 5 && photo) {
        capacity = std::max(0.,carbon_cap-carbon); rate = rates["carbon"];
      }
      if (capacity <= 0 || rng->randf() >= 1-std::exp(-std::max(0.,rate)*std::max(0.,dt))) continue;
      // Only accepted encounters need the original swept solid-path check.
      if (solid) {
        Array moved = habitat->call("move",center,at,Vector2(),0.,Array());
        if (bool(moved[2])) continue;
      }
      double taken = std::min(p.amount(),capacity);
      p.set(keys.amount,p.amount()-taken);
      invalidate_particle_render(int64_t(ids[k]));
      if (p.amount() <= .000001) p.set(keys.alive,false);
      if (kind == 1) oxygen += taken;
      else if (kind == 5) {
        carbon += taken;
        if (int(p.get("owner",-1)) != owner) foreign += taken;
      } else {
        substrate += taken; eaten += taken; intake += taken;
        if (int(p.get("owner",-1)) != owner) foreign += taken;
        body->call("consumed",mouth,taken);
      }
    }
    body->set("substrate",substrate); body->set("eaten",eaten);
    body->set("foreign_intake",foreign); body->set("oxygen",oxygen); body->set("carbon",carbon);
    return intake;
  }
  void feed(Array particles, TypedArray<int64_t> ids, Object *body, Dictionary organ,
            Vector2 camera, Vector2 half) {
    bool mouth = !organ.is_empty();
    Vector2 center = mouth ? Vector2(body->call("pore_center",organ)) : Vector2(body->get("position"));
    double reach = mouth ? double(body->call("pore_radius",organ)) + 8 : 0;
    double substrate = body->get("substrate"), eaten = body->get("eaten"),
           foreign = body->get("foreign_intake"), oxygen = body->get("oxygen"),
           carbon = body->get("carbon"), gut = body->call("gut_capacity"),
           oxygen_cap = body->call("oxygen_capacity"), carbon_cap = 30 * double(body->call("growth_scale"));
    int owner = body->get("id");
    bool photo = int(body->call("count","photosynthesis")) > 0;
    double angle = body->get("angle"), extent = body->call("extent");
    Object *membrane = body->get("membrane");
    PackedVector2Array outline = membrane->get("points");
    for (int k = 0; k < ids.size(); ++k) {
      auto p = access(particles,int64_t(ids[k]));
      int kind = p.kind();
      if (!p.alive() || (mouth ? kind != 0 : kind != 1 && kind != 5)) continue;
      Vector2 at = p.position();
      if (activity(at,camera,half) <= 0) continue;
      Vector2 d = delta(center,at);
      double distance = d.length(), taken = 0;
      bool handled = false;
      if (mouth && distance <= reach) {
        handled = true;
        taken = std::min(p.amount(), std::max(0.,gut-substrate));
        substrate += taken;
        eaten += taken;
        if (int(p.get("owner",-1)) != owner) foreign += taken;
        if (taken > 0) body->call("consumed",organ,taken);
      } else if (!mouth && kind == 5 && photo && distance < extent+18) {
        handled = true;
        taken = std::min(p.amount(), std::max(0.,carbon_cap-carbon));
        carbon += taken;
        if (int(p.get("owner",-1)) != owner) foreign += taken;
      } else if (!mouth && kind == 1) {
        // Same ordered radial ray intersection as Cell.support(), without a
        // VM call for every oxygen packet.
        double local = d.angle()-angle, radius = 0;
        Vector2 ray(std::cos(local), std::sin(local));
        bool found = false;
        for (int i=0;i<outline.size();++i) {
          Vector2 a = outline[i], edge = outline[(i+1)%outline.size()]-a;
          double denom = ray.cross(edge);
          if (std::abs(denom) < .00001) continue;
          double along = a.cross(ray)/denom, length = a.cross(edge)/denom;
          if (along >= 0 && along <= 1 && length >= 0) {
            radius = a.lerp(outline[(i+1)%outline.size()],along).length();
            found = true; break;
          }
        }
        if (!found) {
          double phase = wrap(local,TAU)/TAU*outline.size();
          int i = int(phase);
          radius = outline[i].lerp(outline[(i+1)%outline.size()],phase-i).length();
        }
        if (distance < radius+14) {
          handled = true;
          taken = std::min(p.amount(), std::max(0.,oxygen_cap-oxygen));
          oxygen += taken;
        }
      }
      if (!handled) continue;
      if (taken > 0) p.set(keys.amount,p.amount()-taken);
      invalidate_particle_render(int64_t(ids[k]));
      if (p.amount() <= .000001) p.set(keys.alive,false);
    }
    body->set("substrate",substrate); body->set("eaten",eaten);
    body->set("foreign_intake",foreign); body->set("oxygen",oxygen); body->set("carbon",carbon);
  }
  void exclude(Array particles, TypedArray<int64_t> ids, Array bodies,
               Vector2 camera, Vector2 half) {
    struct Body {
      Vector2 p;
      double angle, extent;
      PackedVector2Array outline;
      Object *object;
    };
    std::vector<Body> cells;
    std::array<std::vector<int>, 640> near;
    for (int i = 0; i < bodies.size(); ++i) {
      Object *o = bodies[i];
      if (bool(o->get("dead")) || double(o->get("activity")) <= 0)
        continue;
      Body b;
      b.object = o;
      b.p = o->get("position");
      b.angle = o->get("angle");
      b.extent = o->call("extent");
      Object *membrane = o->get("membrane");
      b.outline = membrane->call("outline");
      int id = cells.size();
      cells.push_back(b);
      int lx = std::floor((b.p.x - b.extent - 8) / 128),
          ly = std::floor((b.p.y - b.extent - 8) / 128),
          hx = std::floor((b.p.x + b.extent + 8) / 128),
          hy = std::floor((b.p.y + b.extent + 8) / 128);
      for (int x = lx; x < std::min(hx + 1, lx + 32); ++x)
        for (int y = ly; y < std::min(hy + 1, ly + 20); ++y)
          near[mod(y, 20) * 32 + mod(x, 32)].push_back(id);
    }
    for (int k = 0; k < ids.size(); ++k) {
      int id = ids[k];
      auto p = access(particles,id);
      if (!p.alive() || p.kind() == 3)
        continue;
      Vector2 at = p.position();
      if (activity(at, camera, half) <= 0)
        continue;
      bool changed = false;
      for (int it = 0; it < 3; ++it) {
        bool moved = false;
        auto candidates = near[mod(int(std::floor(at.y / 128)), 20) * 32 +
                               mod(int(std::floor(at.x / 128)), 32)];
        for (int c : candidates) {
          const Body &b = cells[c];
          Vector2 d = delta(b.p, at);
          double len = d.length();
          if (len * len > std::pow(b.extent + 8, 2))
            continue;
          double angle = len * len > .0001 ? d.angle() : id * 2.4,
                 local = angle - b.angle;
          Vector2 ray(std::cos(local), std::sin(local));
          int guess = int(std::floor(wrap(local, TAU) / TAU * 28)) * 4;
          double radius = -1;
          for (int phase = guess - 4; phase < guess + 8; ++phase) {
            int n = mod(phase, b.outline.size());
            Vector2 point = b.outline[n],
                    edge = b.outline[(n + 1) % b.outline.size()] - point;
            double denom = ray.cross(edge);
            if (std::abs(denom) < .000001)
              continue;
            double t = point.cross(ray) / denom,
                   distance = point.cross(edge) / denom;
            if (t >= -.00001 && t <= 1.00001 && distance >= 0) {
              radius = distance;
              break;
            }
          }
          if (radius < 0)
            radius = double(b.object->call("support", angle));
          radius += 7;
          if (len >= radius - .001)
            continue;
          at = wrapv(b.p + Vector2(std::cos(angle), std::sin(angle)) * radius);
          moved = changed = true;
        }
        if (!moved)
          break;
      }
      if (changed) {
        invalidate_particle_render(id);
        p.set(keys.p,at);
        if (pool_enabled) packet_positions.set(id,at);
        p.set(keys.previous,at);
      }
    }
  }
  Array compact_particles(Array particles, int cursor) {
    Array kept;
    int before = 0;
    for (int i=0;i<particles.size();++i) {
      Dictionary p = particles[i];
      if (!bool(p[keys.alive])) continue;
      if (i < cursor) ++before;
      kept.push_back(p);
    }
    Array out; out.push_back(kept); out.push_back(kept.is_empty() ? 0 : before%kept.size());
    return out;
  }
  TypedArray<int64_t> background_ids(Array particles, int cursor, int visits,
                                      Vector2 camera, Vector2 half, double clock) {
    TypedArray<int64_t> out;
    for (int k=0;k<visits;++k) {
      int id = (cursor+k)%(pool_enabled ? packet_slots.size() : particles.size());
      if (packet_frame) {
        const auto &p=packet(id).value;
        if (p.alive && activity(p.p,camera,half)<=0 && p.transport_at<clock) out.push_back(id);
      } else {
        Dictionary p = particles[id];
        if (bool(p[keys.alive]) && activity(p[keys.p],camera,half) <= 0 &&
            double(p.get(keys.transport_at,0.)) < clock) out.push_back(id);
      }
    }
    return out;
  }
  void settle_transport(Array particles, TypedArray<int64_t> ids, bool background) {
    for (int k=0;k<ids.size();++k) {
      if (packet_frame) {
        auto &slot=packet(ids[k]); auto &p=slot.value;
        if (background || p.jump) {
          if (!pool_enabled && !slot.moved) p.angle=slot.d[keys.angle];
          p.previous=p.p; p.previous_angle=p.angle;
          if (!background) p.jump=false;
          if (pool_enabled) { slot.mask|=JUMP; continue; }
          slot.d[keys.previous]=p.previous;
          slot.d[keys.previous_angle]=p.previous_angle;
          if (!background) slot.d[keys.transport_jump]=p.jump;
        }
        continue;
      }
      Dictionary p = particles[int64_t(ids[k])];
      if (background || bool(p.get(keys.transport_jump,false))) {
        p[keys.previous] = p[keys.p];
        p[keys.previous_angle] = p[keys.angle];
        if (!background) p[keys.transport_jump] = false;
      }
    }
  }
  int transport_dictionary(Array particles, TypedArray<int64_t> ids,
                const PackedVector2Array &flow, Vector2 camera, Vector2 half,
                double dt, int revision, Ref<RandomNumberGenerator> rng,
                double clock, bool background) {
    int count = 0;
    for (int k = 0; k < ids.size(); ++k) {
      Dictionary p = particles[int64_t(ids[k])];
      if (!bool(p[keys.alive])) continue;
      Vector2 at = p[keys.p];
      if ((activity(at, camera, half) > 0) == background) continue;
      double t = clock < 0 ? dt : std::max(0., clock - double(p.get(keys.transport_at, clock-dt)));
      if (t <= 0) continue;
      ++count;
      bool tracer = int(p[keys.kind]) == 3;
      Vector2 v = tracer ? Vector2() : Vector2(p[keys.v]);
      double angle = p[keys.angle];
      p[keys.updated] = revision;
      p[keys.previous] = at;
      p[keys.transport_jump] = t > .05;
      if (clock >= 0) p[keys.transport_at] = clock;
      // Keep RNG call order explicit, matching the reference backend.
      double nx = rng->randfn(0, 1), ny = rng->randfn(0, 1);
      if (t <= .05) {
        at = wrapv(at + (v + sample(flow, at)) * t);
      } else {
        int steps = std::clamp(int(std::ceil(t / .25)), 1, 8);
        double h = t / steps, damping = std::exp(-.8*h);
        Vector2 launch = v;
        for (int j = 0; j < steps; ++j) {
          Vector2 midpoint = at + sample(flow, at)*(h*.5) + launch*((1-std::exp(-.4*h))/.8);
          at = wrapv(at + sample(flow, midpoint)*h + launch*((1-damping)/.8));
          launch *= damping;
        }
      }
      p[keys.p] = wrapv(at + Vector2(nx, ny)*std::sqrt((tracer ? 240 : 12)*t));
      p[keys.v] = v * std::exp(-t * .8);
      p[keys.age] = double(p[keys.age]) + t;
      p[keys.previous_angle] = angle;
      angle = wrap(angle + double(p[keys.spin])*t + rng->randfn(0, 1)*std::sqrt(1.2*t) + PI, TAU) - PI;
      if (tracer) angle = 0;
      p[keys.angle] = angle;
      p[keys.direction] = tracer ? Vector2() : Vector2(std::cos(angle), std::sin(angle));
    }
    return count;
  }
  int transport_pool_parallel(TypedArray<int64_t> ids,const PackedVector2Array &flow,
      Vector2 camera,Vector2 half,double dt,int revision,
      Ref<RandomNumberGenerator> rng,double clock,bool background) {
    transport_jobs_buffer.clear();
    transport_seen.resize(packet_slots.size(),0);
    if (++transport_epoch==0) { std::fill(transport_seen.begin(),transport_seen.end(),0); ++transport_epoch; }
    // All engine-array access and RNG calls stay on the submitting thread.
    // The stream is exactly x, y, angle for each eligible packet, in ID order.
    for (int k=0,n=ids.size();k<n;++k) {
      int id=int64_t(ids[k]);
      if (transport_seen[id]==transport_epoch) return -1; // Duplicate diagnostic IDs require sequential semantics.
      transport_seen[id]=transport_epoch;
      auto &slot=packet_slots[id];auto &p=slot.value;
      if (!p.alive || ((activity(p.p,camera,half)>0)==background)) continue;
      double previous=slot.has_transport_clock ? p.transport_at : clock-dt;
      double t=clock<0 ? dt : std::max(0.,clock-previous);
      if (t<=0) continue;
      transport_jobs_buffer.push_back({id,t,0,0,0});
    }
    if (transport_jobs_buffer.empty()) return 0;
    for (auto &job:transport_jobs_buffer) {
      job.nx=rng->randfn(0,1);job.ny=rng->randfn(0,1);job.angular=rng->randfn(0,1);
    }
    // Obtain stable COW views before dispatch; no resizing or engine calls
    // happen on workers. Each ordinary scheduler ID is unique.
    const Vector2 *velocities=flow.ptr();
    Vector2 *positions=packet_positions.ptrw();
    auto sample_flow=[&](Vector2 p) {
      p=wrapv(p)/64-Vector2(.5,.5);
      int x=std::floor(p.x),y=std::floor(p.y);
      return velocities[node(x,y)].lerp(velocities[node(x+1,y)],p.x-x)
        .lerp(velocities[node(x,y+1)].lerp(velocities[node(x+1,y+1)],p.x-x),p.y-y);
    };
    SimulationWorkers::shared().run(transport_jobs_buffer.size(),simulation_threads,[&](size_t begin,size_t end) {
      for (size_t k=begin;k<end;++k) {
        const auto &job=transport_jobs_buffer[k];double t=job.dt;
        auto &slot=packet_slots[job.id];auto &p=slot.value;
        Vector2 at=p.p,v=p.kind==3 ? Vector2() : p.v;
        bool tracer=p.kind==3;double angle=p.angle;
        p.updated=revision;p.previous=at;p.jump=t>.05;
        if (clock>=0) {p.transport_at=clock;slot.has_transport_clock=true;}
        if (t<=.05) at=wrapv(at+(v+sample_flow(at))*t);
        else {
          int steps=std::clamp(int(std::ceil(t/.25)),1,8);
          double h=t/steps,damping=std::exp(-.8*h);Vector2 launch=v;
          for (int j=0;j<steps;++j) {
            Vector2 midpoint=at+sample_flow(at)*(h*.5)+launch*((1-std::exp(-.4*h))/.8);
            at=wrapv(at+sample_flow(midpoint)*h+launch*((1-damping)/.8));
            launch*=damping;
          }
        }
        p.p=wrapv(at+Vector2(job.nx,job.ny)*std::sqrt((tracer ? 240 : 12)*t));
        p.v=v*std::exp(-t*.8);p.age=p.age+t;p.previous_angle=angle;
        angle=wrap(angle+p.spin*t+job.angular*std::sqrt(1.2*t)+PI,TAU)-PI;
        if (tracer) angle=0;
        p.angle=angle;p.dir=tracer ? Vector2() : Vector2(std::cos(angle),std::sin(angle));
        slot.moved=true;slot.mask|=UPDATED|JUMP;positions[job.id]=p.p;
      }
    });
    ++transport_jobs;
    return transport_jobs_buffer.size();
  }
  int transport(Array particles, TypedArray<int64_t> ids,
                const PackedVector2Array &flow, Vector2 camera, Vector2 half,
                double dt, int revision, Ref<RandomNumberGenerator> rng,
                double clock, bool background) {
    // Keep the unscoped reference kernel unchanged for honest ablations.
    if (!packet_frame)
      return transport_dictionary(particles,ids,flow,camera,half,dt,revision,rng,clock,background);
    if (pool_enabled && simulation_threads>1 && parallel_transport && ids.size()>=4096 && !liquid.enabled && !parcels.enabled) {
      int result=transport_pool_parallel(ids,flow,camera,half,dt,revision,rng,clock,background);
      if (result>=0) return result;
    }
    int count = 0;
    if (parcels.enabled && pool_enabled && background)
      parcels.prepare(packet_slots,ids,flow,clock,dt,sample,wrapv);
    std::vector<int> liquid_ids;
    std::vector<Vector2> liquid_positions,liquid_motion;
    const int id_count=ids.size();
    for (int k = 0; k < id_count; ++k) {
      const int id=int64_t(ids[k]);
      PacketState local, *value;
      if (packet_frame) value=&packet(id).value;
      else {
        Dictionary d=particles[id];
        local.alive=d[keys.alive]; local.p=d[keys.p]; local.kind=int(d[keys.kind]);
        local.transport_at=d.get(keys.transport_at,clock-dt);
        local.v=d[keys.v]; local.angle=d[keys.angle]; local.age=d[keys.age]; local.spin=d[keys.spin];
        value=&local;
      }
      auto &p=*value;
      if (!p.alive) continue;
      Vector2 at=p.p;
      if ((activity(at,camera,half)>0)==background) continue;
      double previous_clock = packet_frame && !packet_slots[id].has_transport_clock ? clock-dt : p.transport_at;
      double t=clock<0 ? dt : std::max(0.,clock-previous_clock);
      if (t<=0) continue;
      ++count;
      if (packet_frame) load_transport(packet_slots[id]);
      bool tracer=p.kind==3;
      Vector2 v=tracer ? Vector2() : p.v;
      double angle=p.angle;
      p.updated=revision; p.previous=at; p.jump=t>.05;
      if (clock>=0) {
        p.transport_at=clock;
        if (packet_frame) packet_slots[id].has_transport_clock=true;
      }
      // Keep RNG call order explicit, matching the reference backend.
      double nx = rng->randfn(0, 1), ny = rng->randfn(0, 1);
      if (background && parcels.enabled && parcels.contains(id)) {
        at=wrapv(at+parcels.displacement(id));
      } else if (t <= .05) {
        at = wrapv(at + (v + sample(flow, at)) * t);
      } else {
        int steps = std::clamp(int(std::ceil(t / .25)), 1, 8);
        double h = t / steps, damping = std::exp(-.8*h);
        Vector2 launch = v;
        for (int j = 0; j < steps; ++j) {
          Vector2 midpoint = at + sample(flow, at)*(h*.5) + launch*((1-std::exp(-.4*h))/.8);
          at = wrapv(at + sample(flow, midpoint)*h + launch*((1-damping)/.8));
          launch *= damping;
        }
      }
      p.p = wrapv(at + Vector2(nx, ny)*std::sqrt((tracer ? 240 : 12)*t));
      p.v = v * std::exp(-t * .8);
      if (liquid.enabled && pool_enabled && !background && !tracer && std::abs(t-dt)<.000001) {
        liquid_ids.push_back(id);
        liquid_positions.push_back(p.previous);
        liquid_motion.push_back(delta(p.previous,p.p)/dt);
      }
      p.age = p.age + t;
      p.previous_angle = angle;
      angle = wrap(angle + p.spin*t + rng->randfn(0, 1)*std::sqrt(1.2*t) + PI, TAU) - PI;
      if (tracer) angle = 0;
      p.angle = angle;
      p.dir = tracer ? Vector2() : Vector2(std::cos(angle), std::sin(angle));
      if (packet_frame) {
        packet_slots[id].moved=true;
        packet_positions.set(id,p.p);
        auto &slot=packet_slots[id];
        if (pool_enabled) { slot.mask|=UPDATED|JUMP; continue; }
        Dictionary &d=slot.d;
        d[keys.updated]=p.updated; d[keys.previous]=p.previous; d[keys.transport_jump]=p.jump;
        if (clock>=0) d[keys.transport_at]=p.transport_at;
        d[keys.p]=p.p; d[keys.v]=p.v; d[keys.age]=p.age;
        d[keys.previous_angle]=p.previous_angle; d[keys.angle]=p.angle; d[keys.direction]=p.dir;
        slot.original.v=p.v;
      } else {
        Dictionary d=particles[id];
        d[keys.updated]=p.updated; d[keys.previous]=p.previous; d[keys.transport_jump]=p.jump;
        if (clock>=0) d[keys.transport_at]=p.transport_at;
        d[keys.p]=p.p; d[keys.v]=p.v; d[keys.age]=p.age;
        d[keys.previous_angle]=p.previous_angle; d[keys.angle]=p.angle; d[keys.direction]=p.dir;
      }
    }
    if (!liquid_ids.empty()) {
      liquid.solve(liquid_positions,liquid_motion,dt);
      for (int k=0;k<int(liquid_ids.size());++k) {
        int id=liquid_ids[k];auto &slot=packet_slots[id];auto &p=slot.value;
        p.p=wrapv(liquid_positions[k]);
        // Brownian/current velocity is imposed transport, not stored propulsion.
        // Keep only the solver's correction to the original imposed trajectory.
        Vector2 original_motion=delta(p.previous,packet_positions[id])/dt;
        p.v+=liquid_motion[k]-original_motion;
        packet_positions.set(id,p.p);
        slot.moved=true;
      }
    }
    return count;
  }
  Dictionary chemistry(Array particles, TypedArray<int64_t> ids,
                       PackedFloat32Array acid, Vector2 camera, Vector2 half,
                       double dt, int revision,
                       Ref<RandomNumberGenerator> rng, double clock, bool background, bool dirty_writes, bool collisions, bool tight_bounds, bool lazy_acid) {
    static const double radii[] = {4, 2.5, 3, 2.5, 5, 3, 4, 4, 3, 3, 3.5};
    static const double decay[] = {.003, .008, .006, 0.0,  .1, .001,
                                   .02,  .015, .008, .008, .08};
    static const char *names[] = {"decay", "combine", "recycle",   "detox",
                                  "spoil", "enzyme",  "neutralize"};
    std::array<int, 7> events{};
    Array neutralizations;
    PackedVector2Array reaction_points;
    double loss = 0, recycled = 0;
    double max_radius = 0;
    bool fine_contacts=liquid.enabled && pool_enabled && !background;
    auto &scratch=background && reuse_chemistry_scratch ? background_scratch : foreground_scratch;
    // Separate activity tiers avoid destroying the foreground records for each
    // small coarse pass. Retain scratch storage across passes.
    // Every pass-dependent field below is reassigned before neighbor traversal.
    if (!reuse_chemistry_scratch) scratch.clear();
    const int id_count=ids.size();
    scratch.resize(id_count);
    if (!packet_frame) chemistry_dictionaries.resize(id_count);
    for (int k = 0; k < id_count; ++k) {
      auto &p=scratch[k];
      p.handle=0;
      p.identity=int64_t(ids[k]);
      PacketState *numeric=nullptr;
      if (packet_frame) {
        auto &slot=packet(p.identity); load_chemistry(slot); numeric=&slot.value; slot.chemical=true;
        p.handle=slot.handle; p.d=&slot.d; p.p=numeric->p; p.v=numeric->v; p.dir=numeric->dir;
        p.amount=numeric->amount; p.capacity=numeric->capacity; p.kind=numeric->kind;
        p.alive=numeric->alive; p.reacted=numeric->reacted==revision;
      } else {
        chemistry_dictionaries[k]=particles[p.identity];p.d=&chemistry_dictionaries[k];
        p.p=(*p.d)[keys.p]; p.v=(*p.d)[keys.v]; p.dir=(*p.d)[keys.direction];
        p.amount=(*p.d)[keys.amount]; p.capacity=(*p.d)[keys.capacity]; p.kind=int((*p.d)[keys.kind]);
        p.alive=(*p.d)[keys.alive]; p.reacted=int(p.d->get(keys.reacted,-1))==revision;
      }
      p.initial_v = p.v; p.initial_amount = p.amount; p.initial_capacity = p.capacity;
      p.initial_kind = p.kind; p.initial_alive = p.alive; p.initial_reacted = p.reacted;
      p.active = p.alive ? (background ? 1. : activity(p.p, camera, half)) : 0;
      p.elapsed = background ? std::max(0., clock - (numeric ? (packet_slots[p.identity].has_chemical_clock ? numeric->chemical_at : clock) : double(p.d->get(keys.chemical_at, clock)))) : dt * p.active;
      if (clock >= 0 && !background) { if (numeric) { numeric->chemical_at=clock; packet_slots[p.identity].has_chemical_clock=true; } else (*p.d)[keys.chemical_at]=clock; }
      p.radius = radii[p.kind] * std::clamp(std::sqrt(p.amount / .3), .8, 1.7);
      if (!numeric) { (*p.d)[keys.reaction_activity]=p.active; (*p.d)[keys.contact_radius]=p.radius; }
      p.neighbor_bin=mod(int(std::floor(p.p.y/16)),160)*256+mod(int(std::floor(p.p.x/16)),256);
      if (fine_contacts && p.active>0 && p.kind!=3 && numeric->jump) fine_contacts=false;
      if (p.active > 0 && p.kind != 3) max_radius=std::max(max_radius,p.radius);
    }
    // Fine LiquidFun already supplies circular contacts. Chemistry needs only
    // its own conservative binding radius; catch-up/coarse passes keep both.
    double contact_radius=fine_contacts ? 0 : physical_radius;
    max_radius=std::max(max_radius,contact_radius);
    neighbors.begin(scratch,max_radius,background);
    bool matching=pair_matching && pool_enabled && neighbors.backend==0 && !neighbors.caching && !liquid.enabled;
    if (matching) {
      matching_seen.resize(packet_slots.size());
      if (++matching_epoch==0) {std::fill(matching_seen.begin(),matching_seen.end(),0);++matching_epoch;}
      for (const auto &p:scratch) {
        if (matching_seen[p.identity]==matching_epoch) {matching=false;++matching_fallbacks;break;}
        matching_seen[p.identity]=matching_epoch;
      }
    }
    const bool screened=!matching && simulation_threads>1 && parallel_contacts && scratch.size()>=4096 &&
      neighbors.backend==0 && !neighbors.caching && !neighbors.metrics;
    if (screened) {
      contact_lists.resize(scratch.size());
      if (compact_geometry) {
        contact_positions.resize(scratch.size());contact_radii.resize(scratch.size());contact_identities.resize(scratch.size());
        for (size_t i=0;i<scratch.size();++i) {
          contact_positions[i]=scratch[i].p;contact_radii[i]=scratch[i].radius;contact_identities[i]=scratch[i].identity;
        }
      }
      SimulationWorkers::shared().run(scratch.size(),simulation_threads,[&](size_t begin,size_t end) {
        for (size_t i=begin;i<end;++i) {
          const auto &p=scratch[i];auto &list=contact_lists[i];list.ids.clear();list.complete=true;
          if (!p.alive || p.active<=0 || p.kind==3 || p.reacted || p.elapsed<=0) continue;
          double reach=tight_bounds ? std::max(p.radius,contact_radius)+max_radius+.001 : 18.;
          neighbors.readonly_grid_visit(scratch,int(i),reach,[&](int j) {
            int identity=compact_geometry ? contact_identities[j] : scratch[j].identity;
            if (identity<=p.identity) return false;
            // Only immutable geometry is screened; alive/kind/reacted/material
            // are checked again during the original ordered commit below.
            double radius=compact_geometry ? contact_radii[j] : scratch[j].radius;
            Vector2 at=compact_geometry ? contact_positions[j] : scratch[j].p;
            double c=std::max(p.radius+radius,contact_radius>0 ? contact_radius*2 : 0.);
            if (delta(p.p,at).length_squared()>c*c) return false;
            if (list.ids.size()==128) {list.ids.clear();list.complete=false;return true;}
            list.ids.push_back(j);return false;
          });
        }
      });
      ++contact_jobs;
    }
    for (int i = 0; i < int(scratch.size()); ++i) {
      auto &p = scratch[i];
      if (!p.alive || p.active <= 0 || p.kind == 3)
        continue;
      double t = p.elapsed;
      if (clock >= 0 && background) { if (packet_frame) { packet_slots[p.identity].value.chemical_at=clock; packet_slots[p.identity].has_chemical_clock=true; } else (*p.d)[keys.chemical_at]=clock; }
      if (t <= 0) continue;
      if (p.kind == 8 || p.kind == 9) {
        int n = node(std::floor(p.p.x / 64), std::floor(p.p.y / 64));
        double before = acid[n];
        double after = std::clamp(before + (p.kind == 8 ? 1 : -1) *
                                               std::min(p.capacity, t * .2),
                                  0., 1.);
        acid.set(n, after);
        p.capacity -= std::abs(after - before);
        if (p.capacity <= .000001)
          p.kind = 2;
      }
      if (rng->randf() < 1 - std::exp(-decay[p.kind] * t)) {
        if (p.kind != 1 && p.kind != 3)
          loss += p.amount;
        p.alive = false;
        ++events[0];
        continue;
      }
      if (matching || p.kind == 3 || p.reacted)
        continue;
      // Only omit bins beyond every possible cached contact radius. Keep
      // traversal order and a float-coordinate margin for boundary contacts.
      double reach = tight_bounds ? std::max(p.radius,contact_radius) + max_radius + .001 : 18.;
      auto apply_contact=[&](int j) {
        auto &b = scratch[j];
        if (b.identity <= p.identity) return false;
        neighbors.owned_candidate();
        if (!b.alive || b.kind == 3 || b.reacted) return false;
        Vector2 d = delta(p.p, b.p);
        double c = p.radius + b.radius, dist2 = d.length_squared();
        double physical_c=contact_radius>0 ? contact_radius*2 : c;
        if (dist2 > std::max(c,physical_c)*std::max(c,physical_c))
          return false;
        neighbors.contact();
        double dist = std::sqrt(dist2);
        Vector2 n = dist2 > .000001 ? d / dist : Vector2(1, 0);
        const bool enzyme_pair = (p.kind == 6 && b.kind == 2) || (p.kind == 2 && b.kind == 6);
        // Most chemistry and every separation impulse are acid-independent.
        double a = (!lazy_acid || enzyme_pair) ? acid_sample(acid, p.p) : 0.;
        double threshold = .5;
        if (enzyme_pair)
          threshold +=
              .46 * std::pow(std::clamp(std::abs(a - .4) / .4, 0., 1.), 2);
        bool reacted = false;
        if (dist2 <= c*c && p.dir.dot(n) >= threshold && b.dir.dot(-n) >= threshold) {
          if (lazy_acid && ((p.kind == 2 && b.kind == 1) || (p.kind == 1 && b.kind == 2)))
            a = acid_sample(acid, p.p);
          Particle *u = &p, *v = &b;
          if ((u->kind == 2 && v->kind == 6) ||
              (u->kind == 4 && v->kind == 7) ||
              (u->kind == 1 && (v->kind == 2 || v->kind == 4)) ||
              (u->kind == 4 && v->kind == 0))
            std::swap(u, v);
          if (u->kind == 6 && v->kind == 2 && a < .9) {
            v->kind = 0;
            recycled += v->amount;
            ++events[5];
            reacted = true;
          } else if (u->kind == 7 && v->kind == 4) {
            // Presentation samples are bounded; every chemical reaction still runs.
            if (neutralizations.size() < 32) {
              Dictionary cue;
              cue["at"] = u->p;
              cue["source"] = u->d->get("owner", -1);
              cue["amount"] = v->amount;
              neutralizations.push_back(cue);
            }
            u->kind = 2;
            u->amount += v->amount;
            v->alive = false;
            ++events[6];
            reacted = true;
          } else if ((u->kind == 8 || u->kind == 9) &&
                     (v->kind == 8 || v->kind == 9) && u->kind != v->kind) {
            double use = std::min(u->capacity, v->capacity);
            u->capacity -= use;
            v->capacity -= use;
            if (u->capacity <= .000001)
              u->kind = 2;
            if (v->capacity <= .000001)
              v->kind = 2;
            reacted = true;
          } else if (u->kind == 2 && v->kind == 1 &&
                     v->amount >= u->amount * .15 && a < .8) {
            double amount = u->amount;
            u->kind = 0;
            u->amount = amount * .6;
            v->kind = 5;
            v->amount = amount * .4;
            recycled += amount * .6;
            ++events[2];
            reacted = true;
          } else if (u->kind == 0 && v->kind == 4) {
            u->kind = 2;
            ++events[4];
            reacted = true;
          } else if (u->kind == v->kind &&
                     (u->kind == 0 || u->kind == 2 || u->kind == 5 ||
                      u->kind == 1) &&
                     u->amount + v->amount <= 1.4) {
            double total = u->amount + v->amount;
            if (total <= 0)
              return false;
            u->v = u->v.lerp(v->v, v->amount / total);
            u->amount = total;
            v->alive = false;
            ++events[1];
            reacted = true;
          }
        }
        if (reacted) {
          // Capped presentation samples do not skip or alter chemistry.
          if (reaction_points.size() < 64)
            reaction_points.push_back(wrapv(p.p + d * .5));
          p.reacted = b.reacted = true;
          return true;
        }
        bool solved_contact=liquid.enabled && pool_enabled && !background &&
          !packet_slots[p.identity].value.jump && !packet_slots[b.identity].value.jump;
        if (collisions && !solved_contact && dist2 < physical_c*physical_c) {
          Vector2 push = n * (physical_c - dist) * .25;
          p.v -= push * 8;
          b.v += push * 8;
        }
        return false;
      };
      if (screened && contact_lists[i].complete) {
        for (int j:contact_lists[i].ids) if (apply_contact(j)) break;
      } else {
        if (screened) ++contact_fallbacks;
        neighbors.visit(scratch,i,reach,apply_contact);
      }
    }
    if (matching) {
      ++matching_jobs;
      mutual_matching(scratch,neighbors,simulation_threads,uint32_t(revision),max_radius,contact_radius,collisions,delta,
        [&](Vector2 at){return acid_sample(acid,at);},pair_choices,pair_outcomes);
      for (size_t i=0;i<pair_outcomes.size();++i) {
        const auto &event=pair_outcomes[i];
        if (!event.reacted) continue;
        if (event.event>=0) ++events[event.event];
        recycled+=event.recycled;
        if (reaction_points.size()<64)
          reaction_points.push_back(wrapv(scratch[i].p+delta(scratch[i].p,scratch[event.other].p)*.5));
        if (event.neutralizer>=0 && neutralizations.size()<32) {
          const auto &u=scratch[event.neutralizer];Dictionary cue;
          cue["at"]=u.p;cue["source"]=u.d->get("owner",-1);cue["amount"]=event.neutralized;
          neutralizations.push_back(cue);
        }
      }
    }
    for (auto &p : scratch) {
      if (packet_frame) {
        auto &value=packet_slots[p.identity].value;
        value.v=p.v; value.kind=p.kind; value.amount=p.amount; value.capacity=p.capacity;
        value.alive=p.alive; if (p.reacted) { value.reacted=revision; if (pool_enabled) packet_slots[p.identity].mask|=REACTED; }
        continue;
      }
      if (p.kind!=p.initial_kind || p.amount!=p.initial_amount || p.alive!=p.initial_alive)
        invalidate_particle_render(p.identity);
      if (!dirty_writes || p.v != p.initial_v) (*p.d)[keys.v] = p.v;
      if (!dirty_writes || p.kind != p.initial_kind) (*p.d)[keys.kind] = p.kind;
      if (!dirty_writes || p.amount != p.initial_amount) (*p.d)[keys.amount] = p.amount;
      if (!dirty_writes || p.capacity != p.initial_capacity) (*p.d)[keys.capacity] = p.capacity;
      if (!dirty_writes || p.alive != p.initial_alive) (*p.d)[keys.alive] = p.alive;
      if (p.reacted && (!dirty_writes || !p.initial_reacted))
        (*p.d)[keys.reacted] = revision;
    }
    Dictionary out;
    out["acid"] = acid;
    out["loss"] = loss;
    out["recycled"] = recycled;
    Dictionary e;
    for (int i = 0; i < 7; ++i)
      e[names[i]] = events[i];
    out["events"] = e;
    out["neutralizations"] = neutralizations;
    out["reaction_points"] = reaction_points;
    return out;
  }
  PackedVector2Array fluid_step(const PackedVector2Array &v,
                                const PackedFloat32Array &a,
                                const PackedVector2Array &tide, double dt,
                                bool driven) {
    PackedVector2Array out = v;
    Vector2 *w = out.ptrw();
    // Gather the same symmetric edge flux once per endpoint, avoiding scatter
    // races.
    for (int i = 0; i < v.size(); ++i) {
      if (a[i] <= 0)
        continue;
      int x = i % 64, y = i / 64;
      Vector2 change;
      for (int j :
           {node(x - 1, y), node(x + 1, y), node(x, y - 1), node(x, y + 1)})
        change +=
            (v[j] - v[i]) * (std::min(a[i], a[j]) * std::min(dt * .8, .2));
      if (driven)
        change += (tide[i] - v[i]) * (1 - std::exp(-dt * a[i] * .12));
      w[i] += change;
    }
    return out;
  }
  PackedFloat32Array acid_step(const PackedFloat32Array &v,
                               const PackedVector2Array &flow,
                               const PackedFloat32Array &active, double dt) {
    PackedFloat32Array out = v;
    float *w = out.ptrw();
    for (int i = 0; i < v.size(); ++i) {
      if (active[i] <= 0)
        continue;
      int x = i % 64, y = i / 64;
      double t = dt * active[i];
      Vector2 at((x + .5) * 64, (y + .5) * 64);
      double upstream = acid_sample(v, at - flow[i] * t);
      double neighbors = (v[node(x - 1, y)] + v[node(x + 1, y)] +
                          v[node(x, y - 1)] + v[node(x, y + 1)]) *
                         .25;
      double blend = std::min(1., t * .5);
      w[i] = std::clamp((upstream * (1 - blend) + neighbors * blend) *
                            std::exp(-t * .012),
                        0., 1.);
    }
    return out;
  }
};
void initialize(ModuleInitializationLevel level) {
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
    ClassDB::register_class<PrimordiaKernels>();
    ClassDB::register_class<PrimordiaResidentReference>();
    ClassDB::register_class<PrimordiaGrid>();
    ClassDB::register_class<PrimordiaMusicMixer>();
  }
}
void terminate(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT primordia_library_init(
    GDExtensionInterfaceGetProcAddress get, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *init) {
  GDExtensionBinding::InitObject object(get, library, init);
  object.register_initializer(initialize);
  object.register_terminator(terminate);
  object.set_minimum_library_initialization_level(
      MODULE_INITIALIZATION_LEVEL_SCENE);
  return object.init();
}
