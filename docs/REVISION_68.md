# Revision68 — mitochondrial energy efficiency

Owner request, October18: mitochondria should be an upgrade to ATP production, without a biomass trade-off. Experimental first; preserve both saved ponds, every body/anatomy/account, five keys and private feedback. Main awaits owner playtest.

## Rule

Each healthy normal-sized mitochondrion adds50% of baseline aerobic digestion ATP:0 gives1x,1 gives1.5x,2 gives2x, capped5x. Health/area weights capacity; old Output values remain inert. The multiplier applies only to the oxygen-supported fraction, not direct photosynthetic ATP or fermentation. Position remains cosmetic for this bonus. Ordinary0.04ATP/s maintenance remains.

Separate nutrient quality's existing allocation bonus from mitochondrial recovery. Mitochondria recover only unallocated finite fuel after tissue and quality output; they never reduce tissue, consume extra food/oxygen or speed digestion. Empty/depleted fuel and distant oxygen cannot pay a bonus.

## Finite energy

New fully fueled food represents18 energy per material unit, including respiratory energy normally dissipated as heat. Tissue and emergency tissue mobilization retain7.5. Baseline ATP/biomass yields remain2.25/.7 with oxygen and1/.3 without. A fully fueled ordinary meal with one mitochondrion yields3.375ATP and.7biomass; two yield4.5ATP and.7biomass. At5x plus maximum nutrient bonus, outputs remain below18.

Photosynthesis pays its new food energy explicitly in solar_work:0.35*7.5+0.65*18+4=18.325 per fixed unit. Leaks and structural lysis retain tissue energy in exterior capacity; food lysis preserves its actual remaining fuel. Spent recycling never refuels. CPU and resident GPU use shared authored constants.

Existing saved food keeps its exact fuel, quantities and age; no migration/refill or new stored field is needed. Older low-energy food may have little heat to recover until fresh food arrives. Both restore/upgrade and subsequent restart retention remain strict.

The existing Alberts mitochondrial/ATP-coupling reference motivates the mechanism. Numeric fuel units,50% increments and5x cap are game abstractions, not molecular yields. See references.md.

## Acceptance

Check0/1/2/many organs, damage, no/distant oxygen, exhausted and legacy fuel, nutrient quality, unchanged food/oxygen and biomass outputs, finite ATP/tissue/heat accounting, photosynthetic solar input, non-refueling lysis, checkpoint recovery and resident CPU/GPU parity without particle exports. Run required suites, functional hardware checks and target restart/delivery checks. No rendering-speed campaign.
