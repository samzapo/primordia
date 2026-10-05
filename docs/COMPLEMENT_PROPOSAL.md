# Complement-inspired mechanics — proposal

These mechanics are suggestions for the next gameplay playtest. Revision six implements directional particle artwork and brighter graphics; it does **not** add a complement cascade.

## Recommended first experiment: mark, assemble, inhibit

| Mechanic | Proposed rule | Why it fits |
| --- | --- | --- |
| Surface tags | Secreted tags bind on correctly oriented contact with a foreign cell or organic debris. Tags stay anchored to the local membrane coordinate. Grazing pores prioritize tagged debris; hunting spikes can recognize tagged prey more clearly while retaining the lower-biomass targeting rule. | Makes chemical recognition visible and lets chemistry support both grazing and hunting. |
| Cooperative membrane pores | A bound tag provides the first docking site. Further aligned subunits build a visible partial ring. After a small tunable number of attachments, the complex damages the local membrane and produces an ordinary biomass leak. | Creates a chemical attack with observable buildup and time to respond, rather than another instant damage packet. |
| Protective inhibitors | An antitoxin-like regulator caps unfinished complexes; repair bodies clear completed damage. Removing a tag or cap returns its retained material to waste. Passive turnover prevents permanent marks. | Provides a defensive build and an escape/recovery opportunity. |

Start with two new free-particle types (tag and pore subunit), a few states on bound complexes, and a complementary regulator interaction using the existing neutralizer. A secretion variant of the toxin vesicle could produce the new offensive chemistry. Exact organ costs, thresholds and the role of existing antitoxin need a playtest decision; these are not settled requirements.

All inputs must be secreted by cells and paid for with retained material/ATP. Assembly transfers that material into the bound complex. No catalyst creates free mass. Every attachment obeys distance, orientation and compatibility rules without an extra reaction-success roll. A decorative branch is not automatically a new binding site.

Retain shared NPC rules, local armor-first damage, current self-immunity as a game concession, and the existing membrane repair/biomass leak path. Show progress with a growing colored arc at the attachment; show inhibition as a contrasting cap, followed by release into waste. Avoid permanent sensing penalties or requiring precise player clicks.

## Later possibility: local amplification

A bound activating complex could convert nearby inactive precursor packets into active tags. That would produce a local cascade dependent on supplied precursors and their aligned encounters. Regulators and precursor depletion would bound it. Add this only if the simpler tag/pore/counter loop is readable and useful; a full catalogue of complement proteins would add complexity without necessarily adding player choices.

## Scientific motivation and limits

C3-derived surface tags can promote recognition and uptake: [C3b-triggered phagocytosis experiments](https://www.nature.com/articles/s41598-022-27279-4). This motivates prioritizing tagged material, not a literal model of our grazing pump or remote spike sensing.

Complement proteins assemble a membrane-damaging complex: [Serna and colleagues, 2016](https://pubmed.ncbi.nlm.nih.gov/26841837/). Real MAC is an asymmetric multi-protein structure. A small ring assembled from a few identical game pieces is an abstraction, and it should not be presented as the actual stoichiometry.

Factor H regulates complement activation and assists C3b inactivation: [Wu and colleagues, 2009](https://www.nature.com/articles/ni.1755). Our generic inhibitor would combine distinct regulatory functions. These immune mechanisms belong to multicellular immune biology; Primordia's autonomous cell-secreted version is fictional.

## Computational approach

Reuse the active particle grid and cached facing vectors. Store each surface complex as one small record with material coordinate, component count, material and state, rather than simulating a jointed protein molecule. Only active cells advance complexes. Bound work should scale with membrane capacity; orientation is a pair of dot products at a local contact. Rendering can use the current species MultiMeshes and cached local cell drawings. Performance still requires a crowded benchmark before enabling the gameplay.
