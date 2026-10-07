#pragma once
// Conservative coarse transport parcels. Child material/angles/metadata stay
// authoritative: this stage shares advection work, NOT chemistry or collisions.
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <unordered_map>
#include <cstdint>
#include <vector>
class ParcelTransport {
  static constexpr int COLS=64,ROWS=40;
  struct Group {std::vector<int> members; double elapsed=0;};
  std::vector<unsigned char> protected_bins,available;
  std::vector<godot::Vector2> shifts;
  std::unordered_map<uint64_t,Group> groups;
  static int mod(int x,int n) {return (x%n+n)%n;}
public:
  bool enabled=false;
  uint64_t calls=0,parcels=0,children=0,saved_integrations=0,rejected_shear=0;
  double prepare_ms=0;
  void reset_metrics() {calls=parcels=children=saved_integrations=rejected_shear=0;prepare_ms=0;}
  void invalidate_protection() {protected_bins.clear();}
  void protect(const godot::PackedVector2Array &centers,const godot::PackedFloat32Array &radii) {
    protected_bins.assign(COLS*ROWS,0);
    for (int i=0;i<centers.size();++i) {
      double reach=std::min(double(radii[i])+384,8192.0); // Coarse intake, sensory patch and swept contact halo.
      int lx=std::floor((centers[i].x-reach)/64),hx=std::floor((centers[i].x+reach)/64);
      int ly=std::floor((centers[i].y-reach)/64),hy=std::floor((centers[i].y+reach)/64);
      for (int y=ly;y<=std::min(hy,ly+ROWS-1);++y)
        for (int x=lx;x<=std::min(hx,lx+COLS-1);++x)
          protected_bins[mod(y,ROWS)*COLS+mod(x,COLS)]=1;
    }
  }
  template<class Slots,class IDs,class Sample,class Wrap>
  void prepare(const Slots &slots,const IDs &ids,const godot::PackedVector2Array &flow,
               double clock,double dt,Sample sample,Wrap wrap) {
    auto start=std::chrono::steady_clock::now();
    ++calls;groups.clear();available.assign(slots.size(),0);shifts.resize(slots.size());
    for (int k=0;k<ids.size();++k) {
      int id=ids[k];const auto &slot=slots[id];const auto &p=slot.value;
      if (!p.alive||p.kind==3) continue;
      int bin=mod(int(std::floor(p.p.y/64)),ROWS)*COLS+mod(int(std::floor(p.p.x/64)),COLS);
      if (protected_bins.empty()||protected_bins[bin]) continue;
      double elapsed=clock-(slot.has_transport_clock ? p.transport_at : clock-dt);
      if (elapsed<=.05||elapsed>2) continue;
      // A timestep cohort cannot drag a newly emitted packet through old time.
      uint64_t cohort=uint64_t(std::llround(elapsed*60000));
      uint64_t key=(cohort*11+uint64_t(p.kind))*(COLS*ROWS)+bin;
      auto &g=groups[key];g.elapsed=elapsed;g.members.push_back(id);
    }
    for (auto &entry:groups) {
      const auto &g=entry.second;
      for (int begin=0;begin<int(g.members.size());begin+=32) {
        int end=std::min(begin+32,int(g.members.size()));
        if (end-begin<4) continue;
        godot::Vector2 center,velocity;
        for (int k=begin;k<end;++k) {const auto &p=slots[g.members[k]].value;center+=p.p;velocity+=p.v;}
        center/=end-begin;velocity/=end-begin;
        bool compatible=true;
        for (int k=begin;k<end;++k) {
          const auto &slot=slots[g.members[k]];
          double elapsed=clock-(slot.has_transport_clock ? slot.value.transport_at : clock-dt);
          if (std::abs(elapsed-g.elapsed)>.000001 || (slot.value.v-velocity).length()>8) compatible=false;
        }
        if (!compatible) {++rejected_shear;continue;}
        // Sharp variation needs individual integration, regardless of zoom.
        if ((sample(flow,center+godot::Vector2(32,0))-sample(flow,center-godot::Vector2(32,0))).length()>8 ||
            (sample(flow,center+godot::Vector2(0,32))-sample(flow,center-godot::Vector2(0,32))).length()>8) {++rejected_shear;continue;}
        double t=g.elapsed,h=t/std::clamp(int(std::ceil(t/.25)),1,8),damping=std::exp(-.8*h);
        auto at=center,launch=velocity;
        for (int j=0;j<std::clamp(int(std::ceil(t/.25)),1,8);++j) {
          auto midpoint=at+sample(flow,at)*(h*.5)+launch*((1-std::exp(-.4*h))/.8);
          at=wrap(at+sample(flow,midpoint)*h+launch*((1-damping)/.8));launch*=damping;
        }
        // Recover the local periodic translation; the group footprint is <=64.
        auto travel=at-center;
        travel.x-=4096*std::floor((travel.x+2048)/4096);
        travel.y-=2560*std::floor((travel.y+1280)/2560);
        double integral=(1-std::exp(-.8*t))/.8;
        for (int k=begin;k<end;++k) {
          int id=g.members[k];const auto &p=slots[id].value;
          available[id]=1;
          shifts[id]=travel+(p.v-velocity)*integral;
        }
        ++parcels;children+=end-begin;saved_integrations+=end-begin-1;
      }
    }
    prepare_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
  }
  bool contains(int id) const {return id<int(available.size())&&available[id];}
  godot::Vector2 displacement(int id) const {return shifts[id];}
};
