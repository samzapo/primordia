# Revision 46 — resident cytoplasm and mobile sound

Visible intracellular particles now use the resident main RenderingDevice, alongside the existing external chemistry backend. The browser remains a WebGL presentation client of that native authority.

## Particle ownership and local chemistry

`ResidentParticles` manages per-cell `ResidentCytoplasm` components. During resident ownership, `CellChemistry.particles` and its CPU bins are empty. GPU storage owns finite quantities, fuel, identities, sources, compartments and poses. Transport, local catalytic reactions, digestion, autocatalysis, ATP conversions and turnover, osmosis, and membrane transfers execute in compute. Anatomy and body physiology remain on the CPU and use compact, exactly-once finite receipts. Totals are derived inventory caches, not an alternative chemical store.

Spatial bins are separated by species. Stable links retain reference bin and insertion order for consumption; local coalescence retains identity order. Hash collisions are checked against actual bin coordinates and distance, never treated as chemical contact. All GPU operations use the existing main device and render thread. Ordinary steps read a 2 KiB receipt, with a bounded additional membrane-transfer receipt. They do not download or upload a whole particle pool. Capacity overflow restores the previous transaction on-device before growth and retry; a hard limit returns the restored inventory without a partial biological receipt. Persistent authority treats an intracellular device failure as an error rather than continuing with incomplete chemistry.

Quantities and fuel use doubles; identity, source and compartment retain their full 64-bit representation. Poses use GPU floats. Sparse non-physical facts stay separate from poses. This is numerical parity with finite accounting, not a claim of cross-platform bit determinism or molecular chemistry.

A visible interoceptive cell is promoted once. Leaving its camera footprint or changing to exteroception releases its current particles once to the existing coarse CPU method. Independent pending time, transport ticks and chemistry clocks survive that transition and checkpoints. Structural removal, division and lysis explicitly take ownership before changing particles. Detached editing previews and checkpoint exports do not replace resident authority.

## Internal resolution and presentation

The additional tenfold parcel scale applies only to intracellular local emissions. Explicit broad starting conditions keep their spatial sampling so a small ATP inventory is not collapsed into one inaccessible spot. Installed catalytic sites remain separate.

Checkpoint resolution version 2 groups up to ten nearby compatible internal parcels, preserving quantities, fuel, pathway sources and compartments. The maximum group diameter is the larger of eight world units and one quarter of the cell radius. Protected sites, sparse groups and spatial bounds can leave more than exactly one tenth of the records. External density is unchanged for a world already converted to version 1. The validated input is retained independently for each resolution version; the saved version prevents repeated conversion on restart. Version 3 additionally coalesces released digestive catalysts within two world units and the normal finite catalyst quantum. These are paid enzyme material from emptied vacuoles, not installed reaction sites. Installed catalysts, active vacuoles and packets with sparse facts remain separate. Upgrading an existing v2 world leaves its ordinary substrates unchanged and retains `before-particle-resolution-v3.pworld`. Both CPU coarse chemistry and GPU detail perform the same local coalescence, preventing renewed accumulation without discarding material or fuel.

Native drawing samples resident textures directly through one instanced batch. Browser drawing uses the same instanced glyph presentation and interpolates successive snapshots by particle identity. The smaller intracellular glyph scale remains. Hidden poses are omitted from network snapshots; read-only inventory summaries retain correct resource and material displays. Checkpoints still contain complete particle state.

The authority disables display VSync and caps its render loop separately at 120 frames per second. Its physical step remains 60 Hz. An idle or occluded desktop display must not set world time. These settings do not guarantee real-time simulation under an overloaded workload.

## Mobile music

Web export has no worker-thread or GDExtension dependency. The ordinary web build generates all 17 sample instruments from `MusicSynth`, writes a content-addressed PCM bank and its manifest, and checks their integrity and non-silence. Generated banks and manifests are build outputs, not committed assets.

The web client uses Web Audio for sample playback, filtering, panning and tempo delay. The existing score still observes anatomy and environment, using the independent audio clock. Active polyphony is bounded at 40. Bank rate and base notes come from the authored synthesizer through the generated manifest. Browser loading verifies the bank checksum. Music resumes through a trusted touch gesture; touch controls provide enable/mute and volume. Mute and reset discard old voices and delay tails. Native music retains its existing mixer.

In a persistent remote view, the musical lead is the focused living cell. Observing a cell after the owned lineage ends does not adopt or revive it, change selected ownership, or mutate physics or RNG. Local terminal-game music retains its prior behavior.

## Verification

Keep gameplay, objectives and balance tests on hold. Retain native and script checks for conservation, finite paid actions, clocks, networking, checkpoint recovery, touch controls and music. `tests/resident_cytoplasm_gpu.gd` checks hardware ownership, local/cofactor limits, catalog recipes against the CPU reference, digestion, pumping, photosynthesis, growth rollback, full-width facts, sparse metadata, membrane transfer, lysis, previews and direct native texture drawing. It must run on real hardware in GPU CD.

The private browser fixture uses trusted loopback HTTPS, a real GPU authority, a touch viewport and software WebGL presentation. It checks loading, snapshots, perception pixels, anchored camera gestures, Follow, pause/resume, saved identity, non-silent Web Audio and touch sound controls. It does not establish physical phone GPU frame rate or speaker audibility. Deployment also checks HTTP delivery of the generated music bank.

Engineering reference: [Godot DisplayServer VSync API](https://docs.godotengine.org/en/latest/classes/class_displayserver.html#class-displayserver-method-window-set-vsync-mode).
