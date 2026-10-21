#pragma once
#include "chemical_catalog.h"
#include "mouth_attraction.h"
// Diagnostic transport model shared with resident_particles.glsl. Never replaces
// gameplay RNG, chemical state, contacts, feeding or background scheduling.
#include "simulation_workers.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <vector>
#include <cmath>
#include <algorithm>
#include <cstdint>
namespace godot {
class PrimordiaResidentReference : public RefCounted {
  GDCLASS(PrimordiaResidentReference, RefCounted)
  std::vector<float> state;
  PackedVector2Array flow;
  int lanes=1;
  static float wrap(float a,float n) { return a-std::floor(a/n)*n; }
  static uint32_t hash(uint32_t x) { x^=x>>16; x*=0x7feb352du; x^=x>>15; x*=0x846ca68bu; return x^(x>>16); }
  static float uniform(uint32_t x) { return (float(hash(x)>>8)+.5f)/16777216.f; }
  static float normal(uint32_t x) { return std::sqrt(-2.f*std::log(uniform(x)))*std::cos(6.28318530718f*uniform(x^0x9e3779b9u)); }
  static int node(int x,int y) {return ((y%40+40)%40)*64+(x%64+64)%64;}
  static Vector2 sample(const Vector2 *v, Vector2 p) {
    float x=wrap(p.x,4096.f)/64.f-.5f,y=wrap(p.y,2560.f)/64.f-.5f;
    int ix=std::floor(x),iy=std::floor(y); float fx=x-ix,fy=y-iy;
    return v[node(ix,iy)].lerp(v[node(ix+1,iy)],fx).lerp(v[node(ix,iy+1)].lerp(v[node(ix+1,iy+1)],fx),fy);
  }
protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","state","flow","threads"),&PrimordiaResidentReference::configure);
    ClassDB::bind_method(D_METHOD("advance","dt","tick"),&PrimordiaResidentReference::advance);
    ClassDB::bind_method(D_METHOD("snapshot"),&PrimordiaResidentReference::snapshot);
    ClassDB::bind_method(D_METHOD("instances","camera"),&PrimordiaResidentReference::instances);
  }
public:
  bool configure(PackedFloat32Array values,PackedVector2Array velocity,int threads) {
    if(values.size()==0 || values.size()%12 || values.size()>100000*12 || (velocity.size()<2560||velocity.size()>2688||(velocity.size()-2560)%2) || threads<1 || threads>8) return false;
    for(int i=0;i<values.size();++i) if(!std::isfinite(values[i])) return false;
    for(int i=0;i<velocity.size();++i) if(!velocity[i].is_finite()) return false;
    for(int i=0;i<values.size();i+=12) if(values[i+7]<0 || values[i+7]>=primordia_chemistry::species_count || values[i+7]!=std::floor(values[i+7]) || values[i+8]<=0) return false;
    state.assign(values.ptr(),values.ptr()+values.size());flow=velocity;lanes=threads;return true;
  }
  bool advance(double elapsed,int64_t tick) {
    if(state.empty() || elapsed<=0 || elapsed>2 || !std::isfinite(elapsed) || tick<0 || tick>0xffffffffLL) return false;
    const Vector2 *field=flow.ptr();float dt=elapsed;
    auto work=[&](size_t first,size_t last) {
      for(size_t i=first;i<last;++i) {
        float *p=state.data()+i*12;bool tracer=p[7]==3.f;
        Vector2 at(p[0],p[1]),launch=tracer?Vector2():Vector2(p[4],p[5]);
        Vector2 original=launch;
        if(dt<=.05f) at+= (sample(field,at)+primordia_mouth::pull(field,flow.size(),at,int(p[7]))+launch)*dt;
        else {
          int steps=std::clamp(int(std::ceil(dt/.25f)),1,8);float h=dt/steps,damping=std::exp(-.8f*h);
          for(int j=0;j<steps;++j) {
            Vector2 mid=at+(sample(field,at)+primordia_mouth::pull(field,flow.size(),at,int(p[7])))*(h*.5f)+launch*((1.f-std::exp(-.4f*h))/.8f);
            at+=(sample(field,mid)+primordia_mouth::pull(field,flow.size(),mid,int(p[7])))*h+launch*((1.f-damping)/.8f);
            at=Vector2(wrap(at.x,4096.f),wrap(at.y,2560.f));launch*=damping;
          }
        }
        uint32_t seed=uint32_t(i)*0x9e3779b9u+uint32_t(tick)*0x85ebca6bu;
        float noise=std::sqrt((tracer?240.f:12.f)*dt);
        at+=Vector2(normal(seed),normal(seed+1u))*noise;
        p[0]=wrap(at.x,4096.f);p[1]=wrap(at.y,2560.f);
        p[2]=tracer?0.f:wrap(p[2]+p[3]*dt+normal(seed+2u)*std::sqrt(1.2f*dt)+3.14159265359f,6.28318530718f)-3.14159265359f;
        original*=std::exp(-.8f*dt);p[4]=original.x;p[5]=original.y;p[6]+=dt;
      }
    };
    SimulationWorkers::shared().run(state.size()/12,lanes,work);return true;
  }
  PackedFloat32Array snapshot() const {
    PackedFloat32Array out;out.resize(state.size());std::copy(state.begin(),state.end(),out.ptrw());return out;
  }
  PackedFloat32Array instances(Vector2 camera) const {
    PackedFloat32Array out;out.resize(state.size());float *dst=out.ptrw();
    for(size_t i=0;i<state.size();i+=12) {
      const float *p=state.data()+i;float co=std::cos(p[2])*p[8],si=std::sin(p[2])*p[8];
      float values[12]={co,-si,0,wrap(p[0]-camera.x+2048.f,4096.f)-2048.f,si,co,0,wrap(p[1]-camera.y+1280.f,2560.f)-1280.f,p[7]/float(primordia_chemistry::species_count-1),1,1,1};
      std::copy(values,values+12,dst+i);
    }
    return out;
  }
};
}
