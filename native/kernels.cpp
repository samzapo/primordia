#include "music_mixer.h"
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
#include <vector>
using namespace godot;
namespace {
constexpr double TAU = 6.283185307179586, PI = TAU / 2;
double wrap(double x, double n) { return x - std::floor(x / n) * n; }
Vector2 wrapv(Vector2 p) { return Vector2(wrap(p.x, 4096), wrap(p.y, 2560)); }
Vector2 delta(Vector2 a, Vector2 b) {
  return Vector2(wrap(b.x - a.x + 2048, 4096) - 2048,
                 wrap(b.y - a.y + 1280, 2560) - 1280);
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
struct Particle {
  Dictionary d;
  Vector2 p, v, dir;
  double amount, capacity, active, radius, elapsed;
  int kind, identity;
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
  std::vector<Particle> scratch;
  std::vector<std::vector<int>> bins;
  std::vector<int> occupied_bins;

protected:
  static void _bind_methods() {
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
                                  "revision", "capacities"),
                         &PrimordiaKernels::render_particles);
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
                                  "camera", "half", "dt", "revision", "rng", "clock", "background", "dirty_writes"),
                         &PrimordiaKernels::chemistry, DEFVAL(-1.0), DEFVAL(false), DEFVAL(true));
    ClassDB::bind_method(
        D_METHOD("fluid_step", "velocity", "activity", "tide", "dt", "driven"),
        &PrimordiaKernels::fluid_step);
    ClassDB::bind_method(
        D_METHOD("acid_step", "values", "velocity", "activity", "dt"),
        &PrimordiaKernels::acid_step);
  }

