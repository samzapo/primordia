#pragma once
// Original Google LiquidFun; Primordia metadata/chemistry never live here.
// Solver coordinates are metres at 0.01 m per game unit, NOT micrometres.
#include <Box2D/Box2D.h>
#include <godot_cpp/variant/vector2.hpp>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <memory>
#include <vector>

class LiquidParticles {
  static constexpr double SCALE=.01, W=4096, H=2560;
  std::unique_ptr<b2World> world;
  b2ParticleSystem *system=nullptr;
  std::vector<godot::Vector2> shifts;
  std::vector<int> owners;
  void reset() {
    world=std::make_unique<b2World>(b2Vec2(0,0));
    b2ParticleSystemDef definition;
    definition.radius=float(radius*SCALE);
    definition.gravityScale=0;
    definition.dampingStrength=.2f;
    definition.pressureStrength=.05f;
    definition.destroyByAge=false; // Capacity must NEVER destroy game material.
    system=world->CreateParticleSystem(&definition);
    ++rebuilds;
  }
public:
  bool enabled=false;
  double radius=4;
  int iterations=1;
  uint64_t calls=0,rebuilds=0;
  int points=0,ghosts=0,contacts=0,capacity=0;
  double prepare_ms=0,solve_ms=0,apply_ms=0;
  bool configure(bool on,double r,int it) {
    if (!std::isfinite(r)||r<1||r>8||it<1||it>4) return false;
    if (r!=radius || on!=enabled) {world.reset();system=nullptr;}
    enabled=on;radius=r;iterations=it;return true;
  }
  void clear_metrics() {calls=rebuilds=0;prepare_ms=solve_ms=apply_ms=0;}
  void solve(std::vector<godot::Vector2> &positions,
             std::vector<godot::Vector2> &motion,double dt) {
    auto started=std::chrono::steady_clock::now();
    owners.clear();shifts.clear();
    points=int(positions.size());
    // Periodic images provide ordinary LiquidFun contacts at habitat seams.
    // They contain no chemical material and are never exposed to biology.
    double pad=radius*4;
    for (const auto &v:motion) pad=std::max(pad,radius*4+double(v.length())*dt*2);
    pad=std::min(pad,128.0);
    for (int i=0;i<points;++i) {
      owners.push_back(i);shifts.emplace_back();
    }
    for (int i=0;i<points;++i) {
      const auto p=positions[i];
      double xs[3]={0},ys[3]={0};int nx=1,ny=1;
      if (p.x<pad) xs[nx++]=W;
      if (p.x>W-pad) xs[nx++]=-W;
      if (p.y<pad) ys[ny++]=H;
      if (p.y>H-pad) ys[ny++]=-H;
      for (int iy=0;iy<ny;++iy) for (int ix=0;ix<nx;++ix) {
        double x=xs[ix],y=ys[iy];if (x==0&&y==0) continue;
        owners.push_back(i);shifts.emplace_back(x,y);
      }
    }
    ghosts=int(owners.size())-points;
    // Reuse solver slots through chemistry compaction. Rebuild only after a
    // substantial count reduction; reserve points are isolated wall particles.
    int needed=int(owners.size());
    if (!system || needed*4<system->GetParticleCount()*3) reset();
    while (system->GetParticleCount()<needed) {
      b2ParticleDef d;d.position=b2Vec2(float(1000+system->GetParticleCount()),1000);
      d.flags=b2_wallParticle;system->CreateParticle(d);
    }
    capacity=system->GetParticleCount();
    auto *p=system->GetPositionBuffer(), *v=system->GetVelocityBuffer();
    for (int i=0;i<capacity;++i) {
      if (i<needed) {
        const auto at=positions[owners[i]]+shifts[i],vel=motion[owners[i]];
        p[i].Set(float(at.x*SCALE),float(at.y*SCALE));
        v[i].Set(float(vel.x*SCALE),float(vel.y*SCALE));
        system->SetParticleFlags(i,b2_waterParticle);
      } else {
        p[i].Set(float(1000+i),1000);v[i].SetZero();
        system->SetParticleFlags(i,b2_wallParticle);
      }
    }
    auto prepared=std::chrono::steady_clock::now();
    world->Step(float(dt),1,1,iterations);
    auto solved=std::chrono::steady_clock::now();
    contacts=system->GetContactCount();
    p=system->GetPositionBuffer();v=system->GetVelocityBuffer();
    for (int i=0;i<points;++i) {
      positions[i]=godot::Vector2(p[i].x/SCALE,p[i].y/SCALE);
      motion[i]=godot::Vector2(v[i].x/SCALE,v[i].y/SCALE);
    }
    auto applied=std::chrono::steady_clock::now();
    prepare_ms+=std::chrono::duration<double,std::milli>(prepared-started).count();
    solve_ms+=std::chrono::duration<double,std::milli>(solved-prepared).count();
    apply_ms+=std::chrono::duration<double,std::milli>(applied-solved).count();
    ++calls;
  }
};
