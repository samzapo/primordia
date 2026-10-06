# Revision 14 — inherited melodies and responsive habitat music

The approved music follow-up adds all three features: a family melody that survives division, light/acidity timbre, and musical accents for feeding, toxin neutralization and division. The original 128 BPM arrangement, anatomy rhythms, proximity/panning, biomass register, volume controls and visual beat response remain.

## A recognizable lineage

Each family receives a seeded six-note contour. Parent and offspring use the same lineage signature, so division retains the melody even when the controlled cell ID changes. A private generator leaves the ecology random stream untouched.

Installed organ types take turns carrying that melody in two-bar phrases. Adding or removing anatomy changes its instrumentation, while the notes retain their family identity. The visible player is the foreground voice; a free camera away from the player can hear the strongest local organism instead. One foreground melody avoids six competing leads. Breakdowns and editing leave a sparse version; the finale/death state falls back to the existing quieter bed.

## Hear the water

Each audible organism samples light and acidity at its own location. The global accompaniment samples the camera's water. Light opens a smoothed low-pass filter on melodic instruments from 400 to 6,500 Hz. Acid adds gentle saturation and a small 6.4 Hz amplitude ripple. Existing buffer chemistry lowers the sampled field and therefore calms the timbre naturally.

The mixer applies one tonal filter per source, rather than one per note. Kick, hats, clap and the foundation bass remain clear. Stereo gain, filter and acidity transitions are smoothed; the existing limiter retains output headroom. These are musical metaphors, not new chemistry or physical sound propagation.

## Actions answer the score

| Action | Musical response |
| --- | --- |
| Nutrient ingestion through a grazing pore | Two-note mallet fill on the next sixteenth |
| Oriented antitoxin–toxin neutralization | Two answering chimes on the next eighth |
| Successful funded division | Four-note resolving bell phrase on the next beat |

The simulation records completed actions in a bounded presentation journal. Music observes it without removing gameplay events, consuming ecology randomness or feeding information back into cell sensing. The physiology happens immediately. Only the sound waits for its musical subdivision, plus the existing audio buffering and observation interval.

Local visibility and proximity determine which events are heard. Offscreen or older-than-one-second records are skipped. Repeated reactions coalesce, with short per-kind/channel cooldowns; division has priority over neutralization and feeding. Editing, terminal states, mute, unmute and restart clear pending accents. Startup and unmute prepare the first audio buffer before playback begins, preventing a slow reference render from opening an empty stream. Reassigning an audio channel cancels its old organism's remaining phrase.

Bounds: 64 journal entries/coalescing keys, 12 pending cues, at most three new phrases per scheduling pass, 24 queued accent notes, six cell layers plus accompaniment, and 40 simultaneous sampler voices. The native chemistry result reports at most 32 presentation samples per call while executing every chemical reaction. Dense bursts may omit accents; they never omit reactions or create an audio backlog.

## Generate a listening example

The authored fixture uses the same score and mixer:

```sh
./tools/run.sh --headless --script tools/music_preview.gd -- --output=/absolute/path/primordia-music.wav
```

It renders 48 seconds. Dark water brightens around 4–12 seconds; a large organism enters, acidity rises around 16–23 seconds, buffering calms it around 27–34 seconds, and division at 36 seconds retains the family's contour with an added cortex voice. Feeding and neutralization accents punctuate the example. It is composed review material, not a recorded simulation or a promise that every playthrough follows this timeline. Generated audio is not committed.

Use the usual Linux launcher after pulling so it rebuilds the native mixer. Direct editor launches with an older library require that rebuild to hear the new native filtering; missing new reaction-presentation fields are tolerated.

## Validation

Godot 4.7.2: **2,256 native assertions** and **1,197 reference assertions** passed, with no script/runtime errors. New coverage exercises actual feeding, oriented neutralization and funded division; inherited melodies and anatomy orchestration; the visible player's melody among larger neighbors; buffer-driven timbre; event locality, age, coalescing and memory bounds; audio-block-independent scheduling; restart/history rejection; filter spectral response, headroom and native/reference agreement.

Thirteen running-audio checks passed on Vulkan Mobile with both mixers and on Compatibility with the native mixer. Four additional reference mute/unmute cycles also passed. These checks reported **zero underruns**; final native peak updates were **0.321–0.345 ms**, with **41.576 ms** in the reference cycle test. Compatibility used llvmpipe software rendering. An initial reference unmute gap led to the buffer-priming fix; all final playback checks passed afterward.

The 48-second fixture produced peak amplitude **0.367**, RMS **−22.36 dBFS**, at most **25 voices** and **zero dropped notes**. Numerical signal checks establish headroom and scheduling, not subjective listening quality.

### Widest-play-view comparison

Godot 4.7.2, Ryzen 9 9950X / RTX 5080, Vulkan Mobile, 1440×900 Xvfb, Dummy audio driver, **80% play zoom**, 12 warm-up and 36 measured live frames per case. Dense starts at 4× packets; growth at 256× unspent biomass. Before is revision 13 with music on. After on/off uses revision 14.

| Fixture | Bloom | Before on median ms | After off median ms | After on median ms | After on p95 ms | After on tick ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Normal | Off | 26.425 | 26.340 | 26.778 | 28.920 | 3.796 |
| Normal | On | 26.467 | 23.495 | 26.954 | 27.734 | 3.589 |
| Dense | Off | 47.458 | 48.323 | 49.735 | 58.307 | 7.867 |
| Dense | On | 55.016 | 53.550 | 54.900 | 64.621 | 7.406 |
| Growth | Off | 33.182 | 32.913 | 33.454 | 34.086 | 3.265 |
| Growth | On | 33.154 | 32.992 | 33.431 | 34.173 | 3.210 |

All six after/music-on cases initialized playback and recorded **zero underruns**, with peak mixer updates **0.281–0.310 ms**, versus **0.232–0.257 ms** before. Short frame measurements vary; they do not establish a fixed total overhead or a rendering speedup. The wider-view performance problem remains: these fixtures still miss the 16.7 ms/60 FPS target, especially dense chemistry.

A 60-block, 1,024-frame **40-voice stress test with maximum acidity** measured native median/p95 **0.254/0.258 ms**, and GDScript **29.173/31.481 ms**. Each block represents 46.4 ms of audio. Both retained the voice ceiling and deliberately dropped 160 over-budget note requests. The reference backend remains substantially more expensive.

Physical speakers, long sessions and the owner's Steam/RTX 3090/Threadripper machine were not tested here. A host stall longer than available buffered audio can still interrupt playback. Scientific motivations and presentation abstractions remain in [references.md](../references.md).