public:
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
    static const double rings[] = {.76,.90,1.,1.42};
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
                         int revision, PackedInt32Array capacities) {
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
    std::array<std::vector<std::array<float, 12>>, 11> instances;
    static const double radii[] = {4, 2.5, 3, 2.5, 5, 3, 4, 4, 3, 3, 3.5};
    for (int k = 0; k < ids.size(); ++k) {
      Dictionary p = particles[int64_t(ids[k])];
      if (!bool(p[keys.alive]))
        continue;
      Vector2 at = p[keys.p];
      double heading = p[keys.angle];
      if (int(p.get(keys.updated, -1)) == revision) {
        Vector2 previous = p[keys.previous];
        at = previous + delta(previous, at) * alpha;
        double old = p[keys.previous_angle];
        heading = old + (wrap(heading - old + PI, TAU) - PI) * alpha;
      }
      // Dissolved pheromones are drawn at their true position, even inside cells.
      if (int(p[keys.kind]) != 3) {
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
      int kind = p[keys.kind];
      double diameter =
          2 * radii[kind] *
          std::clamp(std::sqrt(double(p[keys.amount]) / .3), .8, 1.7);
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
    bool solid = habitat->get("enabled");
    for (int k=0;k<ids.size();++k) {
      Dictionary p = particles[int64_t(ids[k])];
      int kind = p[keys.kind];
      if (!bool(p[keys.alive]) || (kind != 0 && kind != 1 && kind != 5)) continue;
      Vector2 at = p[keys.p];
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
      double taken = std::min(double(p[keys.amount]),capacity);
      p[keys.amount] = double(p[keys.amount])-taken;
      if (double(p[keys.amount]) <= .000001) p[keys.alive] = false;
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
      Dictionary p = particles[int64_t(ids[k])];
      int kind = p[keys.kind];
      if (!bool(p[keys.alive]) || (mouth ? kind != 0 : kind != 1 && kind != 5)) continue;
      Vector2 at = p[keys.p];
      if (activity(at,camera,half) <= 0) continue;
      Vector2 d = delta(center,at);
      double distance = d.length(), taken = 0;
      bool handled = false;
      if (mouth && distance <= reach) {
        handled = true;
        taken = std::min(double(p[keys.amount]), std::max(0.,gut-substrate));
        substrate += taken;
        eaten += taken;
        if (int(p.get("owner",-1)) != owner) foreign += taken;
        if (taken > 0) body->call("consumed",organ,taken);
      } else if (!mouth && kind == 5 && photo && distance < extent+18) {
        handled = true;
        taken = std::min(double(p[keys.amount]), std::max(0.,carbon_cap-carbon));
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
          taken = std::min(double(p[keys.amount]), std::max(0.,oxygen_cap-oxygen));
          oxygen += taken;
        }
      }
      if (!handled) continue;
      if (taken > 0) p[keys.amount] = double(p[keys.amount])-taken;
      if (double(p[keys.amount]) <= .000001) p[keys.alive] = false;
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
      Dictionary p = particles[id];
      if (!bool(p[keys.alive]) || int(p[keys.kind]) == 3)
        continue;
      Vector2 at = p[keys.p];
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
        p[keys.p] = at;
        p[keys.previous] = at;
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
      int id = (cursor+k)%particles.size();
      Dictionary p = particles[id];
      if (bool(p[keys.alive]) && activity(p[keys.p],camera,half) <= 0 &&
          double(p.get(keys.transport_at,0.)) < clock) out.push_back(id);
    }
    return out;
  }
  void settle_transport(Array particles, TypedArray<int64_t> ids, bool background) {
    for (int k=0;k<ids.size();++k) {
      Dictionary p = particles[int64_t(ids[k])];
      if (background || bool(p.get(keys.transport_jump,false))) {
        p[keys.previous] = p[keys.p];
        p[keys.previous_angle] = p[keys.angle];
        if (!background) p[keys.transport_jump] = false;
      }
    }
  }
  int transport(Array particles, TypedArray<int64_t> ids,
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
  Dictionary chemistry(Array particles, TypedArray<int64_t> ids,
                       PackedFloat32Array acid, Vector2 camera, Vector2 half,
                       double dt, int revision,
                       Ref<RandomNumberGenerator> rng, double clock, bool background, bool dirty_writes) {
    static const double radii[] = {4, 2.5, 3, 2.5, 5, 3, 4, 4, 3, 3, 3.5};
    static const double decay[] = {.003, .008, .006, 0.0,  .1, .001,
                                   .02,  .015, .008, .008, .08};
    static const char *names[] = {"decay", "combine", "recycle",   "detox",
                                  "spoil", "enzyme",  "neutralize"};
    std::array<int, 7> events{};
    Array neutralizations;
    PackedVector2Array reaction_points;
    double loss = 0, recycled = 0;
    scratch.clear();
    scratch.reserve(ids.size());
    if (bins.empty())
      bins.resize(256 * 160);
    for (int id : occupied_bins) bins[id].clear();
    occupied_bins.clear();
    for (int k = 0; k < ids.size(); ++k) {
      Dictionary d = particles[int64_t(ids[k])];
      Particle p;
      p.identity = int64_t(ids[k]);
      p.d = d;
      p.p = d[keys.p];
      p.v = d[keys.v];
      p.dir = d[keys.direction];
      p.amount = d[keys.amount];
      p.capacity = d[keys.capacity];
      p.kind = int(d[keys.kind]);
      p.alive = d[keys.alive];
      p.reacted = int(d.get(keys.reacted, -1)) == revision;
      p.initial_v = p.v; p.initial_amount = p.amount; p.initial_capacity = p.capacity;
      p.initial_kind = p.kind; p.initial_alive = p.alive; p.initial_reacted = p.reacted;
      p.active = p.alive ? (background ? 1. : activity(p.p, camera, half)) : 0;
      p.elapsed = background ? std::max(0., clock - double(d.get(keys.chemical_at, clock))) : dt * p.active;
      if (clock >= 0 && !background) d[keys.chemical_at] = clock;
      p.radius = radii[p.kind] * std::clamp(std::sqrt(p.amount / .3), .8, 1.7);
      d[keys.reaction_activity] = p.active;
      d[keys.contact_radius] = p.radius;
      scratch.push_back(p);
      if (p.active > 0 && p.kind != 3) {
        int id = mod(int(std::floor(p.p.y / 16)),160)*256 + mod(int(std::floor(p.p.x / 16)),256);
        if (bins[id].empty()) occupied_bins.push_back(id);
        bins[id].push_back(k);
      }
    }
    for (int i = 0; i < int(scratch.size()); ++i) {
      auto &p = scratch[i];
      if (!p.alive || p.active <= 0 || p.kind == 3)
        continue;
      double t = p.elapsed;
      if (clock >= 0 && background) p.d[keys.chemical_at] = clock;
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
      if (p.kind == 3 || p.reacted)
        continue;
      int lx = std::floor((p.p.x - 18) / 16),
          hx = std::floor((p.p.x + 18) / 16),
          ly = std::floor((p.p.y - 18) / 16),
          hy = std::floor((p.p.y + 18) / 16);
      for (int x = lx; x <= hx && !p.reacted; ++x)
        for (int y = ly; y <= hy && !p.reacted; ++y)
          for (int j : bins[mod(y, 160) * 256 + mod(x, 256)]) {
            // Original identity, not local traversal order, owns each unordered
            // pair.
            auto &b = scratch[j];
            if (b.identity <= p.identity)
              continue;
            if (!b.alive || b.kind == 3 || b.reacted)
              continue;
            Vector2 d = delta(p.p, b.p);
            double c = p.radius + b.radius, dist2 = d.length_squared();
            if (dist2 > c * c)
              continue;
            double dist = std::sqrt(dist2);
            Vector2 n = dist2 > .000001 ? d / dist : Vector2(1, 0);
            double a = acid_sample(acid, p.p);
            double threshold = .5;
            if ((p.kind == 6 && b.kind == 2) || (p.kind == 2 && b.kind == 6))
              threshold +=
                  .46 * std::pow(std::clamp(std::abs(a - .4) / .4, 0., 1.), 2);
            bool reacted = false;
            if (p.dir.dot(n) >= threshold && b.dir.dot(-n) >= threshold) {
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
                  cue["source"] = u->d.get("owner", -1);
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
                  continue;
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
              break;
            }
            Vector2 push = n * (c - dist) * .25;
            p.v -= push * 8;
            b.v += push * 8;
          }
    }
    for (auto &p : scratch) {
      if (!dirty_writes || p.v != p.initial_v) p.d[keys.v] = p.v;
      if (!dirty_writes || p.kind != p.initial_kind) p.d[keys.kind] = p.kind;
      if (!dirty_writes || p.amount != p.initial_amount) p.d[keys.amount] = p.amount;
      if (!dirty_writes || p.capacity != p.initial_capacity) p.d[keys.capacity] = p.capacity;
      if (!dirty_writes || p.alive != p.initial_alive) p.d[keys.alive] = p.alive;
      if (p.reacted && (!dirty_writes || !p.initial_reacted))
        p.d[keys.reacted] = revision;
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
