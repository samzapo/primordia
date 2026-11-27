export interface MutationDef {
  kind: string;
  title: string;
  short: string;
  summary: string;
  modifiers: Record<string, number>;
}

export const LIGHT_ADAPTATIONS = ['sun_leaf', 'shade_leaf'] as const;

export const MUTATION_DATA: Record<string, MutationDef> = {
  economical_flagellum: {
    kind: 'propulsion',
    title: 'Economical flagellum',
    short: 'Economical',
    summary: 'Uses 50% less ATP when swimming at 80% thrust.',
    modifiers: { thrust: 0.8, motion_cost: 0.5 },
  },
  layered_cortex: {
    kind: 'protection',
    title: 'Layered cortex',
    short: 'Layered',
    summary: 'Increases protective cortex health by 60%.',
    modifiers: { health: 1.6 },
  },
  recuperative_repair: {
    kind: 'regenerative',
    title: 'Recuperative repair',
    short: 'Recuperative',
    summary: '60% faster membrane & organ repair at 40% more ATP per unit.',
    modifiers: { repair: 1.6, repair_cost: 1.4 },
  },
  wide_pore: {
    kind: 'feeding',
    title: 'Wide oral groove',
    short: 'Wide pore',
    summary: '30% wider intake and stronger suction (+0.10 ATP/s upkeep).',
    modifiers: { intake: 1.3, suction: 1.3, upkeep: 0.1 },
  },
  enzyme_pore: {
    kind: 'feeding',
    title: 'Digestive enzyme groove',
    short: 'Enzyme',
    summary: 'Doubles enzyme secretion rate; enzymes stay closer to the cell.',
    modifiers: { secretion: 2.0, secretion_cost: 1.6, dispersal: 0.5 },
  },
  long_receptor: {
    kind: 'sensing',
    title: 'Sensitive flight receptor',
    short: 'Sensitive',
    summary: '50% wider hazard & threat sensing reach (+0.08 ATP/s upkeep).',
    modifiers: { sense: 1.5, upkeep: 0.08 },
  },
  sun_leaf: {
    kind: 'photosynthesis',
    title: 'Sun specialist',
    short: 'Sun',
    summary: 'Seeks brighter water; boosts photosynthesis by 70% in bright water.',
    modifiers: { sun: 1.7, shade: 0.6 },
  },
  shade_leaf: {
    kind: 'photosynthesis',
    title: 'Shade specialist',
    short: 'Shade',
    summary: 'Seeks moderate light (0.35–0.45); boosts dim-water photosynthesis by 60%.',
    modifiers: { sun: 0.7, shade: 1.6 },
  },
  pulse_vesicle: {
    kind: 'toxin',
    title: 'Pulse toxin gland',
    short: 'Pulse',
    summary: '2.5× larger toxin & decoy bursts with 2× cooldown.',
    modifiers: { burst: 2.5, cooldown: 2.0 },
  },
  dense_antitoxin: {
    kind: 'neutralizing',
    title: 'Rapid neutralizer',
    short: 'Rapid',
    summary: '70% faster antitoxin secretion at 90% more ATP per burst.',
    modifiers: { secretion: 1.7, secretion_cost: 1.9 },
  },
  acid_pulse: {
    kind: 'acidifying',
    title: 'Rapid acid gland',
    short: 'Rapid acid',
    summary: '70% faster acid secretion at 90% more ATP per burst.',
    modifiers: { secretion: 1.7, secretion_cost: 1.9 },
  },
};

export function mutationFactor(mutation: string, stat: string): number {
  if (!mutation) return stat === 'upkeep' ? 0.0 : 1.0;
  const def = MUTATION_DATA[mutation];
  if (!def) return stat === 'upkeep' ? 0.0 : 1.0;
  return def.modifiers[stat] ?? (stat === 'upkeep' ? 0.0 : 1.0);
}

export function availableMutationsForOrgan(
  kind: string,
  currentMutation: string,
  learned: string[],
): string[] {
  if (kind === 'photosynthesis') {
    return [...LIGHT_ADAPTATIONS];
  }
  if (currentMutation) return [];
  const out: string[] = [];
  for (const gene of learned) {
    if (MUTATION_DATA[gene]?.kind === kind) out.push(gene);
  }
  return out;
}
