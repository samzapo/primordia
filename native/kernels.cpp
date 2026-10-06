#include "music_mixer.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
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
  double d = (delta(camera, p) / half).length();
  double t = std::clamp((1 - d) / .28, 0., 1.);
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
};
struct Particle {
  Dictionary d;
  Vector2 p, v, dir;
  double amount, capacity, active, radius;
  int kind, identity;
  bool alive, reacted;
};
} // namespace
class PrimordiaGrid : public RefCounted {
  GDCLASS(PrimordiaGrid, RefCounted)
  Keys keys;
  double size = 64;
  int cols = 64, rows = 40;
  std::vector<std::vector<int>> bins = std::vector<std::vector<int>>(2560);
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
    ClassDB::bind_method(D_METHOD("insert", "id", "position"),
                         &PrimordiaGrid::insert);
    ClassDB::bind_method(D_METHOD("move", "id", "old", "position"),
                         &PrimordiaGrid::move);
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
  }
  void clear() {
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
  void insert(int id, Vector2 p) { bins[key(p)].push_back(id); }
  void move(int id, Vector2 old, Vector2 p) {
    int a = key(old), b = key(p);
    if (a == b)
      return;
    auto &v = bins[a];
    auto it = std::find(v.begin(), v.end(), id);
    if (it != v.end())
      v.erase(it);
    bins[b].push_back(id);
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

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("obstacle_configure", "segments", "bins"),
                         &PrimordiaKernels::obstacle_configure);
    ClassDB::bind_method(
        D_METHOD("obstacle_particles", "particles", "ids", "revision"),
        &PrimordiaKernels::obstacle_particles);
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
    ClassDB::bind_method(
        D_METHOD("exclude", "particles", "ids", "bodies", "camera", "half"),
        &PrimordiaKernels::exclude);
    ClassDB::bind_method(D_METHOD("transport", "particles", "ids", "flow",
                                  "camera", "half", "dt", "revision", "rng"),
                         &PrimordiaKernels::transport);
    ClassDB::bind_method(D_METHOD("chemistry", "particles", "ids", "acid",
                                  "camera", "half", "dt", "revision", "rng"),
                         &PrimordiaKernels::chemistry);
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
  bool obstacle_particles(Array particles, Array ids, int revision) {
    bool changed = false;
    std::vector<int> candidates;
    for (int index = 0; index < ids.size(); ++index) {
      Dictionary packet = particles[int(ids[index])];
      if (!bool(packet[keys.alive]) ||
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
          Vector2 a = p + delta(p, s.a), b = a + s.b - s.a,
                  d = p - closest_stem(p, a, b);
          double reach = 4 + s.radius + .2;
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
      if (!bool(p[keys.alive]))
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
  int transport(Array particles, TypedArray<int64_t> ids,
                const PackedVector2Array &flow, Vector2 camera, Vector2 half,
                double dt, int revision, Ref<RandomNumberGenerator> rng) {
    int count = 0;
    for (int k = 0; k < ids.size(); ++k) {
      Dictionary p = particles[int64_t(ids[k])];
      if (!bool(p[keys.alive]))
        continue;
      Vector2 at = p[keys.p];
      double a = activity(at, camera, half);
      if (a <= 0)
        continue;
      ++count;
      double t = dt * a;
      Vector2 v = p[keys.v];
      double angle = p[keys.angle];
      p[keys.updated] = revision;
      p[keys.previous] = at;
      // Keep RNG call order explicit, matching the reference backend.
      double nx = rng->randfn(0, 1), ny = rng->randfn(0, 1);
      p[keys.p] = wrapv(at + (v + sample(flow, at)) * t +
                        Vector2(nx, ny) * std::sqrt(12 * t));
      p[keys.v] = v * std::exp(-t * .8);
      p[keys.age] = double(p[keys.age]) + t;
      p[keys.previous_angle] = angle;
      angle = wrap(angle + double(p[keys.spin]) * t +
                       rng->randfn(0, 1) * std::sqrt(1.2 * t) + PI,
                   TAU) -
              PI;
      p[keys.angle] = angle;
      p[keys.direction] = Vector2(std::cos(angle), std::sin(angle));
    }
    return count;
  }
  Dictionary chemistry(Array particles, TypedArray<int64_t> ids,
                       PackedFloat32Array acid, Vector2 camera, Vector2 half,
                       double dt, int revision,
                       Ref<RandomNumberGenerator> rng) {
    static const double radii[] = {4, 2.5, 3, 2.5, 5, 3, 4, 4, 3, 3, 3.5};
    static const double decay[] = {.003, .008, .006, .65,  .1, .001,
                                   .02,  .015, .008, .008, .08};
    static const char *names[] = {"decay", "combine", "recycle",   "detox",
                                  "spoil", "enzyme",  "neutralize"};
    std::array<int, 7> events{};
    double loss = 0, recycled = 0;
    scratch.clear();
    scratch.reserve(ids.size());
    if (bins.empty())
      bins.resize(256 * 160);
    for (auto &b : bins)
      b.clear();
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
      p.active = p.alive ? activity(p.p, camera, half) : 0;
      p.radius = radii[p.kind] * std::clamp(std::sqrt(p.amount / .3), .8, 1.7);
      d[keys.reaction_activity] = p.active;
      d[keys.contact_radius] = p.radius;
      scratch.push_back(p);
      if (p.active > 0)
        bins[mod(int(std::floor(p.p.y / 16)), 160) * 256 +
             mod(int(std::floor(p.p.x / 16)), 256)]
            .push_back(k);
    }
    for (int i = 0; i < int(scratch.size()); ++i) {
      auto &p = scratch[i];
      if (!p.alive || p.active <= 0)
        continue;
      double t = dt * p.active;
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
              p.reacted = b.reacted = true;
              break;
            }
            Vector2 push = n * (c - dist) * .25;
            p.v -= push * 8;
            b.v += push * 8;
          }
    }
    for (auto &p : scratch) {
      p.d[keys.v] = p.v;
      p.d[keys.kind] = p.kind;
      p.d[keys.amount] = p.amount;
      p.d[keys.capacity] = p.capacity;
      p.d[keys.alive] = p.alive;
      if (p.reacted)
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
