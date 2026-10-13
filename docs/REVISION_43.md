# Revision 43 — particle chemistry inside the cell

The cell is a biochemical sandbox. Chemical transport uses finite moving
particles both outside the membrane and inside the cytoplasm. Graph edges
configure enzyme binding compatibility; they never move a resource or credit
a distant pool.

## Playing and editing

Press **Tab**, open the cell's **Chemistry** factory and choose **Pathways**.
All templates are available immediately. The temporary graph shows each
installed catalyst's compartment, allocation, last reaction rate and limiting
input. Connect matching metabolite ports to permit binding between those
producers and consumers. Circulation and diffusion still have to bring the
actual molecules together.

Food-vacuole, contractile-vacuole and light domains are inherent configurations.
Photosynthesis also requires its ordinary paid membrane organ. Additional
glycolytic, respiratory, fermentation, synthesis, salvage, excretion and carrier
enzymes, or an experimental condensate, cost **10 tissue and 1 AP** each.
They occupy retained physical catalyst/compartment material. A cell supports
at most 16 catalyst nodes and 8 domain types. Recycling returns half the reactor
structure as usable tissue and half as waste; proteins/seeds remain accounted
particles, and AP is not refunded.

The graph saves at most 32 local designs. A design contains configuration only.
Loading requires the same installed template identities and paid capacities;
it cannot install missing anatomy, restore food or ATP, move catalysts,
teleport particles, or rewind a cell. Invalid configurations are rejected
atomically. Reactions use the authored templates, never arbitrary equations
or code.

**Editing pauses chemical movement, reactions and all physiology**, along with
the outside habitat. AP blobs and presentation effects remain nonphysical
animation. Leaving editing, death or a new cell invalidates the open panel.

## Chemical toolkit

| Domain | Actual particle inputs | Particle outputs / incorporation |
| --- | --- | --- |
| Food vacuoles | Food, local ATP, catalytic protein; acidification precedes hydrolysis | Glucose, precursor and waste; oxidized food yields salvage |
| Glycolysis | Glucose, NAD⁺, ADP | Pyruvate, NADH, ATP |
| Aggregate respiration | Pyruvate, oxygen, NADH, ADP | Carbon, precursor, waste, NAD⁺, ATP |
| Lactate fermentation | Pyruvate, NADH | Lactate and NAD⁺ |
| Tissue synthesis | Precursor and ATP | Material incorporated into retained tissue |
| Salvage activation | Oxidized salvage and ATP | Activated precursor |
| Excretion conversion | Lactate and ATP | Waste, which must reach the cytoproct |
| Photosynthesis | Local carbon, light; local ADP when ATP is made | Glucose, oxygen, tissue and ATP |
| Carrier synthesis | Precursor and ATP | ADP and accounted waste |
| Contractile vacuoles | Local water particles and ATP | Water expelled to the solvent |
| Experimental autocatalysis | Local precursor, ATP, catalysts A and B | Additional A/B particles; turnover yields waste |

ATP/ADP and NAD⁺/NADH are real finite carrier particles. Spending and production
convert local carriers. Offspring ATP reserves are particles as well. Amount
properties and editor readouts are derived totals, with compatibility setters
reserved for initial conditions and explicit fixtures. Reactions query bounded
spatial neighborhoods of actual catalytic proteins. Products appear where a
reaction happens and subsequently move. Body/tissue remains stationary
structure, rather than a circulating chemical store.

Food vacuoles retain their captured particles and paid membrane/protein
material. Their acidification and digestion cost local ATP. Contractile
vacuoles expel only water that physically reaches them; excessive water load
damages the cell. Internal membrane domains are coarse permeable reaction
regions, not detailed organelle ultrastructure or a proton-gradient solver.

Division inherits the network and partitions metabolites after a safe birth
position and funded reserve have been accepted. Lysis releases each retained
chemical with its species and current fuel, and converts retained tissue to
debris exactly once. Spilled ATP, redox carriers and water have zero represented
organic-material weight. Recycling waste into edible salvage never restores
fuel potential; activating that salvage costs ATP.

## Chemical predation

Physical hunting spikes, spike injury and the barbed-spike mutation are removed.
The same anatomy slot is a rounded **pore-forming gland**. It spends local ATP
and tissue to emit a surface tag plus four finite subunit packets. A tag and
aligned subunits must reach the same local membrane patch before a pore can
damage ordinary tissue/armor. The four-subunit rule is a game abstraction.

Antitoxin can neutralize free tags/subunits or cap an unfinished assembly.
Regenerative anatomy pays for removal of completed pores. Bound material is
retained and returned to waste on removal or expiry. Family signatures protect
related cells in the reference, native and GPU paths.

The hunting receptor still uses immutable local pheromone reports, and explicit
flight takes priority. Glands have no sensing or live-target lookup. Hidden
hunting no longer awards statistical kills: predation requires actual chemical
contact in every transport tier.

## Richer finite particle habitat

The default starting cell-derived packet population is ten times the previous
one: **37,600 external packets** at the normal balanced profile. Initial food,
carbon and oxygen are explicit finite pre-observation inputs. Later material
comes from cell-funded secretion, photosynthesis, excretion and lysis; there is
no environmental food spawner.

Emission uses smaller finite packets, and oriented aggregation is bounded to
0.5 units. Photosynthesis capacity and dissolved-carbon storage are higher.
There is no global particle quota or camera-dependent resource creation.

The intended visual scale is roughly **7,000 on-screen chemical packets**
(including oxygen, excluding informational pheromones). F3 separately reports
actual visible chemical packets, packets with represented organic material,
signals, internal particles, detailed activity and stored ownership scope.
At the standard seed, initial visible counts were 6,006 at 100% and 7,741 at the
widest playable 80% view. These are density observations, not a survival,
balance or frame-rate claim.

CPU remains the default. The existing resident GPU option uses the shared
26-species catalog, finite contact/fuel receipts, compact visible counts and
expanded generated artwork. Native headers are generated automatically from
data/chemistry.json into ignored build/, and are never committed.

## Validation policy and scientific limits

**Owner instruction, October 13, 2026:** every gameplay-balance test is disabled
until further notice. tests/test_policy.gd is the single source policy; there
is no environment override. The full runner and standalone economy/balance
harnesses print explicit skips. Unattended survival, autonomous hunting
capability, metabolic-yield tuning and live victory campaigns remain in source
for later restoration. Correctness tests continue for local particle behavior,
conservation, paid operations, elapsed-time accounting, physics, UI, replay and
backend consistency.

All amounts are weighted game units. Respiration is an aggregate pathway,
fermentation recycles redox carriers, carrier mass is abstracted, tissue growth
uses represented area, and the solvent/light are implicit reservoirs.
The catalog checks represented material and fuel potential; it is not an
atom-by-atom molecular chemistry simulator. Motives and limitations are
documented in [references.md](../references.md).

Autophagy, reactive-oxygen detoxification, detailed lipid/membrane synthesis,
nitrogen assimilation, gene-expression regulation, quorum cooperation and a
resolved electron-transport/proton-gradient system remain useful future
extensions. They are not implemented by this revision.

Validation measurements from the workstation's RTX 5080 do not establish
Threadripper/RTX 3090, phone performance, sustained 60 FPS, or gameplay balance.
