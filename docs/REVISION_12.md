# Revision 12 — living techno and varied tension networks

Music is a core part of Primordia's design. This revision adds an original procedural progressive-techno score whose instrumentation comes from anatomy, alongside randomized starting cytoskeletons. The owner's musical touchstones are Crypt of the NecroDancer, Dicey Dungeons, Neophyte and Nova Drift. No recordings, melodies or samples from those games are included.

## Starting anatomy

Every newly generated cell receives **0–4 original tension links**, with independent random tensions across the existing 0–1 control range. Links are created sequentially: the first spans membrane points; later endpoints can choose membrane points or positions along links already present. Splitting an earlier link creates a movable junction, retaining its original tension group. Thus four original links may contain more than four solver segments.

A separate generator derives anatomy from the habitat seed and cell identity. It does not consume the chemistry/ecology random stream. Different cells receive different layouts, and the same seed reproduces them; restarting the same seeded life reproduces its anatomy. Offspring inherit the parent's edited network. Blank unseeded membrane primitives remain available for isolated geometry fixtures.

The pressure/area solver, edit-only gestures, free repositioning and shape protections remain. Random starting tension can change trajectories and encounter outcomes; it is a physical change, not only artwork.

## The cell orchestra

The score shares a **128 BPM** clock and an original minor-key chord progression. Its 64-bar form moves through emergence, groove, lift, breakdown, build and return. Kick, hats, clap, bass, a soft pad and a returning melodic hook provide musical continuity. Organs add their own patterns:

| Organelle | Voice |
| --- | --- |
| Flagellum | Offbeat rounded synth pluck |
| Protective cortex | Low brass-like stabs |
| Hunting spike | Syncopated acid bite |
| Repair body | Sustained FM bell |
| Grazing pore | Bubbly mallet phrase |
| Flight receptor | Short metallic signal |
| Photosynthesis | Bright glass arpeggio |
| Toxin vesicle | Low modulated growl |
| Toxin neutralizer | Soft answering chime |
| Acid gland | Resonant-style synthetic chirp |

Repeated organs strengthen their type's contribution with diminishing gain, instead of creating unbounded independent voices. Damaged organs contribute more softly. The loudest six visible/partially entering cells supply spatial layers. Cell proximity controls gain and rhythmic density, while stereo position follows the current viewer, including free-camera movement and invisible wrapping.

Increasing the player's retained organic mass lowers the score's tonal register at bar boundaries, capped at one octave of global transposition. Larger individual cells also use lower instrumental registers and add an ominous bass tone. A large body can begin sounding as its edge enters the screen; it grows louder toward the center. Pitched notes are bounded to useful listening ranges. Percussion stays on the common tempo as tonal pitch changes.

The mix includes gentle melodic ducking beneath the kick, a quiet stereo echo, softened editing music and a conservative output limiter. These mappings are musical design choices rather than literal biological sound.

## Visuals and controls

Escape settings now include **Music volume** and **Particle beat response**, saved independently. Zero music volume fades and stops playback; unmuting begins a fresh phrase. Zero beat response removes the visual effect while leaving music active. Editing preserves a quieter beat while simulation time remains paused.

Nearby particle glyphs breathe slightly in size and brightness on the local beat, with spatial falloff around audible cells. This happens entirely in their drawing shader. Positions, velocities, collision sizes, orientation, reaction rules and simulation timing do not change. The optional F3 overlay adds music update time and buffer underruns.

## Execution and bounds

The authored instrument bank is synthesized once at startup on a background thread, then cached in memory. No generated audio assets are committed or downloaded. The ordinary Linux launcher automatically rebuilds the updated native extension. A bounded native sampler handles interpolation, gain smoothing, stereo placement, ducking, echo and limiting; an independent GDScript sampler remains available.

Notes are placed on an integer audio sample timeline, with a small authored sixteenth-note swing. A 160 ms target buffer decouples audio onset timing from rendered frames. Visual phase uses consumed samples and the audio device's reported output latency. Dense anatomy is limited to six cell layers and 40 simultaneous notes; this is a musical mixing budget, not a limit on organisms or particles. Existing gameplay has no beat-timed actions.

Headless tests and normal visual benchmarks leave playback disabled. Use `--music=on` with `tests/visual_benchmark.gd` for explicit audio-on frame comparisons. `--music-benchmark` enables the running director in a diagnostic scene. Benchmarks can use `--audio-driver Dummy` to exercise the real-time mixer without sending sound to speakers.

Generate an offline 30-second listening fixture using the same score and sampler:

```sh
godot --headless --path . --script tools/music_preview.gd -- --output=/absolute/path/primordia-music.wav
```

