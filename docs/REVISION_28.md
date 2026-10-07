# Revision 28 — overlapping chemical particles

Chemical particles now overlap by default. Unsuccessful encounters no longer push them apart; compatible species still react when their circular encounter ranges and oriented binding faces agree. Their forks and branches remain artwork and binding cues, never non-spherical collision geometry.

## Play the comparison

Launch normally with `./tools/run.sh`. In Escape settings, **Particle collisions** is off by default; turn it on to restore the previous soft repulsion. The choice applies immediately, persists across launches and new expeditions, and does not restart the habitat or export the native pool.

Current advection, independent positional random walks and rotational diffusion retain their previous strengths. Decay, feeding, toxin contact, material accounting, receptor perception and reaction sparks remain active. Chemical particles still stay outside deformed living membranes and pass through plant stems. Physical cell, spike and plant contacts retain their existing rules; pheromones still bypass solids and chemistry.

Diffusion spreads a coincident cloud without collision forces. It does not guarantee a uniform distribution: currents and feeding pumps concentrate material, and successful nutrient assembly merges packets. The dense preview keeps recognizable clouds instead of the strong outward scattering seen with repulsion.

## Checks

- Native suite: **7,023 assertions, zero failures**.
- Independent script suite: **3,289 assertions, zero failures**.
- Godot 4.7.2 editor import and whitespace checks pass.
- Focused tests exercise script, native dictionaries and the authoritative pool, foreground and hidden chemistry, both collision settings, wrapped encounters, species/facing rejection, finite nutrient assembly and live switching. A zero-current cloud test checks the existing random-walk spreading rate.
- Settings tests cover persistence and world restart without advancing simulation or dropping native ownership. The pool chemistry comparison covers both collision modes across 1,452 species/order/acidity/alignment cases.
- Both modes render successfully at the widest playable 80% view. The paired preview starts from a finite 20,000-packet clustered fixture and advances three simulated seconds: 5,790 packets remain with collisions off, 4,913 with collisions on. These are diagnostic packet subdivisions, not extra gameplay material or a higher default density.

## Performance result

**This visual trial is not a performance improvement.** Reaction searches still need nearby particles, even when separation forces are disabled.

Godot 4.7.2, Ryzen 9950X / RTX 5080, Mobile renderer, 1440×900 virtual Wayland output, 80% view. Music preparation/playback, bloom, streamers, wakes, membrane graphics and reaction sparks stay enabled. Dummy audio and a virtual GPU-rendered display do not constitute an owner-machine or speaker playtest. The RTX 3090 / Threadripper 2990WX Steam machine remains untested.

The fixed comparison starts with 50,000 finite chemical packets, ordinary cells and paid cilia, uniform distribution and the current fluid backend. Each trace displays 120 frames and advances one 1/60-second tick per frame: exactly two simulated seconds. Two trials per setting ran in reversed order.

| Particle collisions | Whole-frame mean, trials | Whole-frame p95, trials | Minimum packet count observed |
| --- | --- | --- | --- |
| On | 37.47 / 38.81 ms | 56.74 / 57.58 ms | 19,606 |
| Off | 45.03 / 43.86 ms | 59.53 / 57.66 ms | 24,602 |

The mean over both trials rises from **38.14 to 44.44 ms** with collisions off, about 16.5%. Chemistry averages 13.54 versus 16.72 ms per tick; transport averages 6.04 versus 6.96 ms. More packets remain and their spatial distributions differ, so this is a comparison of the resulting modes, not an isolation of repulsion arithmetic. The larger continuing workload is consistent with the higher cost. Matching initial seed and material does not imply identical later ecology.

One eight-second live trial per mode also fails the 50k/60 FPS goal:

| Particle collisions | Mean / p95 frame | Simulated / wall seconds | Eight-tick catch-up frames |
| --- | --- | --- | --- |
| On | 46.61 / 160.86 ms | 6.87 / 8.02 s | 16 |
| Off | 101.58 / 292.15 ms | 6.18 / 8.02 s | 27 |

The fixed traces recorded **30,972 packet merges with collisions on versus 26,121 off**. Each merge preserves the modeled material in one larger packet and retires its partner, explaining most of the approximately 5,000-packet count difference. Decay was slightly higher with collisions off (341 versus 299 events); accounted particle material ended at 640.84 off versus 639.32 on, a difference of about 0.24%. “More packets surviving” means more separate simulation packets here, not substantially more material. Repulsion changes encounter trajectories and approach directions, which matter to orientation-gated merging; whether extra encounter mixing explains the rate difference has not been isolated.

Live scheduling amplifies slow frames through catch-up; these short, shrinking fixtures cannot establish sustained particle capacity or a general slowdown ratio. No default density increase or solver promotion accompanies this trial. Keeping the preferred overlap appearance will still require reducing reaction-query and per-packet costs.

## Reproduce

```sh
./tools/test.sh
PRIMORDIA_BACKEND=script ./tools/test.sh
./tools/fluid_compare.sh current --particle-collisions=on --chemicals=50000 --frames=120 --output=/tmp/primordia-collisions-on.json
./tools/fluid_compare.sh current --particle-collisions=off --chemicals=50000 --frames=120 --output=/tmp/primordia-collisions-off.json
python3 tools/fluid_report.py /tmp/primordia-collisions-on.json /tmp/primordia-collisions-off.json
```

Use `--frame-step=live --seconds=8` for the live comparison. Trace/report metadata records the collision setting. Screenshots and raw traces are retained in project-local task evidence, not committed as generated assets.

## Scientific motivation

Independent random walks model diffusion with displacement variance proportional to elapsed time. Diffusion, reaction encounter criteria and pair repulsive potentials can be treated separately in coarse reaction-diffusion models. [references.md](../references.md) links OceanParcels and ReaDDy's primary documentation and describes the game approximation.

Real molecules collide. This overlap mode omits excluded volume and crowding; it is a readable chemical-tracer approximation rather than calibrated dense molecular dynamics.
