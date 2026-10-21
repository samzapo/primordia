#pragma once
#include <godot_cpp/variant/vector2.hpp>
#include <cmath>
#include <algorithm>
namespace primordia_mouth {
// First2560 entries are real water. Remaining pairs: mouth xy, reach/power.
inline godot::Vector2 pull(const godot::Vector2 *field,int count,godot::Vector2 at,int kind) {
 godot::Vector2 best;double strongest=-1;
 for(int i=2560;i+1<count;i+=2) {
  double x=double(field[i].x)-at.x,y=double(field[i].y)-at.y;
  x-=4096*std::floor((x+2048)/4096);y-=2560*std::floor((y+1280)/2560);
  godot::Vector2 d(x,y);double distance=d.length(),reach=field[i+1].x;
  if(distance>=reach||distance<.000001)continue;
  double speed=field[i+1].y*(1-distance/reach)*std::min(1.,distance/24.);
  if(speed>strongest+.0001){strongest=speed;best=d*(speed/distance);}
 }
 return best*(kind==0?1.:.2);
}
}
