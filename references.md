# Scientific motivations and game abstractions

This is a living design record. For each new biological or physical mechanic, retain at least one source describing the real phenomenon that motivates it. Prefer original research and authoritative technical documentation. State the game rule separately from the evidence; a citation is not validation of our numerical constants. Controls, presentation and performance shortcuts are explicitly game design choices.

## Acidity, digestive enzymes and buffering

**Phenomenon:** extracellular acid proteases can digest complex organic material most effectively within an acidic pH range. The optimum is enzyme-specific, not a universal rule that acid helps all reactions.

**Source:** [Purification of extracellular acid protease and analysis of fermentation metabolites by Synergistes sp. utilizing proteinaceous solid waste from tanneries](https://pubmed.ncbi.nlm.nih.gov/17601727/) (2007), an experimental study reporting an optimum at pH 5.5–6.5. [An extracellular acid protease from Brevibacillus sp. OA30](https://pmc.ncbi.nlm.nih.gov/articles/PMC6027330/) (2018) provides another measured pH-activity curve.

**Game:** grazing pores release reusable digestive enzymes. An enzyme meeting waste with complementary orientation converts it into edible nutrient material. Moderate acidity improves the modeled enzyme's binding acceptance; extreme acidity prevents this reaction. Acid glands and finite-capacity buffer particles change a transported acid-equivalent field. Repair bodies secrete buffers.

**Abstraction:** the wider accepted contact angle represents favorable enzyme activity; pH does not literally widen a molecular patch. Our normalized acidity is not measured pH, and averaging it is not averaging pH values. Rose/magenta water is a visualization of that field, not a claim that acid or hydrogen ions are naturally pink. Generic waste stands for digestible organic debris. Water, ions and individual chemical bonds are unresolved. Nutrient assembly is not automatically enhanced by acid.

## Acid stress and cellular defense

**Phenomenon:** weak-acid exposure can acidify the cytosol; cells use energy-dependent transport to maintain internal conditions. Growth inhibition is not explained by ATP depletion alone.

**Source:** [Yeast adaptation to weak acids prevents futile energy expenditure](https://pmc.ncbi.nlm.nih.gov/articles/PMC3678083/) (2013), experiments comparing intracellular pH, growth and ATP under acetic/sorbic acid stress.

**Game:** acidic surroundings increase ATP maintenance costs. Sustained excessive exposure accumulates stress, impairs metabolism and eventually reduces health. Clean water permits recovery, and local buffers reduce exposure. The secreting cell shares the risk.

**Abstraction:** one stress variable represents several distinct mechanisms. No calibrated pH, acid species, transporter model or universal toxicity threshold is claimed. Armor does not grant automatic acid immunity.

## Respiration and organic recycling

**Phenomenon:** microorganisms consume organic substrates and oxygen, partitioning carbon between growth and respiration.

**Source:** [Oxidation state of bioavailable dissolved organic matter influences bacterioplankton respiration and growth efficiency](https://www.nature.com/articles/s42003-025-07574-2) (2025), experiments measuring organic carbon, dissolved inorganic carbon and oxygen changes during microbial processing.

**Game:** cells process food with oxygen; waste/oxygen encounters recover nutrient material and dissolved carbon. Photosynthetic cells can reuse carbon.

**Abstraction:** extracellular waste-to-food conversion condenses unrepresented microbial processing into a contact rule. Oxygen alone does not turn waste into food in real water. Our carbon resource and organic ledger combine chemical pools that real biogeochemistry distinguishes; they are not an atom-balanced reaction equation. The cited work motivates recycling and its oxygen cost, not the game's yield ratios.

## Orientation-dependent binding and particle assembly

**Phenomenon/model:** directional interaction sites produce orientation-dependent association. Patchy-particle simulations use orientation relative to the line joining neighbors.

**Sources:** [HOOMD-blue Patchy documentation](https://hoomd-blue.readthedocs.io/en/v5.2.0/hoomd/md/pair/aniso/patchy.html); [ReaDDy reaction and potential model](https://readdy.github.io/system.html) for the contrast with stochastic reaction-diffusion kinetics.

**Biological aggregation example:** [Marine bacteria Alteromonas spp. require UDP-glucose-4-epimerase for aggregation and production of sticky exopolymer](https://pmc.ncbi.nlm.nih.gov/articles/PMC11325263/) (2024) experimentally links cellular exopolymer production to aggregation. This motivates clustering existing organic material, not synthesizing new food mass.

**Game:** reactive faces must touch and point toward one another. Compatible contact reactions have no extra success roll. Thermal translation/rotation and probabilistic decay make encounters variable. Aligned nutrient packets aggregate into a larger packet containing their combined edible material.

**Abstraction:** packets represent coarse amounts, not single molecules. Nutrient assembly is physical packet aggregation, not spontaneous protein or sugar synthesis. Orientation alone does not capture activation barriers, conformation, solvent effects or quantum chemistry. Decay uses continuous hazards rather than fixed expiration times. Bright tips on asymmetric vector glyphs show orientation, not actual molecular structure.

## Toxins and neutralization

**Phenomenon:** specific binding can sequester a toxin and suppress its activity.

**Source:** [Identification, functional characterization, assembly and structure of ToxIN type III toxin–antitoxin complex from E. coli](https://pmc.ncbi.nlm.nih.gov/articles/PMC8860590/) (2022), including direct structural/binding evidence for a toxin–antitoxin complex.

**Game:** toxin vesicles emit damaging packets; neutralizer organs emit complementary binding particles. Correctly oriented contact makes harmless waste carrying both reactants' organic material.

**Abstraction:** this cited intracellular RNA/protein system motivates sequestration, not our fictional extracellular organelle. The conversion to generic waste and contact damage are game simplifications. The neutralizer does not stand for an actual universal antitoxin.

## Receptor competition and recovery

**Phenomenon:** occupancy and desensitization can reduce receptor responsiveness; dissociation, internalization and recycling can restore signaling.

**Source:** [Recycling and Resensitization of Delta Opioid Receptors](https://pmc.ncbi.nlm.nih.gov/articles/PMC3856725/), experimental evidence that recycled receptors can respond again after agonist removal; [Src promotes delta opioid receptor desensitization by interfering with receptor recycling](https://pmc.ncbi.nlm.nih.gov/articles/PMC3823043/) (2008).

**Game:** aligned foreign decoys occupy chemical receptors and reduce sensing range. ATP-funded automatic clearance and repair bodies accelerate recovery; passive release remains possible at zero ATP. Purple rings show occupancy, and resource packets show cleaning costs. Toxin vesicles co-release decoys.

**Abstraction:** these mammalian signaling studies motivate reversible responsiveness; the cell's chemical receptors are fictional composites. Passive dissociation, energy-dependent turnover and decoy disposal are condensed into one occupancy variable. Photosynthetic light sensing is not blocked by chemical decoys.

## Photosynthesis and phototaxis

**Phenomena:** oxygenic photosynthesis releases oxygen derived from water, and some flagellated algae orient their swimming in response to light.

**Sources:** [Heavy Oxygen (O18) as a Tracer in the Study of Photosynthesis](https://pubs.acs.org/doi/10.1021/ja01848a512) (Ruben and colleagues, 1941); [Eyespot-dependent determination of the phototactic sign in Chlamydomonas reinhardtii](https://pmc.ncbi.nlm.nih.gov/articles/PMC4868408/) (2016).

**Game:** the photosynthetic organ follows brighter habitat patches and uses light plus stored dissolved carbon to support ATP, biomass and food, releasing oxygen. Grazers in the ecosystem provide cell-derived particles.

**Abstraction:** light is energy, not oxygen mass. Water is an implicit reservoir; carbon fixation, photosynthetic electron transport and oxygen evolution are bundled into one event. Combining light sensing, propulsion and photosynthesis in one buildable organ is a convenience. Real phototaxis can have either sign, not simply “always seek more light.”

## Chemical sensing and indirect motion

**Phenomenon:** microorganisms alter swimming in response to chemical conditions.

**Source:** [High-throughput 3D tracking of bacteria on a standard phase contrast microscope](https://www.nature.com/articles/ncomms9776) (2015), experimental measurements of bacterial swimming and run/tumble trajectories.

**Game:** pores, spikes and flight receptors send internal signals that guide motion. Anatomy, rather than direct player steering, determines behavior.

**Abstraction:** sampling a gradient, orienting a particular organ toward a target, long-range traces and choosing lower total biomass prey are readable game rules, not a reproduction of bacterial chemotaxis circuitry.

## Fluid coupling and feeding currents

**Phenomenon:** viscous forces strongly influence microswimming, and appendage motion acts on surrounding fluid.

**Source:** [Life at low Reynolds number](https://www.math.uwaterloo.ca/~mdunphy/purcell.pdf) (Purcell, 1977; doi:10.1119/1.10903).

**Feeding-current source:** [Filter-feeding, near-field flows, and the morphologies of colonial choanoflagellates](https://arxiv.org/abs/1607.02892) (2016), a hydrodynamic study of flow-assisted feeding. Our inward pore pump is a simplified stand-in for appendage-driven feeding currents.

**Game:** flagella, pursuit organs and feeding pumps exchange momentum with a finite-mass fluid grid. Nutrients and other cells respond to the resulting currents.

**Abstraction:** we intentionally retain appreciable inertia and eddies for gameplay. This is not a strict zero-inertia Stokes-flow or incompressible-fluid solver. Direct particle/body shunting is a visual collision concession, not a conservation law.

## Membrane shape, growth and cytoskeleton

**Phenomenon:** osmotic pressure and cytoskeletal forces together influence cell volume and shape.

**Sources:** [Hydrostatic pressure and the actomyosin cortex drive mitotic cell rounding](https://www.nature.com/articles/nature09642) (Stewart and colleagues, 2011); [Microtubules can bear enhanced compressive loads in living cells because of lateral reinforcement](https://pmc.ncbi.nlm.nih.gov/articles/PMC2063890/) (2006).

**Game:** biomass changes projected volume and membrane capacity. Enclosed-area pressure opposes a player-authored tension network; the membrane can deform while preserving an ordered outline.

**Abstraction:** the tool is called “microtubules,” but its tension-only links are closer to a generic contractile cytoskeletal network. Real microtubules also bear compression and bend; we do not simulate that material behavior. A 2D star-shaped membrane, uncapped growth and freely edited internal points are design choices. No cell division is implemented.

## Spike contact and predation

**Phenomenon:** some bacteria use a sharp protein assembly to deliver harmful effectors into neighboring cells.

**Source:** [PAAR-repeat proteins sharpen and diversify the type VI secretion system spike](https://www.nature.com/articles/nature12453) (Shneider and colleagues, 2013), structural and functional evidence for spike-mediated delivery/killing.

**Game:** a protruding spike punctures local protection/membrane on contact and guides pursuit of lower-biomass targets. Dead cells release retained material for grazers.

**Abstraction:** our permanently protruding, self-propelling spike is not a model of the contraction-driven T6SS. Sensing, pursuit, physical impact damage and secretion are deliberately combined for playability.

## Repair, energy and presentation

[Plasma membrane repair is mediated by Ca(2+)-regulated exocytosis of lysosomes](https://pubmed.ncbi.nlm.nih.gov/11511344/) (Reddy, Caler and Andrews, 2001) provides experimental motivation for active membrane resealing. Our repair consumes biomass and ATP, with internal resource animations illustrating those debits. Calcium, trafficking and exocytosis are not resolved; the repair organ, its buffer secretion and cleanup bonus combine distinct functions for gameplay. Protective cortex tiles, instantaneous anatomical editing, HUD resource bars, camera locking, toroidal space, dormant offscreen ecology and particle shunting are explicitly game/implementation choices. Do not invent biological support for them.

## Complement: recognition, assembly and regulation (proposals)

**Phenomena:** complement-derived fragments on a surface can promote receptor-mediated uptake; terminal complement proteins assemble membrane pores; regulatory proteins limit activation and protect host tissue.

**Sources:** [Purified C3b phagocytosis experiments](https://www.nature.com/articles/s41598-022-27279-4); [MAC cryo-EM structure](https://pubmed.ncbi.nlm.nih.gov/26841837/) (Serna and colleagues, 2016); [Factor H–C3b structure](https://www.nature.com/articles/ni.1755) (Wu and colleagues, 2009).

**Proposed game use:** surface tagging, orientation-dependent pore assembly and a protective inhibitor. See [the complement proposal](docs/COMPLEMENT_PROPOSAL.md). These mechanics are **not yet implemented**.

**Abstraction:** a small local assembly/counter loop would condense a multicellular immune system into fictional cell-secreted chemistry. A few game pieces would not reproduce MAC stoichiometry, and a generic neutralizer would combine several regulatory actions. Recognition bonuses and lower-biomass spike targeting are gameplay rules.

**Artwork:** the owner's reference images motivate a bright, rounded vector vocabulary of forks, combs, hooks and linked lobes. Primordia's authored glyphs are original symbolic species markers, not traced illustrations or literal protein structures. Their forward axis matches the existing chemistry orientation. Decorative branches do not add reaction sites; the contact model remains circular.

## Light bloom as presentation

The screen bloom is a stylistic optical halo in light-rich regions. It does not add light energy, photosynthesis or chemical activity. The world pass uses a bounded neighborhood of [Godot screen-texture samples](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html); the HUD is drawn afterward and stays sharp. This is an inexpensive screen-space approximation, not a simulation of microscope optics or spectral scattering.

## Computational implementation of the existing simulation

Revision seven preserves the biological/physical abstractions above. [Godot C++ bindings](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/about_godot_cpp.html) provide native batch execution. [Godot compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html) document RenderingDevice renderer requirements and the synchronization cost relevant to our GPU transport experiment. [GPU Gems: grid fluid simulation](https://developer.nvidia.com/gpugems/gpugems/part-vi-beyond-triangles/chapter-38-fast-fluid-dynamics-simulation-gpu) motivates retaining a field-based fluid representation; Primordia still uses its simpler finite-mass viscous model and does not claim to implement that chapter's pressure projection.

## Recursive branching and plant-like obstacles

**Phenomenon and visual motivation:** repeated branching and self-similar botanical forms can be represented by compact recursive growth rules. [Prusinkiewicz, Graphical applications of L-systems (1986)](https://algorithmicbotany.org/papers/graphical.gi86.html) presents turtle-based rewriting systems that produce both fractal curves and plant-like structures.

**Game implementation:** a bounded recursive branch grammar is repeated around five, six or seven arms to generate original radial colonies. It is inspired by this botanical modeling work; it is not a full L-system interpreter. Shape, layout and color are seeded. Cached artwork preserves fine detail without simulating a leaf as a body. Main stems obstruct and redirect cells and drifting packets, creating passages in the habitat.

**Abstraction:** exact snowflake-like rotational symmetry, static anchored colonies, rigid capsule contact and indestructibility are artistic/gameplay choices, not claims about real microscopic plants or snowflake biology. The finest fronds are permeable decoration. These scenery objects neither photosynthesize nor create particles, preserving the cell-only material sources. Multiscale periodic water color is fractal-style presentation, not a model of light scattering, acidity or additional chemistry; the existing light and acidity fields retain those gameplay roles.

## Peripheral optical defocus

The soft edge blur is a presentation choice, not a new biological or chemical mechanic. [Godot screen-reading shader documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) describes filtered screen-texture mip levels and the shared back-buffer behavior used here. Primordia blends toward a blurred level only in the outer view, keeps level zero in the center and draws HUD controls afterward. It is a stylized microscope focus effect, not a calibrated optical model.

## Proposed adaptation economy and victory conditions

These ideas are **not implemented**. The [action economy proposal](docs/ACTION_ECONOMY_PROPOSAL.md#scientific-grounding) records primary sources for cellular resource-allocation costs, antagonistic coevolution, costly resistance and microbial dormancy, with explicit differences between the experimental phenomena and the proposed game rules. Adaptation points, draft offers, short ecological phases and victory thresholds are game abstractions.
