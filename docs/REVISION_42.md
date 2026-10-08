# Revision 42 — Paramecium anatomy and music from the cell

The oral groove is permanent membrane anatomy in every generated organism and
inherited successor. It is an inward physical dent with ciliated lips; its
position, normals, feeding requests and collision boundary share the deformed
membrane. It cannot be bought, recycled, resized or specialized, and it does not
provide free armor. The legacy feeding identifier remains in the shared
anatomical structure list so native feeding, GPU receipts and coarse ecology all
use the same site. Old feeding blueprints are excluded from new drafts and
installation. Cilia and flagella remain separate purchases; neither is free at
the start.

Oral pumping targets 64 rather than 24 world units/s of relative inflow, over
170 rather than 110 units. This is a target local flow, not a guaranteed particle
speed. Pump response includes both cell and fluid inertia and returns equal and
opposite impulses. All pumps, including cilia, operate relative to the moving,
rotating body. Ciliary steering and membrane traction use the same angular sign
convention in script and native code. There is no hidden velocity clamp.
The cytoproct marks the actual shared waste/carbon outlet on the membrane.

## Resources inside the cell

Retained body, usable biomass and brood tissue determine enclosed area linearly.
Radius therefore grows with the square root of that represented volume.
Construction removes the corresponding cytoplasmic area and transfers tissue
into the organ. The build-cost blob uses the same area-per-unit calibration;
very large comparisons scale both stock and cost together to fit.

ATP has no storage ceiling. All production enters the reserve. A separate
concentration scale controls turnover: dE/dt = -0.002 E² / reference.
Exact positive integration keeps this loss consistent across fine/coarse
intervals. Recent expenditure includes turnover. At reference concentration,
the loss is 0.2 ATP/s for a baseline cell. ATP artwork is a filled elastic sac
whose whole size changes; its growth is visually compressed at high
concentration, without a tank outline or fill level.

Each available AP is one floating gold vacuole inside the cell. Food and waste
are bounded representative parcels whose amounts sum to the actual internal
stocks. They circulate, separate and stay within the membrane/nucleus boundary
while build mode pauses the habitat. Opening the editor neither manufactures
resources nor advances metabolism, damage, external particles or expedition
time. This first internal ecology implements transport and stock visualization;
independent intracellular reaction chemistry and osmotic physiology are not
implemented. The contractile vacuoles and micronucleus are anatomical landmarks.

## Quieter interaction and sound

Factories show at most four actions and a next-page node. The oral groove
exposes only its steering balance. Ordinary labels are short; holding Alt
reveals the detailed explanation. Cost/upkeep comparisons appear during
inspection or construction rather than permanently occupying the build view.
AP stock has moved out of the corner and into the cell.

The nucleus provides the main beat. All other notes come from an equipped
organelle or an actual food vacuole. The anonymous bass, hats, claps, pads and
habitat-event backing phrases have been removed. The inherited motif and
progressive arrangement are played through current anatomy. Neighbors use
substantially lower gain, a softer filter and sparser phrases. Larger bodies
still lower their organ registers.

Every note carries its cell and anatomical source identity. Bounded wave cues
follow the audio generator's played sample position, accounting for queued
audio and output latency. Wave hue encodes pitch class. Muting clears the
visual cues. Chemical particles do not pulse with the beat.

## Validation

- Native suite: 70,483 assertions; script fallback: 3,545 assertions; no failures.
  The final inherent-anatomy shedding guard also passed 80 focused native checks.
- GPU gameplay, streaming, perception, exposure and exchange: 15,171 checks.
  The rendered anatomy/audio test passed 512 checks, including external pause, moving
  interior parcels, actual buffered audio onsets, bounded cues and mute.
- Four ciliary bands in water initially moving at (180, -90) stayed finite at
  1/60, 1/8 and 1/2 second steps. Their peak change from initial current was
  30.57, 31.14 and 80.74 units/s, respectively; the latter covered 300 simulated
  seconds. These isolate paid pump/steering coupling, not a whole-world soak.
  Tests also check equal/opposite linear and angular momentum, frame-velocity
  invariance, ATP exhaustion and damaged cilia.
- Full native/script ecosystems ran 90 simulated seconds. The larger seeded
  hunter still kills and eats via pheromone pursuit within 60 seconds. Geometry,
  conservation, shared metabolism, offspring and editor tests pass.

Rendered profiles used Godot 4.7.2, Vulkan Mobile, a real RTX 5080 / Ryzen 9950X,
a 1440×900 headless Wayland compositor, 80% zoom and a 60 FPS cap. Each measured
window was 12 seconds after warmup. Audio used the real generator with a dummy
output device. These are short workstation regressions, not hardware listening,
long thermal tests or measurements on the owner's 2990WX / RTX 3090.

| Fixture | Mean FPS | P95 frame ms | Simulation ms/frame | Sim/wall |
| --- | ---: | ---: | ---: | ---: |
| CPU normal, music on | 59.99 | 19.03 | 3.52 | 1.000 |
| CPU normal, music off | 60.00 | 18.96 | 3.55 | 1.000 |
| CPU with paid cilia | 59.99 | 19.09 | 3.57 | 1.000 |
| CPU dense particles | 59.98 | 20.21 | 4.76 | 1.000 |
| CPU large cell | 59.99 | 19.01 | 4.19 | 1.000 |
| Resident normal | 60.00 | 18.70 | 5.58 | 0.999 |
| Resident, 50k initial habitat packets | 58.21 | 32.66 | 11.63 | 0.995 |

All measured windows had zero additional audio underruns. Music preparation
averaged 0.036–0.047 ms/frame when enabled. The dense CPU scene ended with
10,745 total / 2,339 detailed packets. The resident 50k-initial scene ended with
14,061 nearby GPU packets (including the halo) and 27,561 CPU stored slots.
This is not 50k visible particles; stored slots can await expiry reclamation.
Normal profiles had six detailed cells of sixteen total. The dense GPU result
still has slow-frame spikes and does not establish sustained 50k performance.

The CPU launcher remains the default. Test the new anatomy and sound with
./tools/playtest.sh cpu, then compare ./tools/playtest.sh resident as desired.

