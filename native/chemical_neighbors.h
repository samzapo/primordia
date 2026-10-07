#pragma once
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <vector>

// Chemistry uses circular encounters. These indices only choose conservative
// candidates; binding, impulse arithmetic and RNG stay in the original kernel.
class ChemicalNeighbors {
  static constexpr int COLS=256, ROWS=160, CELLS=COLS*ROWS;
  static constexpr double SKIN=2., MARGIN=.001;
  static int mod(int x,int n) { return (x%n+n)%n; }
  static double wrapped(double x,double n) { return x-n*std::floor(x/n); }
  struct Node { double lx,ly,hx,hy; int left=-1,right=-1,begin=0,end=0; };
  struct Quad { double lx=0,ly=0,hx=0,hy=0,radius=0; int children[4]={-1,-1,-1,-1}; int begin=0,end=0; };
  struct Leaf { uint32_t code; int id; };
  struct Reference { double x,y,r; uint64_t handle; int identity; bool eligible; };
  std::vector<std::vector<int>> bins;
  std::vector<int> occupied, counts, offsets, cursors, packed, candidates;
  std::vector<Leaf> leaves;
  std::vector<Node> nodes;
  std::vector<Quad> quads;
  std::vector<Reference> references;
  std::vector<int> cache_offsets, cache_pairs;
  bool cache_valid=false;
  double query_partner_radius=0;
  uint64_t builds=0,hits=0,misses=0,overflows=0,calls=0,background_calls=0;
  uint64_t delivered=0,owned=0,contacts=0;
  double build_ms=0,search_sort_ms=0,cache_build_ms=0;
  static uint32_t spread(uint32_t v) {
    v=(v|(v<<8))&0x00ff00ff; v=(v|(v<<4))&0x0f0f0f0f;
    v=(v|(v<<2))&0x33333333; return (v|(v<<1))&0x55555555;
  }
  template<class P> static bool eligible(const P &p) { return p.active>0 && p.kind!=3; }
  template<class P> int make_node(const std::vector<P> &ps,int begin,int end) {
    int id=nodes.size(); nodes.emplace_back();
    Node n; n.begin=begin; n.end=end;
    if (end-begin<=8) {
      n.lx=n.ly=1e30; n.hx=n.hy=-1e30;
      for (int i=begin;i<end;++i) {
        const auto &p=ps[leaves[i].id];
        n.lx=std::min(n.lx,double(p.p.x)-p.radius);
        n.ly=std::min(n.ly,double(p.p.y)-p.radius);
        n.hx=std::max(n.hx,double(p.p.x)+p.radius);
        n.hy=std::max(n.hy,double(p.p.y)+p.radius);
      }
    } else {
      int mid=(begin+end)/2;
      n.left=make_node(ps,begin,mid); n.right=make_node(ps,mid,end);
      const auto &a=nodes[n.left]; const auto &b=nodes[n.right];
      n.lx=std::min(a.lx,b.lx); n.ly=std::min(a.ly,b.ly);
      n.hx=std::max(a.hx,b.hx); n.hy=std::max(a.hy,b.hy);
    }
    nodes[id]=n; return id;
  }
  template<class P> void tree_query(const std::vector<P> &ps,int id,double x,double y,double r) {
    const auto &n=nodes[id];
    if (n.lx>x+r || n.hx<x-r || n.ly>y+r || n.hy<y-r) return;
    if (n.left>=0) {
      tree_query(ps,n.left,x,y,r); tree_query(ps,n.right,x,y,r); return;
    }
    for (int i=n.begin;i<n.end;++i) {
      int j=leaves[i].id; const auto &p=ps[j];
      if (std::abs(double(p.p.x)-x)<=r+p.radius && std::abs(double(p.p.y)-y)<=r+p.radius)
        candidates.push_back(j);
    }
  }
  template<class P> int make_quad(const std::vector<P> &ps,int begin,int end,int shift,
                                  double lx,double ly,double hx,double hy) {
    int id=quads.size(); quads.emplace_back();
    Quad n; n.begin=begin; n.end=end; n.lx=lx; n.ly=ly; n.hx=hx; n.hy=hy;
    if (end-begin<=16 || shift<0) {
      for (int k=begin;k<end;++k) n.radius=std::max(n.radius,ps[leaves[k].id].radius);
    } else {
      double mx=(lx+hx)*.5,my=(ly+hy)*.5;
      int k=begin;
      while (k<end) {
        int q=(leaves[k].code>>shift)&3,first=k;
        while (k<end && int((leaves[k].code>>shift)&3)==q) ++k;
        n.children[q]=make_quad(ps,first,k,shift-2,q&1 ? mx : lx,q&2 ? my : ly,q&1 ? hx : mx,q&2 ? hy : my);
        n.radius=std::max(n.radius,quads[n.children[q]].radius);
      }
    }
    quads[id]=n; return id;
  }
  template<class P> void quad_query(const std::vector<P> &ps,int id,double x,double y,double r) {
    const auto &n=quads[id]; double bound=r+n.radius;
    if (n.lx>x+bound || n.hx<x-bound || n.ly>y+bound || n.hy<y-bound) return;
    bool leaf=true;
    for (int child:n.children) if (child>=0) { leaf=false; quad_query(ps,child,x,y,r); }
    if (!leaf) return;
    for (int i=n.begin;i<n.end;++i) {
      int j=leaves[i].id; const auto &p=ps[j];
      if (std::abs(double(p.p.x)-x)<=r+p.radius && std::abs(double(p.p.y)-y)<=r+p.radius)
        candidates.push_back(j);
    }
  }
  template<class P> void order(const std::vector<P> &ps,int lx,int ly) {
    // Restore original x-major/y-minor bin order, then input insertion order.
    // Relative coordinates make seam queries identical to unwrapped grid loops.
    auto rank=[&](int j) {
      int b=ps[j].neighbor_bin;
      return mod(b%COLS-lx,COLS)*ROWS+mod(b/COLS-ly,ROWS);
    };
    std::sort(candidates.begin(),candidates.end(),[&](int a,int b) {
      int ra=rank(a),rb=rank(b); return ra==rb ? a<b : ra<rb;
    });
    candidates.erase(std::unique(candidates.begin(),candidates.end()),candidates.end());
  }
  template<class P,class F> void index_visit(const std::vector<P> &ps,int i,double reach,F visit) {
    const auto &p=ps[i];
    int lx=std::floor((p.p.x-reach)/16),hx=std::floor((p.p.x+reach)/16),
        ly=std::floor((p.p.y-reach)/16),hy=std::floor((p.p.y+reach)/16);
    if (backend>=2) {
      auto mark=metrics ? Clock::now() : Clock::time_point{};
      candidates.clear();
      // Radius-expanded BVH bounds need only the query particle's radius.
      // Nine translated queries conservatively cover the periodic domain;
      // root AABBs reject distant translations immediately.
      for (int x=-1;x<=1;++x) for (int y=-1;y<=1;++y)
        if (backend==2 && !nodes.empty()) tree_query(ps,0,p.p.x+x*4096.,p.p.y+y*2560.,reach-query_partner_radius);
        else if (backend==3 && !quads.empty()) quad_query(ps,0,p.p.x+x*4096.,p.p.y+y*2560.,reach-query_partner_radius);
      order(ps,lx,ly);
      if (metrics) search_sort_ms+=elapsed(mark);
      for (int j:candidates) { if (metrics) ++delivered; if (visit(j)) return; }
      return;
    }
    for (int x=lx;x<=hx;++x) for (int y=ly;y<=hy;++y) {
      int b=mod(y,ROWS)*COLS+mod(x,COLS);
      if (backend==0) {
        for (int j:bins[b]) { if (metrics) ++delivered; if (visit(j)) return; }
      } else {
        for (int k=offsets[b];k<offsets[b]+counts[b];++k) {
          if (metrics) ++delivered;
          if (visit(packed[k])) return;
        }
      }
    }
  }
  template<class P> void build(const std::vector<P> &ps) {
    auto mark=Clock::now(); if (metrics) ++builds;
    if (backend>=2) {
      leaves.clear(); nodes.clear(); quads.clear();
      for (int i=0;i<int(ps.size());++i) if (eligible(ps[i])) {
        uint32_t x=std::clamp(int(ps[i].p.x/4),0,1023),
                 y=std::clamp(int(ps[i].p.y/2.5),0,1023);
        leaves.push_back({spread(x)|(spread(y)<<1),i});
      }
      std::sort(leaves.begin(),leaves.end(),[](const Leaf &a,const Leaf &b) {
        return a.code==b.code ? a.id<b.id : a.code<b.code;
      });
      if (backend==2) {
        nodes.reserve(leaves.size()/2+1);
        if (!leaves.empty()) make_node(ps,0,leaves.size());
      } else {
        quads.reserve(leaves.size()/2+1);
        if (!leaves.empty()) make_quad(ps,0,leaves.size(),18,0,0,4096,2560);
      }
    } else if (backend==0) {
      if (bins.empty()) bins.resize(CELLS);
      for (int b:occupied) bins[b].clear();
      occupied.clear();
      for (int i=0;i<int(ps.size());++i) if (eligible(ps[i])) {
        int b=ps[i].neighbor_bin;
        if (bins[b].empty()) occupied.push_back(b);
        bins[b].push_back(i);
      }
    } else {
      if (counts.empty()) { counts.resize(CELLS); offsets.resize(CELLS); cursors.resize(CELLS); }
      std::fill(counts.begin(),counts.end(),0);
      for (const auto &p:ps) if (eligible(p)) ++counts[p.neighbor_bin];
      int total=0;
      for (int b=0;b<CELLS;++b) { offsets[b]=cursors[b]=total; total+=counts[b]; }
      packed.resize(total);
      // Count/prefix/scatter packs each bin contiguously without sorting slots.
      for (int i=0;i<int(ps.size());++i) if (eligible(ps[i])) {
        int k=cursors[ps[i].neighbor_bin]++;
        packed[k]=i;
      }
    }
    if (metrics) build_ms+=elapsed(mark);
  }
  template<class P> bool reusable(const std::vector<P> &ps) const {
    if (!cache_valid || ps.size()!=references.size()) return false;
    for (int i=0;i<int(ps.size());++i) {
      const auto &p=ps[i]; const auto &r=references[i];
      if (p.identity!=r.identity || p.handle!=r.handle || (eligible(p) && !r.eligible)) return false;
      if (!eligible(p)) continue;
      double dx=wrapped(double(p.p.x)-r.x+2048,4096)-2048,
             dy=wrapped(double(p.p.y)-r.y+1280,2560)-1280;
      // Each endpoint may consume half the skin through motion/radius growth.
      if (std::sqrt(dx*dx+dy*dy)+std::max(0.,p.radius-r.r)>SKIN*.5) return false;
    }
    return true;
  }
  template<class P> void make_cache(const std::vector<P> &ps,double max_radius) {
    auto mark=Clock::now();
    cache_offsets.assign(ps.size()+1,0); cache_pairs.clear();
    constexpr size_t LIMIT=8*1024*1024; // bounded diagnostic memory, never truncate physics
    for (int i=0;i<int(ps.size());++i) {
      cache_offsets[i]=cache_pairs.size();
      if (eligible(ps[i])) index_visit(ps,i,ps[i].radius+max_radius+SKIN+MARGIN,[&](int j) {
        const auto &p=ps[i]; const auto &b=ps[j];
        if (b.identity<=p.identity) return false;
        double dx=wrapped(double(b.p.x)-p.p.x+2048,4096)-2048,
               dy=wrapped(double(b.p.y)-p.p.y+1280,2560)-1280,
               r=p.radius+b.radius+SKIN+MARGIN;
        if (dx*dx+dy*dy<=r*r) cache_pairs.push_back(j);
        return cache_pairs.size()>LIMIT;
      });
      if (cache_pairs.size()>LIMIT) {
        cache_valid=false; cache_pairs.clear(); if (metrics) ++overflows;
        if (metrics) cache_build_ms+=elapsed(mark); return;
      }
    }
    cache_offsets.back()=cache_pairs.size(); references.clear(); references.reserve(ps.size());
    for (const auto &p:ps) references.push_back({double(p.p.x),double(p.p.y),p.radius,p.handle,p.identity,eligible(p)});
    cache_valid=true;
    if (metrics) cache_build_ms+=elapsed(mark);
  }
public:
  using Clock=std::chrono::steady_clock;
  static double elapsed(Clock::time_point t) { return std::chrono::duration<double,std::milli>(Clock::now()-t).count(); }
  int backend=0; bool caching=false,metrics=false,use_cache=false;
  void configure(int b,bool c,bool m) {
    if (backend!=b || caching!=c) cache_valid=false;
    backend=b; caching=c; metrics=m;
  }
  void reset_metrics() { builds=hits=misses=overflows=calls=background_calls=delivered=owned=contacts=0; build_ms=search_sort_ms=cache_build_ms=0; }
  template<class P> void begin(const std::vector<P> &ps,double max_radius,bool background) {
    query_partner_radius=max_radius;
    if (metrics) { ++calls; if (background) ++background_calls; }
    use_cache=caching && !background;
    if (use_cache && reusable(ps)) { if (metrics) ++hits; return; }
    if (use_cache && metrics) ++misses;
    build(ps);
    if (use_cache) { make_cache(ps,max_radius); use_cache=cache_valid; }
  }
  template<class P,class F> void visit(const std::vector<P> &ps,int i,double reach,F visitor) {
    if (!use_cache) { index_visit(ps,i,reach,visitor); return; }
    auto mark=Clock::now();
    candidates.assign(cache_pairs.begin()+cache_offsets[i],cache_pairs.begin()+cache_offsets[i+1]);
    int lx=std::floor((ps[i].p.x-reach)/16),ly=std::floor((ps[i].p.y-reach)/16);
    order(ps,lx,ly);
    if (metrics) search_sort_ms+=elapsed(mark);
    for (int j:candidates) { if (metrics) ++delivered; if (visitor(j)) return; }
  }
  void owned_candidate() { if (metrics) ++owned; }
  void contact() { if (metrics) ++contacts; }
  uint64_t index_builds() const { return builds; }
  uint64_t cache_hits() const { return hits; }
  uint64_t cache_misses() const { return misses; }
  uint64_t cache_overflows() const { return overflows; }
  uint64_t chemistry_calls() const { return calls; }
  uint64_t coarse_calls() const { return background_calls; }
  uint64_t candidate_count() const { return delivered; }
  uint64_t owned_count() const { return owned; }
  uint64_t contact_count() const { return contacts; }
  double build_time() const { return build_ms; }
  double search_time() const { return search_sort_ms; }
  double cache_time() const { return cache_build_ms; }
  size_t memory_bytes() const {
    size_t n=bins.capacity()*sizeof(std::vector<int>);
    for (const auto &b:bins) n+=b.capacity()*sizeof(int);
    for (const auto *v:{&occupied,&counts,&offsets,&cursors,&packed,&candidates,&cache_offsets,&cache_pairs}) n+=v->capacity()*sizeof(int);
    return n+quads.capacity()*sizeof(Quad)+nodes.capacity()*sizeof(Node)+leaves.capacity()*sizeof(Leaf)+references.capacity()*sizeof(Reference);
  }
};
