# Revision 34 — resident GPU particles and mobile comparison

This is an opt-in transport/rendering prototype, not a new gameplay backend. Ordinary Primordia keeps the Revision 33 CPU simulation, circular contacts, ordered reactions, finite feeding, body exclusion and resource rules. No density increase or phone-performance claim follows from the prototype.

## What is implemented

A compute pass on Godot's **main** RenderingDevice advances particle position, launch velocity, age and orientation in an RGBA32F texture. The vertex shader reads that texture directly through Texture2DRD. No position download, CPU transform reconstruction or per-tick upload is needed in GPU mode. Existing authored branched particle glyphs are assembled into an atlas at startup and drawn in one MultiMesh batch. RD creation, dispatch, upload, snapshot and retirement run on the render thread; Godot's main device is never freed by the prototype.

Three diagnostic paths share initial state, prescribed flow and artwork:

- GPU: persistent compute state and direct texture drawing.
- CPU-texture: native CPU transport, state upload, same texture-driven drawing.
- CPU-MultiMesh: native CPU transport, CPU-built transforms, instance-buffer upload.

The native reference accepts one through eight lanes. A portable GDScript implementation is an independent correctness oracle; it is **not** substituted for native CPU performance if an exported build lacks the extension.

The synthetic fixed-inventory fixture preserves 300 units across 5k–100k packets and all eleven visual species. It runs periodic advection, Gaussian translational/rotational diffusion, velocity damping and coarse midpoint integration. A stateless counter-based diagnostic random stream changes every tick. This is not gameplay RNG or a replacement chemical model. Validation is tolerance-based, not a claim of cross-platform deterministic ecology.

**Omitted:** contacts, reactions, cells/plants, body feedback, feeding, emissions, expiry, music, inspection, live catch-up and offscreen ecology. The fixed population stays dense without implementing an emission-balanced ecosystem. Zoom is 80%, but there are no large cells in this standalone scene. The existing whole-game growth/cluster harness remains an integration gate.

A seam test found a wrapping error in the older experimental transport shader. Signed integer remainder on negative grid indices was replaced with explicitly positive modulo in both experimental samplers. Default CPU simulation is unchanged.

## Desktop use

Steam discovery remains the default:

~~~sh
./tools/particles_compare.sh validate
./tools/particles_compare.sh gpu --count=50000 --frames=300 --output=/tmp/gpu.json
./tools/particles_compare.sh cpu-texture --count=50000 --threads=4 --frames=300 --output=/tmp/cpu-texture.json
./tools/particles_compare.sh cpu-multimesh --count=50000 --threads=4 --frames=300 --output=/tmp/cpu-multimesh.json
python3 tools/resident_report.py /tmp/gpu.json /tmp/cpu-texture.json /tmp/cpu-multimesh.json
~~~

Use --distribution=clustered|seam, --threads=1|2|4|8, and 20k/50k/100k. Unsupported renderers/capacities fail explicitly. Use Mobile/Forward+, not headless or Compatibility. Compilation and 60 warmup ticks precede measurement.

Each frame advances one 1/60-second prototype tick. Unlimited captures measure fixed-step throughput, not real-time gameplay. At a 30 FPS cap this fixed-step fixture advances only 30 ticks/s (half simulation speed); it is a reduced-work diagnostic, not a 60 Hz gameplay fallback. Compare equal caps and report simulated time separately. Warmup is fenced before measurement; final state and viewport readback occur afterward. Reports retain submission-frame intervals and final drain/readback cost separately. The report tool also gives a completed-window mean including that cost, conservatively including transfer overhead. Delayed viewport GPU timings are not a complete compute-pass measurement and must not be added to overlapping CPU phases.

## Pixel 9 Pro XL and Galaxy Z Flip7

These are the owner's first device targets. Actual phone runs are pending: neither device is accessible from this task, and the workstation has no available ADB command or configured Android NDK. No APK, installation, battery result or thermal result is claimed.

Generate an isolated export project:

~~~sh
python3 tools/prepare_mobile_benchmark.py
~~~

Open build/resident-mobile/project.godot in Godot 4.7.2. It offers touch controls, 5k/20k/50k/100k counts, uniform/clustered/seam distributions, 30/60 FPS caps, 30/60/600-second runs, cancellation, and JSON report copying. Reports also remain in user://. Suspension invalidates a run. The input manifest copies only authored benchmark files, not gameplay, dependencies, caches or generated libraries.

For a native CPU comparison, build the small ARM64 reference directly into that generated project:

~~~sh
# Prepare pinned bindings with the ordinary native build if needed.
ANDROID_NDK_ROOT=/path/to/installed/ndk PRIMORDIA_BUILD_JOBS=2 \
  ./tools/build_mobile_benchmark.sh android
~~~

The recipe uses the installed NDK CMake toolchain, ARM64 and pinned godot-cpp. It downloads no SDK, changes no global settings and requests no signing secrets. Configure Android SDK/export templates in your Godot environment and export a debug APK using the Android preset. The cross-build and APK export still need validation with those tools. The same minimal reference was built and run on desktop using tools/build_mobile_benchmark.sh desktop, including repeated GPU/native starts and cancellation.

Without the extension, CPU comparisons are explicitly disabled. GPU-only tests cannot establish an advantage over native CPU. iPhone/iPad testing and a native iOS reference/export recipe remain pending; no Apple device was supplied.

