#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

class PrimordiaMusicMixer : public godot::RefCounted {
  GDCLASS(PrimordiaMusicMixer, godot::RefCounted)
  static constexpr int RATE = 22050, LIMIT = 40;
  struct Channel { int64_t id = -99; double l=0,r=0,tl=0,tr=0; };
  struct Voice { int instrument,lane,release=2147483647; double at=0,rate,gain; };
  struct Event { int offset,instrument,lane; double note,gain; };
  std::vector<godot::PackedFloat32Array> bank;
  std::vector<Voice> voices;
  std::array<Channel,7> channels;
  std::vector<float> left,right;
  int delay_index=0,peak=0,dropped=0;
  int64_t cursor=0;
  double master=0;
  static constexpr int base[16] = {36,60,60,36,60,60,60,60,60,60,60,60,60,60,60,36};
protected:
  static void _bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("configure","samples"), &PrimordiaMusicMixer::configure);
    godot::ClassDB::bind_method(godot::D_METHOD("render","frames","events","sources","volume"), &PrimordiaMusicMixer::render);
    godot::ClassDB::bind_method(godot::D_METHOD("metrics"), &PrimordiaMusicMixer::metrics);
  }
public:
  void configure(const godot::Array &samples) {
    bank.clear();
    for (int i=0;i<samples.size();++i) bank.push_back(samples[i]);
    voices.clear(); channels={}; cursor=0; delay_index=0; master=0; peak=0; dropped=0;
    left.assign(std::lround(RATE*60./128*.75),0); right=left;
    voices.reserve(LIMIT);
  }
  godot::Dictionary metrics() const {
    godot::Dictionary result;
    result["cursor"]=cursor; result["peak_voices"]=peak; result["voices"]=int(voices.size()); result["dropped"]=dropped;
    return result;
  }
  godot::PackedVector2Array render(int frames,const godot::Array &input,const godot::Array &sources,double volume) {
    godot::PackedVector2Array output;
    if(frames<=0 || frames>16384 || bank.size()!=16 || left.empty()) return output;
    for(int lane=0;lane<7;++lane) {
      int64_t identity=-1; double gain=0,pan=0;
      if(lane<sources.size()) {
        godot::Dictionary source=sources[lane];
        identity=source.get("id",-1); gain=source.get("gain",0.); pan=source.get("pan",0.);
      }
      gain=std::isfinite(gain)?std::clamp(gain,0.,2.):0.;
      pan=std::isfinite(pan)?std::clamp(pan,-1.,1.):0.;
      auto &c=channels[lane];
      if(c.id!=identity) for(auto &v:voices) if(v.lane==lane) v.release=std::min(v.release,int(std::lround(RATE*.035)));
      c.id=identity; c.tl=gain*std::sqrt(.5*(1-pan)); c.tr=gain*std::sqrt(.5*(1+pan));
    }
    std::vector<Event> events;
    for(int n=0;n<input.size();++n) {
      godot::Dictionary e=input[n];
      Event v{int(e.get("offset",0)),int(e.get("instrument",-1)),int(e.get("lane",-1)),double(e.get("note",60.)),double(e.get("gain",0.))};
      if(v.offset>=0 && v.offset<frames && v.instrument>=0 && v.instrument<16 && v.lane>=0 && v.lane<7 && std::isfinite(v.note) && std::isfinite(v.gain)) events.push_back(v);
    }
    std::stable_sort(events.begin(),events.end(),[](const Event&a,const Event&b){return a.offset<b.offset;});
    output.resize(frames);
    auto *out=output.ptrw();
    size_t next=0;
    volume=std::isfinite(volume)?std::clamp(volume,0.,1.):0.;
    for(int i=0;i<frames;++i) {
      while(next<events.size() && events[next].offset<=i) {
        const auto &e=events[next++];
        if(voices.size()>=LIMIT) { ++dropped; continue; }
        voices.push_back({e.instrument,e.lane,2147483647,0,std::pow(2.,(std::clamp(e.note,12.,100.)-base[e.instrument])/12.),std::clamp(e.gain,0.,2.)});
      }
      double dry_l=0,dry_r=0,send_l=0,send_r=0;
      double beat=std::fmod(double(cursor+i)/RATE,60./128);
      double duck=.42+.58*std::clamp(beat/.18,0.,1.);
      for(auto &c:channels) { c.l+=(c.tl-c.l)*.002; c.r+=(c.tr-c.r)*.002; }
      for(int n=int(voices.size())-1;n>=0;--n) {
        auto &v=voices[n]; const auto &samples=bank[v.instrument]; int index=int(v.at);
        if(index+1>=samples.size() || v.release<=0) { voices.erase(voices.begin()+n); continue; }
        const float *pcm=samples.ptr();
        double value=(pcm[index]+(pcm[index+1]-pcm[index])*(v.at-index))*v.gain;
        value*=std::min(1.,v.release/(RATE*.035));
        v.at+=v.rate; --v.release;
        const auto &c=channels[v.lane];
        double l=value*c.l,r=value*c.r;
        if(v.instrument>=3) { l*=duck; r*=duck; }
        dry_l+=l; dry_r+=r;
        if(v.instrument>=4) {send_l+=l*.18;send_r+=r*.18;}
      }
      peak=std::max(peak,int(voices.size()));
      double echo_l=left[delay_index],echo_r=right[delay_index];
      left[delay_index]=send_l+echo_r*.26; right[delay_index]=send_r+echo_l*.26;
      delay_index=(delay_index+1)%left.size();
      master+=(volume-master)*.0015;
      out[i]=godot::Vector2(std::tanh((dry_l+echo_l)*.9)*.88*master,std::tanh((dry_r+echo_r)*.9)*.88*master);
    }
    cursor+=frames;
    return output;
  }
};
