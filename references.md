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

**Game:** cells process food efficiently with oxygen, with lower-yield fermentation when oxygen is insufficient (documented below); waste/oxygen encounters recover nutrient material and dissolved carbon. Photosynthetic cells can reuse carbon.

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

**Game:** pores, hunting/flight receptors and light-sensitive organs send internal signals that guide motion. Anatomy, rather than direct player steering, determines behavior.

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

**Abstraction:** the tool is called “microtubules,” but its tension-only links are closer to a generic contractile cytoskeletal network. Real microtubules also bear compression and bend; we do not simulate that material behavior. A 2D star-shaped membrane, uncapped growth and freely edited internal points are design choices. Reserve-funded division is now implemented as a separate game abstraction in revision nine.

## Spike contact and predation

**Phenomenon:** some bacteria use a sharp protein assembly to deliver harmful effectors into neighboring cells.

**Source:** [PAAR-repeat proteins sharpen and diversify the type VI secretion system spike](https://www.nature.com/articles/nature12453) (Shneider and colleagues, 2013), structural and functional evidence for spike-mediated delivery/killing.

**Game:** a protruding spike punctures local protection/membrane on contact. Separate hunting chemoreceptors guide pursuit from emitted pheromone reports. Dead cells release retained material for grazers.

**Abstraction:** our permanently protruding weapon is not a model of the contraction-driven T6SS. Macroscopic collision-dependent puncture, its bounded damage curve and ATP-funded sustained injury are game abstractions. The spike has no sensing or self-propulsion.

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

**Game implementation:** bounded recursive branch rules produce original radial colonies, paired fern pinnae with smaller leaflets, branching fans and spiral rosettes. It is inspired by this botanical modeling work; it is not a full L-system interpreter. Shape, layout and color are seeded. Cached artwork preserves fine detail without simulating a leaf as a body. Main stems obstruct and redirect cells and drifting packets, creating passages in the habitat.

[Prusinkiewicz and Lindenmayer, The Algorithmic Beauty of Plants](https://algorithmicbotany.org/papers/abop/abop.pdf) develops recursive branching and self-similarity in compound leaves, including fern forms. This motivates the fern and fan silhouettes added in revision fifteen; the curled radial rosettes are a stylized arrangement, not a claimed model of phyllotaxis.

**Abstraction:** exact snowflake-like rotational symmetry, static anchored colonies, rigid capsule contact and indestructibility are artistic/gameplay choices, not claims about real microscopic plants or snowflake biology. The finest fronds are permeable decoration. These scenery objects neither photosynthesize nor create particles, preserving the cell-only material sources. Multiscale periodic water color is fractal-style presentation, not a model of light scattering, acidity or additional chemistry; the existing light and acidity fields retain those gameplay roles.

## Peripheral optical defocus

The soft edge blur is a presentation choice, not a new biological or chemical mechanic. [Godot screen-reading shader documentation](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) describes filtered screen-texture mip levels and the shared back-buffer behavior used here. Primordia blends toward a blurred level only in the outer view, keeps level zero in the center and draws HUD controls afterward. It is a stylized microscope focus effect, not a calibrated optical model.

## Adaptation economy and lineage (revision 9)

**Resource allocation:** [Scott et al., Interdependence of cell growth and gene expression (2010)](https://pubmed.ncbi.nlm.nih.gov/21097934/) motivates competition for limited cellular resources. The game charges real tissue and ATP for anatomy, repair and secretions. Mutation traits trade throughput against energy, mass or environmental sensitivity. The numerical prices and adaptation-point allowance are design choices, not measured biochemical constants.

**Costly resistance:** [Buckling and Rainey, Antagonistic coevolution between a bacterium and a bacteriophage (2002)](https://pmc.ncbi.nlm.nih.gov/articles/PMC1690980/) and [Antagonistic coevolution with parasites increases the cost of host deleterious mutations (2006)](https://pmc.ncbi.nlm.nih.gov/articles/PMC1560003/) motivate reciprocal adaptation and resource tradeoffs. The game uses a coarse exposure counter, a warning and a limited fraction of paid resistant newcomers. It does not simulate genetic inheritance across the entire population, claim all resistance is costly, or make individual cells evolve deliberately.

**Nutrient-dependent growth and division:** [Control of cell division in Paramecium tetraurelia: effects of abrupt changes in nutrient level on accumulation of macronuclear DNA and cell mass](https://pubmed.ncbi.nlm.nih.gov/3758201/) links nutritional conditions with growth and the division cycle. Primordia requires accumulated reproductive material and energy, then partitions existing parental body tissue and transfers the remainder from reserves to an independently living offspring. [Molecular Biology of the Cell: Cytokinesis](https://www.ncbi.nlm.nih.gov/books/NBK26831/) provides authoritative background for physical partition of a parent into daughter cells; our reserved-material budget and minimum parental body are gameplay rules. The 12-minute division schedule, ATP budget and optional oxygen transfer, blueprint inheritance and 60-second viability threshold are gameplay abstractions; DNA replication and chromosome segregation are not modeled.

The [original proposal](docs/ACTION_ECONOMY_PROPOSAL.md#scientific-grounding) retains further context. Dominance, microbial dormancy and refuge victory modes remain proposals. Current implemented rules are listed in [Revision 9](docs/REVISION_9.md).



## Emergency reserve metabolism

[Sekar et al., Bacterial Glycogen Provides Short-Term Benefits in Changing Environments (2020)](https://journals.asm.org/doi/10.1128/AEM.00049-20) experimentally links intracellular glycogen mobilization to metabolic activity and adaptation during short nutrient gaps. This motivates Primordia's limited transfer of spare biomass into its metabolic pathways when ATP is low.

The game treats generic unspent biomass as containing usable stores; it does not distinguish glycogen, fat and structural proteins. Its ATP threshold, protected eight-unit repair reserve, mobilization rate and respiration yields are design abstractions. The study does not establish indefinite starvation survival, and this mechanism still requires material. Available oxygen determines whether respiration or the lower-yield fallback processes it. Offspring reserves must be deliberately withdrawn before emergency metabolism can use them.


## Inherited self-recognition

[Hirose et al., TgrB1/TgrC1 ligand–receptor allorecognition (2017)](https://pmc.ncbi.nlm.nih.gov/articles/PMC5769593/) demonstrates molecular recognition associated with cooperative aggregation in social amoebae. Primordia uses an inherited self-signature so a parent and offspring do not automatically hunt/flee one another or attack their own lineage with spikes, toxins or decoys.

This is a gameplay extension of the earlier self-toxin exclusion, not a claim that those proteins provide toxin immunity or control weapons. The study motivates recognition only. Unrelated cells and environmental stress still use the ordinary damage rules; physical contact and fluid coupling remain unchanged.

## Demand-triggered secretion and lysis

The [resource-allocation experiments of Scott et al. (2010)](https://pubmed.ncbi.nlm.nih.gov/21097934/) motivate making secretion consume limited cellular resources. The game avoids unproductive spending by requiring nearby waste for enzyme output, foreign toxin for antitoxin, and local acidity or internal acid stress for buffering. These particular sensing thresholds and immediate responses are a maintenance policy for gameplay, not experimentally established regulation for these fictional organs. Orientation-based reaction rules are unchanged.

[Turnbull et al., Explosive cell lysis as a mechanism for the biogenesis of bacterial membrane vesicles and biofilms (2016)](https://www.nature.com/articles/ncomms11220) demonstrates release of cellular contents through lysis. Primordia releases retained organic material and its modeled dissolved oxygen pool once on death. The paper motivates content release, not oxygen storage or a measured oxygen yield; the game's oxygen packets transfer an existing abstract resource and add none.

## Oxygen limitation and fermentation

[Deciphering the physiological response of Escherichia coli under high ATP demand (2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8686765/) experimentally examines ATP demand, biomass yields and fermentation-product output under aerobic and anaerobic conditions. [Engineering new-to-nature biochemical conversions by combining fermentative metabolism with respiratory modules (2024)](https://www.nature.com/articles/s41467-024-51029-x) further motivates the lower growth yield and metabolite output of fermentative metabolism.

Primordia's shared food-processing pathway uses available oxygen first. Remaining throughput can ferment food for 2 ATP, 0.3 biomass, 0.3 waste and 0.1 carbon per coarse unit; 0.3 leaves the represented pool as unrecoverable end products. The latter is recorded in the existing material-loss ledger and makes recycling unable to supply energy indefinitely from a closed material loop. It is a deliberately coarse accounting sink, not literal destruction of atoms. Respiration instead yields 5 ATP and 0.7 biomass with its existing carbon/waste outputs.

These are gameplay yields, not ATP-per-glucose measurements, universal microbial capabilities or redox-balanced chemical equations. We do not resolve glycolysis, NADH regeneration, ethanol, lactate or acetate. Fermentation does not create oxygen, adds no organ/species, and gives oxygen-poor diets a less efficient fallback.

## Revision 10 presentation

The finite branching and optical presentation references above also motivate this visual revision. Broader stems use matching drawn and collision radii; rounded terminal bracts remain decorative. Loose reef grouping is a level-layout choice.

Seeded colors, stylized nucleus lobes, vesicle patterns, bounded nuclear lag and organ swelling are visual representations, not additional biological processes or measured intracellular mechanics. Color identifies organ/particle function but never cell occupation. The existing membrane, secretion, feeding and lineage systems provide the states being illustrated. Highlight-selective bloom adds no light resource; orientation glyphs add no reaction sites.

## Microscope scale and proposed cellular controls

[Alberts et al., Molecular Biology of the Cell: Looking at the Structure of Cells in the Microscope (2002)](https://www.ncbi.nlm.nih.gov/books/NBK26880/) describes typical animal-cell diameters around 10–20 μm. Primordia adopts **0.2 μm per world unit**, putting its ordinary starting cell near 20 μm across. This is a fixed artistic spatial calibration, not a species identification or a recalibration of physical rate constants. The side scale measures actual displayed world distance, including viewport fitting, zoom and growth-related camera adjustments. Its label uses 1/2/5 steps; text scaling never changes the distance represented.

Particle glyphs remain coarse chemical packets, not literal molecular dimensions. Unbounded gameplay growth can exceed the typical range motivating the initial scale.

[Alberts et al., The Endoplasmic Reticulum (2002)](https://www.ncbi.nlm.nih.gov/books/NBK26841/?report=printable) describes synthesis and insertion of membrane proteins, including proteins destined for the plasma membrane. This motivates the implemented intracellular factory controls. The game does not model real organelle biogenesis or claim that all organelles are assembled by the ER. The ATP sac and AP coins are visual metaphors for existing scalar resources, not new biological mechanisms.

The revision-eleven cursor lens illustrates optical magnification using the microscopy source above. It is a selective inspection aid, not a new physical field, reaction radius or claim that individual chemical packets can be resolved as literal molecules. The full-resolution overlay is clipped to the lens and retains the packet's displayed orientation. The [Godot CanvasItem shader reference](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/canvas_item_shader.html) documents the texture/modulate input used by its presentation-only clipping shader.

## Varied cytoskeletal networks and musical sonification

**Biological motivation:** filament networks are organized through cross-linking and attachments; their organization helps determine cell mechanics. [How Cells Regulate Their Cytoskeletal Filaments](https://www.ncbi.nlm.nih.gov/books/NBK26809/) describes bundling, cross-linking and membrane-supporting networks. The pressure and compression studies cited in the membrane section above still apply.

**Game:** starting anatomy contains zero to four original links with random tensions, assembled in sequence so later links may branch from earlier ones. This is procedural variety, not a biological distribution of microtubule counts. The tension-only model remains a generic cytoskeletal abstraction.

**Music:** the ecosystem is sonified through an original score. Lower pitches for larger bodies, organ-specific instruments and shader-only pulses are presentation metaphors; cells are not claimed to produce audible techno, and sound never controls chemical reactions or fluid forces.

**Technical sources:** [Godot's audio synchronization guidance](https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html) motivates following consumed audio samples and compensating reported device latency. [AudioStreamGenerator documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html) explains buffering and recommends compiled code for demanding generation; this revision uses a native sampler with a reference fallback. [Audiokinetic's interactive music guide](https://www.audiokinetic.com/en/public-library/2024.1.8_8893/?id=creating_interactive_music&source=Help) motivates combining instrument layers with structured phrase changes. No audio engine middleware is added.

## Pheromone plumes and chemical perception

**Phenomenon:** secreted chemical signals are redistributed by flow and diffusion, and microbes can respond by chemotaxis. [Scheidweiler et al., Spatial structure, chemotaxis and quorum sensing shape bacterial biomass accumulation in complex porous media (Nature Communications, 2024)](https://www.nature.com/articles/s41467-023-44267-y) reports flow-dependent accumulation of *E. coli* responding to self-produced AI-2 and discusses how transport changes access to the signals.

**Game:** each cell releases passive point tracers, sampled by nearby hunting/flight chemoreceptors. Advection follows the local fluid; Gaussian displacement has variance proportional to elapsed time, modeling diffusion. Independent exponential lifetimes limit trail persistence. This motivates discovering a source through a transported cue rather than querying its current position.

**Abstraction:** “pheromone” is the game's broad label for these inter-cell cues. Real molecules do not contain literal coordinates, biomass, lineage IDs or a hostility bit. Encoded emission-time metadata, universal secretion, visual point size, pass-through solids, eight points per second, diffusion coefficient and five-second mean lifetime are gameplay choices, not measurements from that study. Hostility summarizes armed anatomy, not a claim about biological intent. The defense bit additionally summarizes a working protective cortex at emission. “Smaller or undefended” prey selection is a game heuristic, not a molecular defense assay or exact assessment of exposed membrane.

## Inherited themes, habitat timbre and event phrases

These revision-fourteen features sonify existing state: lineage inheritance, the light/acid fields, buffer action, ingestion, oriented toxin neutralization and funded division. Their biological motivations remain in the corresponding sections above. No additional cell sense or chemical rule is introduced.

[Audiokinetic's guide to game syncs and Stingers](https://www.audiokinetic.com/en/public-library/2024.1.5_8803/?id=using_game_syncs_during_playback&source=Help) describes short musical phrases layered over an ongoing score in response to events. This motivates the feeding, neutralization and division accents. Primordia implements its own sample-clock scheduler and synthesized phrases; it adds no Wwise dependency or third-party recordings.

An inherited six-note musical contour is a presentation metaphor for the existing lineage signature. Light-to-filter cutoff, acidity-to-saturation/ripple and buffering-to-calmer timbre are authored listening choices, not measured biological acoustics. Audio may observe rendered ecology, but never supplies information to the pheromone-only perception system or changes authoritative particle behavior.

Revision fifteen moves activity falloff entirely outside the visible rectangle; this is a computational boundary, not a biological law. Briefly tracking a magnified particle is likewise an inspection aid, not an added receptor or live source lookup. Dictionary identity survives array compaction under [Godot’s reference comparison semantics](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html#class-globalscope-method-is-same).

## Dormant reserves and continuing lineages

[Jones and Lennon, Dormancy contributes to the maintenance of microbial diversity (2010)](https://pubmed.ncbi.nlm.nih.gov/20231463/) combines modeling and lake-community observations to study microbial seed banks. Reversible low metabolic activity can preserve organisms through unfavorable conditions and affect future active communities. This motivates Primordia's dormant successors.

The game stores a complete prepaid body outside active physics, with no metabolism, production or damage until hatching. Three storage slots, guaranteed preservation, automatic activation after family loss and one initial founder reserve are game rules, not measured dormancy biology. Extra bodies partition real modeled tissue, oxygen and ATP; the initial reserve belongs to initial inventory. Choosing which relative to manage and inheriting its musical motif are player/presentation conventions.

[Gonzalez and Bell, Evolutionary rescue and adaptation to abrupt environmental change depends upon the history of stress (2013)](https://pmc.ncbi.nlm.nih.gov/articles/PMC3538446/) examines how prior environmental stress affects rescue in yeast populations. It motivates giving a lineage a history of environmental challenges rather than testing only an isolated lifespan.

Primordia compresses those pressures into authored light and rival-anatomy changes. Its three timed crises, survival thresholds, optional AP challenges, named rivals and recalled blueprints are design abstractions. The environment is not intentionally evolving against the player; the director introduces bounded, ordinarily paid variants. Persistent blueprint choices represent player knowledge, not DNA passing between unrelated expeditions, and grant no permanent stat advantage.

## Contact impulses and compliant collision response

**Technical motivation:** [Box2D simulation documentation](https://box2d.org/documentation/md_simulation.html) describes contact constraints, impulses, restitution, Coulomb friction, rotational response and swept collision handling. It motivates the numerical approach; Primordia does not add Box2D as a dependency.

**Game:** deformed membrane contacts exchange equal/opposite impulses for fully active bodies, including the torque of an off-center hit. Limited friction turns glancing impacts into spin. Small restitution allows rebound, while local compression redistributes ring area and the existing pressure/cytoskeleton relaxes the shape. Solid plant stems take the environment's reaction; fine leaves remain decorative. Spike impacts transfer momentum and cause bounded tissue damage, making speed and placement useful.

**Abstraction:** body contacts use a bounded radial approximation, not arbitrary concave polygon manifolds or full continuum mechanics. Finite substeps, swept proxies and positional projection stabilize crossings. Stem samples and spike shaft sweeps approximate contact geometry; restitution, friction and a maximum 45-health impact contribution are playtest constants. Near-static pressing retains ATP-funded damage. No claim of molecular, calibrated tissue or globally energy-conserving fluid simulation is made. The pressure/cytoskeleton references above motivate deformability, not the chosen damage curve.


## Coarse offscreen transport

**Phenomenon and numerical motivation:** [OceanParcels' diffusion tutorial](https://docs.oceanparcels.org/en/latest/user_guide/examples/tutorial_diffusion.html) derives Lagrangian advection with random displacement consistent with the advection–diffusion equation. For uniform diffusivity D, each coordinate's Brownian displacement has variance 2 D Δt. Larger steps therefore use square-root time scaling for diffusion, while deterministic current displacement scales with elapsed time.

**Game:** distant material and pheromones take staggered half-second transport steps. Midpoint current sampling follows bends in the cached flow; launch velocity uses an exponential drag integral. The existing viscous field refreshes outside the camera in quarter-second steps. This models continuing dispersal with fewer particle visits.

**Abstraction:** the update interval, diffusion coefficients, toroidal habitat and externally maintained tide are game parameters. Brownian paths are sampled only at update endpoints; a swept chord against solid stems approximates material collision between endpoints. Pheromones intentionally ignore solids. Revision eighteen left distant cells, chemistry and cell-fluid forcing dormant. Revision nineteen supersedes that limitation near living cells; neither version is a calibrated molecular or incompressible fluid solver. No OceanParcels dependency is added.

## Coarse ecology, encounter limits and lysis

**Numerical motivation:** [Gillespie, Approximate accelerated stochastic simulation of chemically reacting systems (2001)](https://doi.org/10.1063/1.1378322) introduces tau-leaping: approximating the number of events during a finite interval to reduce simulation work. Primordia uses Poisson event counts for coarse secretion/photosynthesis and exponential encounter hazards, bounded by actual stored resources. It is not a rigorous tau-leaping implementation or a molecular-rate calibration. Pair chemistry still requires oriented contact; this numerical reference does not justify replacing binding angles with random reactions.

**Encounter limits:** [Holling, Some Characteristics of Simple Types of Predation and Parasitism (1959)](https://hahana.soest.hawaii.edu/cmoreserver/summercourse/2010/documents/Holling_1959b.pdf) motivates separating search and handling time. The game uses finite absorption area, storage limits and a short post-kill handling interval. One-second scheduling, the collection-area calibration, attack hazard and three-second handling interval are gameplay approximations; no particular microbial predation rate is inferred from Holling's experiments.

**Biological motivation:** [Zhao et al., Microbial transformation of virus-induced dissolved organic matter from picocyanobacteria: coupling of bacterial diversity and DOM chemodiversity (2019)](https://www.nature.com/articles/s41396-019-0449-1) examines microbial use and transformation of material released by viral lysis. This motivates making cellular contents available to surrounding consumers rather than paying a private reward to the killer. Primordia has no viral infection system here: spike/toxin/starvation deaths use a simplified lysis event that converts represented organic material into nutrient packets and releases retained oxygen. Immediate conversion, packet sizes and absorption reach are game rules, not a literal decomposition model.


## Membrane depth and flow presentation

**Visual reference:** [Cameron Beccario / Earth Nullschool](https://earth.nullschool.net/about.html) visualizes wind and ocean-current fields. Its animated curved streamers motivate replacing Primordia's short background vectors with pale, flowing trails. This implementation is original Godot shader/mesh code; no Earth source, artwork or weather data is imported.

**Physical motivation:** [Purcell, Life at low Reynolds number (1977)](https://doi.org/10.1119/1.10903), also available as an [author-text reprint](https://www.physics.brocku.ca/Courses/1P92_Kaur/SolidsFluids/Life-at-low-R/), explains why viscosity dominates micron-scale swimming. This motivates showing local relative flow rather than treating the medium as empty space.

**Game and limits:** streamers integrate the existing cached two-dimensional velocity field. Cell disturbance glints brighten with body/fluid slip; plant glints sample flow at a few solid stems. Rounded membrane shading follows the actual deformable boundary with a fixed viewing light. The rings are stylized optical cues for submerged disturbance, not literal capillary waves, turbulent vortex shedding, calibrated low-Reynolds-number wakes, or new forces on particles. Plants do not gain fluid coupling in this art revision; their existing solid contacts are unchanged.


## Competing chemical cues and anatomical signal strength

**Phenomenon:** changing relative chemoreceptor abundance can change which of two opposing chemical gradients bacteria favor. [Kalinin et al., Responses of Escherichia coli bacteria to two opposing chemoattractant gradients depend on the chemoreceptor ratio (2010)](https://pubmed.ncbi.nlm.nih.gov/20118262/) measures this using methyl-aspartate and serine in a microfluidic device.

**Game:** grazing, hunting and light-seeking organs have adjustable directional weights. A coherent selected drive gets a 20% switching margin; arriving signals are checked against current anatomy and the remembered drive. Short memory still expires when cues disappear. Pores with zero steering continue pumping, digesting and absorbing. The inherited self-recognition reference above motivates retaining family signatures throughout the signal path.

**Abstraction:** these controls represent fictional receptor expression/gain, not measured receptor counts. Discrete percentages, scalar salience, winner-takes-direction selection, hysteresis, automatic safety priority and unchanged metabolic costs are game choices. This experiment does not establish those constants, predator sensing or phototaxis. No live-source lookup or awareness of a prey's death is added.

Mounting artwork and forces to a local membrane normal is a geometric/game abstraction. Purcell's microswimming work and the feeding-current study cited above still motivate appendage/fluid coupling; reversible axial propulsion is not a calibrated flagellar motor model. Paired tissue blobs compare areas representing existing material, not extra biomass or literal three-dimensional volume. Wider microtubule picking and the cell-adjacent lens exclusion are interface choices.

The reaction spark visualizes a successful existing orientation-dependent pair rule, described above. It is not a claim that microscopic biochemical reactions make visible sparks, generate heat/light in this model, or transfer momentum. Its capped instanced shader adds no chemical species or random draw.
