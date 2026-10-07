#include "../native/simulation_workers.h"
#include <atomic>
#include <cassert>
#include <vector>
#include <iostream>
int main() {
  SimulationWorkers pool;
  std::vector<int> data(50003,0);
  for (int repeat=0;repeat<64;++repeat) for (int width=1;width<=8;++width) {
    pool.run(data.size(),width,[&](size_t begin,size_t end) {
      for(size_t i=begin;i<end;++i) data[i]+=int(i%13)+1;
    });
  }
  for(size_t i=0;i<data.size();++i) assert(data[i]==512*(int(i%13)+1));
  std::atomic<int> calls{0};
  std::thread a([&]{for(int i=0;i<30;++i) pool.run(100,8,[&](size_t b,size_t e){calls+=int(e-b);});});
  std::thread b([&]{for(int i=0;i<30;++i) pool.run(100,8,[&](size_t b,size_t e){calls+=int(e-b);});});
  a.join();b.join();assert(calls==6000);
  pool.run(0,8,[&](size_t,size_t){assert(false);});
  for (int n=1;n<9;++n) {
    std::atomic<int> visits{0};pool.run(n,8,[&](size_t b,size_t e){visits+=int(e-b);});assert(visits==n);
  }
  std::cout<<"Worker range, barrier, concurrent submission and shutdown checks passed\n";
}
