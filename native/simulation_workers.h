#pragma once
#include <algorithm>
#include <array>
#include <condition_variable>
#include <cstddef>
#include <functional>
#include <mutex>
#include <thread>

// Seven persistent workers plus the submitting thread: at most eight task
// lanes. Submissions are serialized; callbacks must not recursively submit or
// throw (Godot builds without exceptions). No Godot API, RNG, shared-container
// resizing or shared scatter writes in jobs.
class SimulationWorkers {
  std::array<std::thread,7> workers;
  std::mutex submission, state;
  std::condition_variable ready, finished;
  std::function<void(size_t,size_t)> task;
  size_t count=0, generation=0;
  int lanes=1, pending=0;
  bool stopping=false;
  void work(int lane) {
    size_t seen=0;
    std::unique_lock<std::mutex> lock(state);
    for (;;) {
      ready.wait(lock,[&]{ return stopping || generation!=seen; });
      if (stopping) return;
      seen=generation;
      if (lane>=lanes) continue;
      size_t begin=count*lane/lanes, end=count*(lane+1)/lanes;
      lock.unlock();
      task(begin,end);
      lock.lock();
      if (--pending==0) finished.notify_one();
    }
  }
public:
  SimulationWorkers() {
    for (int i=0;i<7;++i) workers[i]=std::thread([this,i]{ work(i+1); });
  }
  ~SimulationWorkers() {
    { std::lock_guard<std::mutex> lock(state); stopping=true; }
    ready.notify_all();
    for (auto &worker:workers) worker.join();
  }
  SimulationWorkers(const SimulationWorkers&)=delete;
  SimulationWorkers& operator=(const SimulationWorkers&)=delete;
  template<class F> void run(size_t n,int width,F fn) {
    if (!n) return;
    if (width<=1) { fn(0,n); return; }
    std::lock_guard<std::mutex> submit(submission);
    {
      std::lock_guard<std::mutex> lock(state);
      task=fn; count=n; lanes=std::min(width,8); pending=lanes-1;
      ++generation;
    }
    ready.notify_all();
    fn(0,n/lanes);
    std::unique_lock<std::mutex> lock(state);
    finished.wait(lock,[&]{ return pending==0; });
    task={};
  }
  static SimulationWorkers &shared() { static SimulationWorkers pool; return pool; }
};
