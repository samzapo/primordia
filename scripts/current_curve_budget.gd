extends RefCounted
## Presentation-only work budget. No simulation or particle counts are changed.
const FULL:=Vector2i(64,32)
const MOBILE:=[Vector2i(24,12),Vector2i(16,8),Vector2i(8,4)]
var mobile:=false
var level:=0
var slow_samples:=0
var calm_since:=-1.0
var last_adjust:=-INF
var last_cost_usec:=0
func configure(value: bool) -> bool:
 if mobile==value:return false
 mobile=value;level=0;slow_samples=0;calm_since=-1;last_adjust=-INF
 return true
func limits() -> Vector2i:return MOBILE[level] if mobile else FULL
func observe(cost_usec: int,now: float) -> bool:
 last_cost_usec=cost_usec
 if not mobile:return false
 if cost_usec>8000:
  slow_samples+=1;calm_since=-1
  if slow_samples>=2 and now-last_adjust>=.25 and level<MOBILE.size()-1:
   level+=1;slow_samples=0;last_adjust=now;return true
 elif cost_usec<3000:
  slow_samples=0
  if calm_since<0:calm_since=now
  if now-calm_since>=8 and now-last_adjust>=8 and level>0:
   level-=1;last_adjust=now;calm_since=now;return true
 else:slow_samples=0;calm_since=-1
 return false
func diagnostics() -> Dictionary:
 return {"mobile":mobile,"level":level,"ordinary":limits().x,"gold":limits().y,"last_build_ms":last_cost_usec/1000.0}
