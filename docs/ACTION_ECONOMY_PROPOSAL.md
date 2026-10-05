# Proposal: adaptation economy, ecosystem resistance and victory

Status: design proposal for owner review. No gameplay changes are authorized by this document. All costs, timings and thresholds below are starting hypotheses, not tuned values. Existing gameplay remains revision 8.

## Recommendation

Build a short run around a constrained adaptation budget, paid anatomy and a forecasted ecological escalation. Retain continuous autonomous simulation and paused anatomical editing. The important decisions are what to grow, what to specialize, what to keep in reserve and when to prepare for reproduction.

Use the upgrade choices and compounding combinations of [Monster Train](https://store.steampowered.com/app/1102190/Monster_Train/) as inspiration. The owner's virus-evolution/resistance example supplies the second principle: a strategy buys an advantage for a while, then the surrounding world begins to challenge it. Do not assume the example refers to the Pandemic board game; the exact title is not needed for this design.

Keep only one new spendable resource. No separate gold, research, construction workers, gene slots or manually cast attacks. Persistent metagame power remains undecided.

## 1. Three resources, three distinct decisions

| Resource | Obtained through | Spent on | Decision |
| --- | --- | --- | --- |
| Biomass | Existing feeding and carbon fixation | Anatomy, enlargement, repair and offspring | Can I afford the material, and what reserve will remain? |
| ATP | Existing metabolism | Organ operation, secretion, propulsion and healing | Can this anatomy sustain its running cost? |
| Adaptation points — new | A bounded allowance at ecological milestones, with limited optional risk bonuses | Installing additional organs, changing their type, substantial enlargement and applying drafted mutations | Which changes are worth making now? |

ATP and biomass already exist. Make their opportunity costs visible, rather than adding parallel currencies. Building material must transfer into anatomy, and offspring must receive material from their parent. Adaptation points are an explicit game abstraction, not DNA molecules collected from food.

Prototype allowance: start with a functional anatomy and 3 adaptation points; gain 3 at each tide transition. An announced optional challenge can award at most 1 extra point per tide. Carry unspent points forward. Ordinary kills and particles do not create unlimited point income, and grazing/photo builds must have equally available challenges.

Baseline organ types remain available throughout a run. Random offers may shape specialization but cannot withhold the only answer to a telegraphed hazard.

Example costs, before tuning:

| Choice | Adaptation | Biomass | Continuing cost |
| --- | ---: | ---: | --- |
| Add a normal flagellum | 1 | 8 | More ATP consumption while propelling |
| Add a toxin neutralizer | 1 | 10 | ATP/material spent on secretion |
| Apply a specialized grazing-pore upgrade | 2 | 12 | Depends on the mutation |
| Regrow damaged existing anatomy | 0 | Actual replacement material | Existing repair ATP cost |

The normal biomass prices illustrate current 1x organs; mutation and adaptation prices are proposed. Larger construction must cost more. Charge enlargement cumulatively by added capacity/material, so many tiny wheel adjustments cannot avoid the same total cost.

There is no new size cap or socket count. Natural biomass growth continues; the new budget constrains deliberate anatomical investment. A larger cell still has to support its operating costs and exposed membrane.

## 2. Protect the enjoyable editing

Tab continues to pause the entire run, including the ecological clock. Plans can be previewed and undone freely until committed. Reopening the menu neither refreshes offers nor awards points.

Organelle relocation and microtubule placement/tension remain free planning tools. Adding, substantially enlarging or changing an organ's function costs adaptation. Ordinary healing and restoration of the same damaged anatomy do not: a setback should consume reserves without also blocking recovery behind another currency.

Recycling returns a partial, clearly stated amount of actual remaining organ material, never adaptation points. Damaged organs cannot refund their undamaged value. A previously paid functional change does not become free by shrinking, removing and replacing it.

Automatic maintenance favors membrane survival and essential feeding before discretionary secretion when ATP is scarce. Show this priority and projected ATP balance before committing a build. Do not introduce an additional manual priority-management minigame in the first version.

Example: with 3 adaptation points and 36 biomass, a better grazing pore (2/12) and a neutralizer (1/10) leave 14 biomass for healing. Taking only the pore leaves a point and more material for an emergency. A stronger income engine, immediate protection and flexibility compete for the same budget.

## 3. Draft a genome

At each tide, offer three mutation blueprints and let the player keep one. Choosing the blueprint is free; applying it to an organ costs adaptation and biomass. Kept blueprints remain available for that run. This separates discovering an option from being able to afford it.

Use persistent organ modifications, not a shuffled hand of movement commands or instant attacks. The cell continues to choose its own targets and actions. Early drafts should include a useful economy/defense option and a more speculative synergy, with no paid reroll system initially.

Proposed examples using existing organs:

| Mutation | Benefit | Price/tradeoff |
| --- | --- | --- |
| Concentrated digestive secretion | Stronger local enzyme delivery | Higher ATP demand and less broad dispersal |
| Reserve cortex | Better local protection | More mass and reduced mobility |
| Pulsed toxin vesicle | Larger automatic bursts | More material per burst and longer recovery |
| Efficient photosynthetic membrane | Better carbon fixation in adequate light | Worse yield in dim conditions; more exposed working surface |
| Recuperative repair body | Stronger recovery from recent wounds | Greater biomass demand during repair |

These are candidate traits, not approved biochemical changes. Effects must remain expressed through existing organs, actual particles and shared cell rules. Any altered reaction affinity still respects orientation-based contact; a card must not silently restore reaction-success dice.

Avoid unbounded multiplicative stacks. More efficient organs should create recognizable combinations, but a favorable draft should not produce a resource loop that pays for itself without external inputs.

## 4. A world that pushes back

Use two independent, readable sources of pressure.

**Forecasted tides:** six roughly two-minute ecological phases, followed by a roughly 90-second final challenge, give an initial run target around 12–15 minutes of unpaused simulation. Pause time never counts. Reveal the final challenge early and warn of the next tide before it arrives. Examples: dimmer light, fewer food-producing cells, a migration of toxin producers, or more heavily protected hunters.

Food scarcity must emerge from producer/consumer populations and existing chemistry. Do not add magical nutrient rain; cells remain the source of external particles. Introductions use explicit population events with accounted material, as current replacements do.

**Adaptation in opposing populations:** exposure and survival history gradually bias future population variants. This is a compressed representation of selection across generations, not a claim that one cell intentionally evolves because the player attacked it.

| Successful strategy | Possible opposing shift | Weakness retained by the opponent |
| --- | --- | --- |
| Repeated toxin use | More neutralizer-equipped survivors/replacements | Secretion consumes ATP and material |
| Spike predation | More protective cortex or flight receptors | Mass, operating costs and less investment in feeding |
| Acid-assisted grazing | More buffering/repair investment nearby | Resources diverted from other functions |
| Productive photosynthetic patch | More competitors exploiting its food and oxygen | Competitors depend on the productive patch too |

Use the same anatomy, costs and damage rules for NPCs. Do not confer invisible immunity or increase every enemy's biomass to match the player. Adapted variants appear gradually in a portion of the population; susceptible prey and alternative opportunities remain.

Show an explanation such as “Toxin-neutralizing variants are becoming common,” backed by visible anatomy and particles. Maintain a warning period and a ceiling on adaptive pressure per tide. Success must still feel like success: the player should enjoy a strong build before counters become relevant.

The player can diversify, change diet, prey on a counter's weakness, or pay to strengthen the original strategy. A forced full rebuild every tide would destroy attachment to the organism.

The ecological clock advances on unpaused simulation time independently of free-camera position. Offscreen simulation remains dormant, but coarse phase/selection records continue. Entering a menu or looking away cannot farm rewards, reroll drafts or reset resistance.

## 5. Victory conditions

### Recommended default: establish a lineage

Win by funding reproduction and getting a viable offspring through the final environmental challenge. A grazer, photosynthetic cell, toxin hunter, spike predator or mixed build can all achieve this through their own resource economy.

Invest biomass and ATP into a visible reproductive reserve. That investment competes with immediate strength and healing. The allocation is a build decision; division and offspring behavior are automatic. The offspring inherits the chosen anatomy/traits, receives actual transferred material, and needs its own viable feeding/energy arrangement. Parent and offspring cannot duplicate biomass. The final viability check must use health and sustained metabolism, not a single frame alive.

An initial finale could require the parent to reach a displayed reserve target before the last tide, then require its offspring to remain viable through a 60–90-second challenge. Exact quantities depend on the starting anatomy and playtests. If the offspring dies or no viable lineage exists at the deadline, the run is lost. Parent death before successful division also loses. After division, the objective, build editor and following camera transfer to the offspring; the parent becomes an autonomous neighbor. The unspent adaptation budget transfers without resetting. The player still manages one cell and gains no manual movement or targeting controls.

This creates an endgame decision: spend the next meal becoming stronger, or commit it to winning.

### Alternative: dominance

Defeat a small announced set of distinct rival lineages before the end of the run. Each has readable anatomy and a different weakness. No universal invulnerability or arbitrary boss-only damage rules.

This is an optional predatory objective, never a mandatory gate for other victories. With the current spike rule, a player may need to outgrow a rival before pursuing it; toxin strategies offer a different investment. Farming repeated easy replacements does not count as new rival victories.

### Alternative: survive the collapse

Prepare a protected dormant stage and emerge viable after a forecasted famine/toxic season. Stockpiling, efficient maintenance, cortex, repair and neutralization matter more than kill count. Dormancy reduces activity and feeding; it does not make the cell invulnerable or let it ignore chemistry/contact.

This is a candidate later feature because no dormancy physiology is implemented. Keep it a distinct active finale with resource expenditure and visible threats, not several minutes of watching a timer in guaranteed safety.

### Later chemistry-focused objective: establish a refuge

Maintain a productive local community through a hostile tide using oxygen production, toxin neutralization and buffering. Measure a defined local region over time, including viable neighboring cells, rather than demanding perfect conditions across the entire torus. Measure the player's net contribution; preexisting healthy water should not win automatically.

This could give environmental chemistry a strong purpose, but attribution, readability and stability need prototyping. Do not require it for the first economy revision.

The first release should use lineage victory with several viable diets. Dominance is the next simplest alternate scenario. Permanent unlocks, account progression and campaign persistence remain undecided.

## 6. Fairness and anti-exploit rules

- Baseline rewards support recovery; bonus points are bounded and optional. Do not make “kill to earn every adaptation point” the only competitive strategy.
- Evaluate challenges through net progress, diverse encounters or survival of a specific event. Reabsorbing one's own secretions, selling/rebuying tissue, deliberately taking damage or farming replacement cells must not generate repeatable rewards.
- Do not penalize pausing. Challenge comes from commitments and ecological consequences.
- Forecast hazards and costs. Telegraph “your ATP budget will be negative” and “this purchase uses your last repair reserve” before confirming.
- Keep useful low-cost choices when resources are low. Preserve repair and free shape experimentation.
- Set opposition budgets by scenario/tide with limited ecological feedback, rather than exact player-strength matching.
- Keep successful builds exciting. Counters should demand adjustment, not erase specialization.
- Give the ending and its requirements a visible progress display. Offer endless continuation only as a separate post-victory choice if later approved.

## 7. First prototype and acceptance

Prototype the three-resource economy, paid remodeling, a small set of roughly 12 mutation blueprints, six forecasted tides, a small number of anatomy-based opposing variants and lineage victory. Reuse the existing organ list and chemistry. Defer extra currencies, manual combat cards, full population genetics and persistent power progression.

Test several seeds and starting diets. Seek meaningful choices at most tide boundaries, a reasonable recovery chance after a mistake, and both predatory and non-predatory wins. Track spending decisions, unused points, repair starvation, wins/losses by diet, dominant mutations, pauses per tide and whether early investment or saving always wins. Costs and timing should change if one option is consistently mandatory.

Performance must be a separate acceptance gate because the current whole-game wide-view target is unmet. Economic bookkeeping uses aggregate counters and occasional phase updates; adaptive populations replace existing budgeted slots rather than endlessly adding cells or particles. Benchmark actual live play at half/quarter/minimum zoom, dense chemistry, deaths, offspring and growth-induced zoom. A cheap rules layer does not resolve the existing rendering/simulation bottleneck.

## Scientific grounding

- [Scott et al. (2010), cell growth and gene expression](https://pubmed.ncbi.nlm.nih.gov/21097934/): experimentally motivated resource-allocation constraints support the idea that expressing more machinery competes with growth. Biomass prices, ATP budgets and adaptation points remain game abstractions.
- [Buckling and Rainey (2002), bacterium–phage coevolution](https://pmc.ncbi.nlm.nih.gov/articles/PMC1690980/): experimental antagonistic coevolution motivates delayed adaptation and counter-adaptation. Applying this to spikes/toxins over minutes is a deliberate simplification, not the phenomenon measured in that experiment.
- [Costs during host–parasite coevolution (2006)](https://pmc.ncbi.nlm.nih.gov/articles/PMC1560003/): experiments motivate treating resistance as potentially costly. The particular mobility, ATP and feeding tradeoffs above are design choices, not universal biological laws.
- [Bacteria-phage coevolution with a seed bank (2023)](https://www.nature.com/articles/s41396-023-01449-2): experiments with bacterial endospores motivate dormancy as an alternative survival investment. Primordia's generic cell is not being asserted to be a spore-forming bacterium, and the suggested cyst is not yet a mechanic.

See also the project-wide [reference policy and implemented abstractions](../references.md).