The fixture introduces a large bass-producing organism, then increases the player's mass. It is a composed listening example, not a recorded simulation run.

## Further immersion ideas

These remain suggestions beyond the implementation above:

- **Event accents:** feeding adds small rhythmic fills, toxin neutralization creates paired notes, and successful division resolves into a recognizable phrase. Sound can wait for a subdivision; the underlying action must remain immediate.
- **Habitat filtering:** brighter water gradually opens the synth filters; acidic regions introduce a sharper, unstable timbre. Buffering audibly calms it.
- **Lineage themes:** a short inherited motif survives division, with new organelles changing its orchestration. The player can recognize their organism by ear.
- **Threat transitions:** approaching armed giants thin the upper melody before a bass-heavy return. Use brief restraint and contrast rather than increasing tempo continuously.
- **Longer authored sections:** add several original progressions and melodies, selected at phrase boundaries, with deliberate rest passages and rare peaks.
- **Flow-linked space:** quiet stereo delay movement follows local currents; major reef passages change the perceived room around the instruments.

Layering instruments and changing complete phrases are established adaptive-score techniques; see [Audiokinetic's interactive-music documentation](https://www.audiokinetic.com/en/public-library/2024.1.8_8893/?id=creating_interactive_music&source=Help). Primordia currently implements those ideas directly in Godot. Technical and biological motivations are recorded in [references.md](../references.md).

## Validation and measured limits

Godot 4.7.2 on the workstation: **2,193 native assertions** and **1,136 GDScript assertions** passed. Coverage includes 64 anatomy seeds, all five initial link counts, tube-to-tube branching, pressure/triangulation stability, deterministic anatomy, all ten musical signatures, sample-boundary scheduling, finite waveform envelopes, source locality, observation purity, stereo/volume rules, voice limits and native/reference audio agreement. The existing 98 interface checks also pass.

Eight running-audio checks passed on Vulkan Mobile with both native and GDScript samplers, and on Compatibility with the native sampler. They cover startup, consumed-sample time, buffer continuity, paused biology, independent visual controls, mute/unmute and local shader sources. Compatibility used llvmpipe software rendering. All three short runs reported zero underruns. The final pulse capture was visually inspected.

The instrument bank generated in approximately **150–177 ms**, once, off the gameplay thread. Native runtime mixer updates peaked at **0.25–0.30 ms** in the smoke tests. The GDScript runtime test peaked at **27.45 ms**; its CPU cost is materially higher.

### Wide-view music ablation

1440×900 Xvfb, Vulkan Mobile, RTX 5080 / Ryzen 9 9950X, native simulation, 80% play camera, 12 warm-up frames and 36 measured live frames per sample. The dense fixture starts with 4× packets; growth uses 256× unspent biomass. Both music states use the same revision's seeded anatomy. Music-on includes the beat shader. The Dummy audio driver runs the buffer/mixer without physical speakers.

| Fixture | Bloom | Music off median (ms) | Music on median (ms) | Music on p95 (ms) | CPU tick (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| Normal | Off | 26.399 | 24.219 | 27.276 | 3.37 |
| Normal | On | 24.346 | 26.118 | 28.344 | 3.53 |
| Dense | Off | 49.482 | 47.289 | 50.695 | 7.58 |
| Dense | On | 53.232 | 53.418 | 62.279 | 7.23 |
| Growth | Off | 32.862 | 33.106 | 35.286 | 3.14 |
| Growth | On | 32.882 | 32.797 | 33.391 | 3.09 |

All six music-on cases initialized playback and recorded zero underruns; their peak mixer updates were **0.232–0.257 ms**. Short whole-frame comparisons vary in both directions, so they do not establish a fixed total overhead or a rendering speedup. The existing 16.7 ms/60 FPS target remains unmet.

An offline **40-voice stress test**, 60 blocks of 1,024 stereo frames, measured native median/p95 **0.204/0.214 ms**, compared with GDScript **28.794/29.896 ms**. Each block represents about 46.4 ms of audio. Deliberate over-demand dropped 160 new notes while retaining the 40-voice ceiling. These are sampler costs, not game frame times. Run it with `--script tests/music_profile.gd`.

The 30-second listening fixture reached a peak of **0.346**, RMS **−22.40 dBFS**, and 23 simultaneous voices, with no dropped notes. This validates signal headroom, not subjective musical quality. Owner listening feedback and long sessions with the actual audio device remain necessary; the Steam/RTX 3090/Threadripper computer has not been benchmarked. A frame stall longer than available buffered audio can still cause an underrun.
