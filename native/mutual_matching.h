#pragma once
#include "chemical_catalog.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
// Numeric-only two-pass matching. The caller owns unary chemistry and event publication.
struct PairOutcome { int event=-1,other=-1,neutralizer=-1;double recycled=0,neutralized=0;bool reacted=false; };
struct PairChoice {int partner=-1;godot::Vector2 impulse;};
inline uint32_t pair_hash(uint32_t x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
// Symmetric degree scaling keeps dense overlap impulses bounded without dropping
// contacts, limiting world velocity, or altering chemical encounter choices.
template<class P,class Offset>
std::vector<int> contact_degrees(const std::vector<P> &ps,int lanes,
                                double max_radius,double physical_radius,Offset offset){
 std::vector<int> degrees(ps.size(),0),heads(40960,-1),next(ps.size(),-1);
 auto eligible=[](const P &p){return p.alive&&p.active>0&&p.elapsed>0&&p.kind!=3;};
 auto periodic=[](int value,int extent){int result=value%extent;return result<0?result+extent:result;};
 // The ordered chemistry cache deliberately stores only higher-ID partners.
 // Degrees need all endpoints; build a complete immutable local grid instead.
 for(size_t i=0;i<ps.size();++i)if(eligible(ps[i])){
  int bin=periodic(int(std::floor(ps[i].p.y/16)),160)*256+periodic(int(std::floor(ps[i].p.x/16)),256);
  next[i]=heads[bin];heads[bin]=int(i);
 }
 SimulationWorkers::shared().run(ps.size(),lanes,[&](size_t begin,size_t end){
  for(size_t i=begin;i<end;++i){
   const auto &p=ps[i];if(!eligible(p))continue;
   double reach=std::max(p.radius,physical_radius)+max_radius+.001;
   int lx=std::floor((p.p.x-reach)/16),hx=std::floor((p.p.x+reach)/16),
       ly=std::floor((p.p.y-reach)/16),hy=std::floor((p.p.y+reach)/16);
   for(int x=lx;x<=hx;++x)for(int y=ly;y<=hy;++y)
    for(int j=heads[periodic(y,160)*256+periodic(x,256)];j>=0;j=next[j]){
     if(int(i)==j)continue;
     double contact=physical_radius>0?2*physical_radius:p.radius+ps[j].radius;
     if(offset(p.p,ps[j].p).length_squared()<contact*contact)++degrees[i];
    }
  }
 });
 return degrees;
}
template<class P,class Grid,class Offset,class Acid>
void mutual_matching(std::vector<P> &ps,Grid &grid,int lanes,uint32_t tick,
                     double max_radius,double physical_radius,bool collisions,
                     Offset offset,Acid acid,std::vector<PairChoice> &choices,std::vector<PairOutcome> &outcomes){
 choices.assign(ps.size(),{});outcomes.assign(ps.size(),{});
 const auto degrees=collisions?contact_degrees(ps,lanes,max_radius,physical_radius,offset):std::vector<int>();
 auto available=[](const P &p){return p.alive&&p.active>0&&p.elapsed>0&&p.kind!=3;};
 auto eligible=[](const P &a,const P &b,double acidity){
  if((a.kind==6&&b.kind==2)||(a.kind==2&&b.kind==6))return acidity<.9;
  if((a.kind==7&&(b.kind==4||b.kind==11||b.kind==12))||((a.kind==4||a.kind==11||a.kind==12)&&b.kind==7))return true;
  if((a.kind==8&&b.kind==9)||(a.kind==9&&b.kind==8))return std::min(a.capacity,b.capacity)>0;
  if(a.kind==2&&b.kind==1)return b.amount>=a.amount*.15&&acidity<.8;
  if(a.kind==1&&b.kind==2)return a.amount>=b.amount*.15&&acidity<.8;
  if((a.kind==0&&b.kind==4)||(a.kind==4&&b.kind==0))return true;
  return a.kind==b.kind&&(a.kind==0||a.kind==1||a.kind==2||a.kind==5)&&a.amount+b.amount>0&&a.amount+b.amount<=(a.kind==0?primordia_chemistry::nutrient_merge_limit:primordia_chemistry::merge_limit);
 };
 SimulationWorkers::shared().run(ps.size(),lanes,[&](size_t begin,size_t end){
  for(size_t i=begin;i<end;++i){
   const auto &p=ps[i];if(!available(p))continue;
   auto &choice=choices[i];uint32_t best_score=0,best_random=0;uint64_t best_low=0,best_high=0;
   grid.readonly_grid_visit(ps,int(i),std::max(p.radius,physical_radius)+max_radius+.001,[&](int j){
    if(int(i)==j||!available(ps[j]))return false;
    int low=p.identity<ps[j].identity?int(i):j,high=low==int(i)?j:int(i);
    const auto &a=ps[low],&b=ps[high];auto d=offset(a.p,b.p);
    double ds=d.length_squared(),c=a.radius+b.radius,physical=physical_radius>0?2*physical_radius:c;
    if(ds>std::max(c,physical)*std::max(c,physical))return false;
    double distance=std::sqrt(ds);godot::Vector2 n=ds>.000001?d/distance:godot::Vector2(1,0);
    if(collisions&&ds<physical*physical)choice.impulse+=(low==int(i)?-n:n)*(physical-distance)*2/std::max(1,std::max(degrees[i],degrees[j]));
    if(p.reacted||ps[j].reacted||ds>c*c)return false;
    bool enzyme=(a.kind==6&&b.kind==2)||(a.kind==2&&b.kind==6)||(a.kind==0&&b.kind==0);
    bool recycling=(a.kind==2&&b.kind==1)||(a.kind==1&&b.kind==2);
    double acidity=(enzyme||recycling)?acid(a.p):0;
    if(!eligible(a,b,acidity))return false;
    double threshold=.5+(enzyme?.46*std::pow(std::clamp(std::abs(acidity-.25)/.25,0.,1.),2):0);
    double alignment=std::min(double(a.dir.dot(n)),double(b.dir.dot(-n)));
    if(alignment<threshold)return false;
    uint64_t aid=a.handle?a.handle:uint64_t(a.identity)+1,bid=b.handle?b.handle:uint64_t(b.identity)+1;
    uint64_t lo=std::min(aid,bid),hi=std::max(aid,bid);
    uint32_t score=uint32_t(std::clamp(alignment,0.,1.)*1024);
    uint32_t random=pair_hash(uint32_t(lo)^pair_hash(uint32_t(hi))^pair_hash(uint32_t(lo>>32))^pair_hash(uint32_t(hi>>32))^pair_hash(tick));
    if(choice.partner<0||score>best_score||(score==best_score&&(random>best_random||(random==best_random&&(lo>best_low||(lo==best_low&&hi>best_high)))))){
     choice.partner=j;best_score=score;best_random=random;best_low=lo;best_high=hi;
    }
    return false;
   });
  }
 });
 // Disjoint pairs permit exclusive writes. No engine objects, RNG or counters on workers.
 SimulationWorkers::shared().run(ps.size(),lanes,[&](size_t begin,size_t end){
  for(size_t i=begin;i<end;++i){
   int j=choices[i].partner;
   bool mutual=j>=0&&choices[j].partner==int(i);
   if(mutual&&ps[i].identity>ps[j].identity)continue;
   auto &a=ps[i];a.v+=choices[i].impulse;
   if(!mutual)continue;
   auto &b=ps[j];b.v+=choices[j].impulse;
   P *u=&a,*v=&b;
   if((u->kind==2&&v->kind==6)||((u->kind==4||u->kind==11||u->kind==12)&&v->kind==7)||(u->kind==1&&v->kind==2)||(u->kind==4&&v->kind==0))std::swap(u,v);
   auto &event=outcomes[i];event.reacted=true;event.other=j;
   if(u->kind==6&&v->kind==2){v->kind=0;v->capacity=0;event.event=5;event.recycled=v->amount;}
   else if(u->kind==7&&(v->kind==4||v->kind==11||v->kind==12)){event.neutralizer=u==&a?int(i):j;event.neutralized=v->amount;u->kind=2;u->amount+=v->amount;v->alive=false;event.event=6;}
   else if((u->kind==8||u->kind==9)&&(v->kind==8||v->kind==9)){
    double used=std::min(u->capacity,v->capacity);u->capacity-=used;v->capacity-=used;
    if(u->capacity<=.000001)u->kind=2;if(v->capacity<=.000001)v->kind=2;
   }else if(u->kind==2&&v->kind==1){
    double amount=u->amount;u->kind=0;u->capacity=0;u->amount=amount*.6;v->kind=5;v->amount=amount*.4;event.event=2;event.recycled=amount*.6;
   }else if(u->kind==0&&v->kind==4){u->kind=2;event.event=4;}
   else {double total=u->amount+v->amount;u->v=u->v.lerp(v->v,v->amount/total);u->capacity=u->kind==0?primordia_chemistry::nutrient_capacity(u->amount,u->capacity,v->amount,v->capacity,acid(a.p)):u->capacity+v->capacity;u->amount=total;v->alive=false;event.event=1;}
   a.reacted=b.reacted=true;
  }
 });
}