### Sustained protocol

1. Record model, OS, resolution, brightness, battery percentage, charging state and ambient conditions; keep them consistent. Charging changes thermal behavior.
2. Start at 20k, then 50k, with uniform and clustered distributions. Compare all three backends and 1/2/4/8 CPU lanes.
3. Use ten-minute 60 FPS capped runs, then 30 FPS if needed. Match work rate, alternate order and allow cooldown.
4. Compare 30-second timing windows, OS thermal status and energy observations. Short throughput gains alone do not establish sustained efficiency.
5. Retain failures/unsupported-device results. Check orientation, wrapping and resume visually.

For an already-authorized, explicitly selected Android ADB device:

~~~sh
python3 tools/android_thermal_capture.py --serial DEVICE_SERIAL \
  --label pixel9proxl-gpu-50k-60fps --seconds=600 --output=/tmp/thermal.json
~~~

The collector only reads model, thermal and battery services. It records denied/missing telemetry, without altering clocks, power modes, brightness or permissions. Battery temperature is not SoC temperature; battery-percent change alone is not precise workload energy. Sustained benchmark captures require 30/60 FPS caps for comparable work and bounded reporting memory.

## Promotion gate

Next add circular neighbor/contact work and ordered reaction conflicts, then finite biological transactions and body feedback, preserving coherent authoritative state and inspection. Measure all transfers, synchronization and rendering together. Whole-game 80% view, large cells, dense clumps, music on/off and equal-horizon ecology checks remain required. Keep CPU gameplay until mobile compatibility and sustained whole-game performance justify a change.

## References

- [Godot compute texture demo](https://godotengine.org/asset-library/asset/2764): main-device compute feeds materials through Texture2DRD.
- [Godot compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html): RD renderer requirements and mobile driver limitations.
- [Apple synchronization](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work): dependency stalls.
- [Android thermal guidance](https://developer.android.com/games/optimize/adpf/thermal): sustained device measurement.

## Desktop evidence

Godot 4.7.2, Mobile/Vulkan, RTX 5080 / Ryzen 9950X, real GPU-backed headless Weston output at 1440×900. Synthetic fixed populations, 80% zoom, 60 warmup ticks and 300 measured frames. These short captures exclude whole-game work and do not predict phone performance.

The table gives **completed-window mean ms per prototype tick/frame**, including the final drain/readback cost amortized across the measured window:

| Population | Native CPU + MultiMesh, 8 lanes | Native CPU + texture, 8 lanes | GPU resident |
| --- | ---: | ---: | ---: |
| 20k uniform | 0.765 | 0.578 | 0.114 |
| 50k uniform | 1.487 | 1.261 | 0.144 |
| 100k uniform | 2.848 | 3.790 | 0.196 |

A reversed-order 50k confirmation measures **1.403 / 1.279 / 0.155 ms**, respectively. Submission-interval p95 values for that confirmation are 1.483 / 1.341 / 0.150 ms; the final drains are 2.755 / 3.104 / 3.226 ms and are not included in those p95 values. At 50k, two/four-lane CPU-MultiMesh means including completion are 2.268 / 1.709 ms; CPU-texture gives 2.078 / 1.441 ms.

Keeping everything resident clearly helps this limited workload. Uploading CPU state for shader drawing is less decisive and loses at 100k; it is not enabled in gameplay. These results must not be reported as a tenfold whole-game speedup. The dense contact/reaction costs that motivated the larger optimization effort are absent here.

The one-minute, 50k GPU run at a 60 FPS cap retains its full population and material. Across 3,602 measured frames, its mean/p95 submission interval is **16.66 / 17.20 ms**, with an 11.773 ms final drain/readback. Its two complete 30-second windows average 16.65 and 16.67 ms. This validates a bounded desktop run, not phone thermals, battery use, ten-minute stability or 50k gameplay at 60 FPS.

## Validation

- Native game suite: **69,707 assertions, zero failures**.
- Script fallback: **3,294 assertions, zero failures**.
- Launcher fixtures: **11 passed**.
- Independent resident CPU tests: 14 checks, including lane equivalence, coarse integration, malformed inputs, finite inventory and detached snapshots.
- Six GPU comparisons cover partial workgroups (127/128/129), texture-row boundaries, torus seams, coarse steps, 5k clustered/120 ticks and 50k uniform/360 ticks. Maximum measured position error in the 50k case is **0.00110 world units**, angle error **0.000064 radians**; immutable metadata matches exactly.
- Existing synchronous GPU transport parity/coarse/edge checks pass after the sampler fix.
- Generated export project imports; its desktop native extension builds and loads. Touch launcher rendering, repeated GPU/native runs and cancellation pass desktop checks.
- Invalid capacity, uncapped sustained-run parameters and unsupported headless rendering fail explicitly.
- Whitespace checks and editor imports pass. Android compilation/export, on-device ten-minute tests, thermal/energy telemetry and Apple-device validation remain unperformed.

Early seam failures and an abandoned import-based shader attempt were repaired before the reported checks. The retained raw shader text avoids depending on compute-asset import and is included by the generated export preset. An initial exploratory matrix omitted explicit completion-drain accounting; the table above uses the later fenced captures. Generated libraries, profiles, screenshots and traces remain outside Git.
