import { ORGAN_KINDS, type OrganKind } from '../sim/cell.ts';
import { SPECIES, SPECIES_COUNT, TAU } from '../sim/constants.ts';
import type { PlantForm } from '../sim/habitat.ts';
import { ORGAN_COLORS, UI_COLORS } from './palette.ts';

export interface ProceduralAtlases {
  speciesDetailed: GPUTexture;
  speciesSimple: GPUTexture;
  plants: GPUTexture;
  organs: GPUTexture;
  nuclei: GPUTexture;
  vacuoles: GPUTexture;
  sampler: GPUSampler;
  organIcons2D: Map<OrganKind, string>;
}

function makeCanvas(w: number, h: number): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

function createMipmappedArrayTexture(
  device: GPUDevice,
  canvases: HTMLCanvasElement[],
  size: number,
  label: string,
): GPUTexture {
  const mipCount = Math.min(5, Math.floor(Math.log2(size)) + 1);
  const tex = device.createTexture({
    label,
    size: [size, size, canvases.length],
    mipLevelCount: mipCount,
    format: 'rgba8unorm',
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });

  for (let layer = 0; layer < canvases.length; layer++) {
    let cur = canvases[layer];
    for (let mip = 0; mip < mipCount; mip++) {
      const mSize = Math.max(1, size >> mip);
      if (cur.width !== mSize || cur.height !== mSize) {
        const next = makeCanvas(mSize, mSize);
        const nctx = next.getContext('2d')!;
        nctx.imageSmoothingEnabled = true;
        nctx.imageSmoothingQuality = 'high';
        nctx.clearRect(0, 0, mSize, mSize);
        nctx.drawImage(cur, 0, 0, mSize, mSize);
        cur = next;
      }
      const ctx = cur.getContext('2d')!;
      const img = ctx.getImageData(0, 0, mSize, mSize);
      device.queue.writeTexture(
        { texture: tex, mipLevel: mip, origin: [0, 0, layer] },
        img.data,
        { bytesPerRow: mSize * 4, rowsPerImage: mSize },
        [mSize, mSize, 1],
      );
    }
  }
  return tex;
}

function drawPolygon(ctx: CanvasRenderingContext2D, cx: number, cy: number, r: number, sides: number, rot = 0): void {
  ctx.beginPath();
  for (let i = 0; i < sides; i++) {
    const a = rot + (TAU * i) / sides;
    const x = cx + Math.cos(a) * r;
    const y = cy + Math.sin(a) * r;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
}

export function drawSpeciesIcon2D(
  ctx: CanvasRenderingContext2D,
  species: number,
  size: number,
  simplified: boolean,
): void {
  const cx = size * 0.5;
  const cy = size * 0.5;
  const r = size * 0.34;
  ctx.save();
  ctx.clearRect(0, 0, size, size);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  if (simplified) {
    const colorMap: Record<number, string> = {
      [SPECIES.NUTRIENT]: '#ffcb47',
      [SPECIES.OXYGEN]: '#5ce6ff',
      [SPECIES.WASTE]: '#9aa864',
      [SPECIES.PHEROMONE]: '#e68aff',
      [SPECIES.TOXIN]: '#ff4d6d',
      [SPECIES.CARBON]: '#829eb5',
      [SPECIES.ENZYME]: '#e06bff',
      [SPECIES.ANTITOXIN]: '#4ff0d8',
      [SPECIES.ACID]: '#ff7b5c',
      [SPECIES.BUFFER]: '#5ef29d',
      [SPECIES.DECOY]: '#ffb545',
      [SPECIES.TAG]: '#ff923b',
      [SPECIES.PORE]: '#cf3e72',
    };
    const col = colorMap[species] ?? '#b7d4ea';
    const grad = ctx.createRadialGradient(cx - r * 0.25, cy - r * 0.25, r * 0.1, cx, cy, r);
    grad.addColorStop(0, '#ffffff');
    grad.addColorStop(0.4, col);
    grad.addColorStop(1, col + 'bb');
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.86, 0, TAU);
    ctx.fill();
    ctx.lineWidth = Math.max(1.5, size * 0.045);
    ctx.strokeStyle = 'rgba(20, 34, 48, 0.55)';
    ctx.stroke();
    ctx.restore();
    return;
  }

  switch (species) {
    case SPECIES.NUTRIENT: {
      // Golden carbohydrate hexagon with rich ring highlight
      drawPolygon(ctx, cx, cy, r * 0.92, 6, -Math.PI / 6);
      const grad = ctx.createRadialGradient(cx - r * 0.2, cy - r * 0.25, r * 0.1, cx, cy, r);
      grad.addColorStop(0, '#fff5b8');
      grad.addColorStop(0.45, '#ffbe3b');
      grad.addColorStop(1, '#c97214');
      ctx.fillStyle = grad;
      ctx.fill();
      ctx.lineWidth = size * 0.05;
      ctx.strokeStyle = '#6b3806';
      ctx.stroke();
      drawPolygon(ctx, cx, cy, r * 0.45, 6, -Math.PI / 6);
      ctx.strokeStyle = 'rgba(255,250,220,0.85)';
      ctx.lineWidth = size * 0.035;
      ctx.stroke();
      break;
    }
    case SPECIES.OXYGEN: {
      // Twin cyan O2 diatomic spheres + double bond
      ctx.strokeStyle = '#d4fbff';
      ctx.lineWidth = size * 0.06;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.4, cy - r * 0.08);
      ctx.lineTo(cx + r * 0.4, cy - r * 0.08);
      ctx.moveTo(cx - r * 0.4, cy + r * 0.08);
      ctx.lineTo(cx + r * 0.4, cy + r * 0.08);
      ctx.stroke();
      for (const sx of [-1, 1]) {
        const px = cx + sx * r * 0.44;
        const g = ctx.createRadialGradient(px - r * 0.12, cy - r * 0.12, r * 0.05, px, cy, r * 0.42);
        g.addColorStop(0, '#ffffff');
        g.addColorStop(0.5, '#6ceaff');
        g.addColorStop(1, '#128ab5');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(px, cy, r * 0.42, 0, TAU);
        ctx.fill();
        ctx.strokeStyle = '#0a4866';
        ctx.lineWidth = size * 0.035;
        ctx.stroke();
      }
      break;
    }
    case SPECIES.WASTE: {
      // Olive irregular organic fragment
      ctx.beginPath();
      for (let i = 0; i < 7; i++) {
        const a = (TAU * i) / 7;
        const rad = r * (i % 2 === 0 ? 0.88 : 0.62);
        const x = cx + Math.cos(a) * rad;
        const y = cy + Math.sin(a) * rad;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.fillStyle = '#9aa85f';
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#4e592b';
      ctx.stroke();
      break;
    }
    case SPECIES.PHEROMONE: {
      // Soft radial translucent signal puff (tinted by instance color in shader)
      const g = ctx.createRadialGradient(cx, cy, r * 0.06, cx, cy, r * 1.15);
      g.addColorStop(0, 'rgba(255,255,255,0.95)');
      g.addColorStop(0.45, 'rgba(255,255,255,0.55)');
      g.addColorStop(1, 'rgba(255,255,255,0.0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 1.15, 0, TAU);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.65)';
      ctx.lineWidth = size * 0.03;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.72, 0, TAU);
      ctx.stroke();
      break;
    }
    case SPECIES.TOXIN: {
      // Spiked crimson toxin star
      ctx.beginPath();
      for (let i = 0; i < 12; i++) {
        const a = (TAU * i) / 12;
        const rad = i % 2 === 0 ? r * 1.05 : r * 0.48;
        const x = cx + Math.cos(a) * rad;
        const y = cy + Math.sin(a) * rad;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.fillStyle = '#ff425b';
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#6b0c1c';
      ctx.stroke();
      ctx.fillStyle = '#ffd6dc';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.24, 0, TAU);
      ctx.fill();
      break;
    }
    case SPECIES.CARBON: {
      // Linear O=C=O molecule
      ctx.strokeStyle = '#b4c6d8';
      ctx.lineWidth = size * 0.045;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.58, cy);
      ctx.lineTo(cx + r * 0.58, cy);
      ctx.stroke();
      for (const sx of [-1, 1]) {
        ctx.fillStyle = '#e86862';
        ctx.beginPath();
        ctx.arc(cx + sx * r * 0.58, cy, r * 0.27, 0, TAU);
        ctx.fill();
        ctx.lineWidth = size * 0.03;
        ctx.strokeStyle = '#5e1a18';
        ctx.stroke();
      }
      ctx.fillStyle = '#54687a';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.34, 0, TAU);
      ctx.fill();
      ctx.strokeStyle = '#24313d';
      ctx.stroke();
      break;
    }
    case SPECIES.ENZYME: {
      // Pac-man active-cleft pink/violet catalyst
      ctx.fillStyle = '#e866ff';
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.arc(cx, cy, r * 0.92, 0.42, TAU - 0.42);
      ctx.closePath();
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#5c156e';
      ctx.stroke();
      ctx.fillStyle = '#fff0a8';
      ctx.beginPath();
      ctx.arc(cx + r * 0.48, cy, r * 0.18, 0, TAU);
      ctx.fill();
      break;
    }
    case SPECIES.ANTITOXIN: {
      // Teal Y-shaped antibody
      ctx.lineCap = 'round';
      ctx.strokeStyle = '#18635b';
      ctx.lineWidth = size * 0.16;
      ctx.beginPath();
      ctx.moveTo(cx, cy + r * 0.85);
      ctx.lineTo(cx, cy);
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx - r * 0.68, cy - r * 0.68);
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + r * 0.68, cy - r * 0.68);
      ctx.stroke();
      ctx.strokeStyle = '#52f5de';
      ctx.lineWidth = size * 0.1;
      ctx.stroke();
      break;
    }
    case SPECIES.ACID: {
      // Coral H+ radiant diamond
      drawPolygon(ctx, cx, cy, r * 0.9, 4, 0);
      ctx.fillStyle = '#ff6b57';
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#731610';
      ctx.stroke();
      ctx.fillStyle = '#fff3b8';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.25, 0, TAU);
      ctx.fill();
      break;
    }
    case SPECIES.BUFFER: {
      // Mint rounded bicarbonate prism
      drawPolygon(ctx, cx, cy, r * 0.9, 5, -Math.PI / 2);
      ctx.fillStyle = '#5ef2a5';
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#10633b';
      ctx.stroke();
      break;
    }
    case SPECIES.DECOY: {
      // Amber false-lure double crescent
      ctx.fillStyle = '#ffb53d';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.85, 0, TAU);
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#734107';
      ctx.stroke();
      ctx.fillStyle = '#fff5cf';
      drawPolygon(ctx, cx, cy, r * 0.45, 3, -Math.PI / 2);
      ctx.fill();
      break;
    }
    case SPECIES.TAG: {
      // Orange complement C3b Y-tag
      ctx.fillStyle = '#ff9438';
      drawPolygon(ctx, cx, cy, r * 0.88, 3, 0);
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#7a3106';
      ctx.stroke();
      break;
    }
    case SPECIES.PORE: {
      // Perforin magenta barrel ring with dark center channel
      ctx.fillStyle = '#de3875';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.92, 0, TAU);
      ctx.fill();
      ctx.lineWidth = size * 0.045;
      ctx.strokeStyle = '#5c0c2a';
      ctx.stroke();
      ctx.fillStyle = '#290714';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.42, 0, TAU);
      ctx.fill();
      break;
    }
    default: {
      ctx.fillStyle = '#89c4eb';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.72, 0, TAU);
      ctx.fill();
      ctx.lineWidth = size * 0.04;
      ctx.strokeStyle = '#244f70';
      ctx.stroke();
      break;
    }
  }
  ctx.restore();
}

export function drawOrganIcon2D(
  ctx: CanvasRenderingContext2D,
  kind: OrganKind,
  size: number,
  color = ORGAN_COLORS[kind],
): void {
  const cx = size * 0.5;
  const cy = size * 0.5;
  const r = size * 0.34;
  ctx.save();
  ctx.clearRect(0, 0, size, size);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // Soft organ cradle glow
  const g = ctx.createRadialGradient(cx, cy, r * 0.15, cx, cy, r * 1.15);
  g.addColorStop(0, color + '55');
  g.addColorStop(1, color + '00');
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(cx, cy, r * 1.15, 0, TAU);
  ctx.fill();

  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = Math.max(2, size * 0.07);

  switch (kind) {
    case 'propulsion': {
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.85, cy);
      ctx.bezierCurveTo(cx - r * 0.3, cy - r * 0.7, cx + r * 0.3, cy + r * 0.7, cx + r * 0.9, cy);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx - r * 0.75, cy, r * 0.24, 0, TAU);
      ctx.fill();
      break;
    }
    case 'cilia': {
      for (let i = -2; i <= 2; i++) {
        const a = i * 0.34;
        ctx.beginPath();
        ctx.moveTo(cx - r * 0.2, cy + i * r * 0.16);
        ctx.quadraticCurveTo(
          cx + Math.cos(a) * r * 0.45,
          cy + i * r * 0.14 - r * 0.2,
          cx + Math.cos(a) * r * 0.9,
          cy + Math.sin(a) * r * 0.7,
        );
        ctx.stroke();
      }
      break;
    }
    case 'feeding': {
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.82, 0.55, TAU - 0.55);
      ctx.stroke();
      ctx.fillStyle = '#ffe58f';
      ctx.beginPath();
      ctx.arc(cx + r * 0.35, cy, r * 0.22, 0, TAU);
      ctx.fill();
      break;
    }
    case 'photosynthesis': {
      for (let i = 0; i < 3; i++) {
        const yOff = (i - 1) * r * 0.42;
        ctx.beginPath();
        ctx.ellipse(cx, cy + yOff, r * 0.72, r * 0.22, 0, 0, TAU);
        ctx.fill();
      }
      break;
    }
    case 'protection': {
      drawPolygon(ctx, cx, cy, r * 0.88, 6, 0);
      ctx.stroke();
      drawPolygon(ctx, cx, cy, r * 0.5, 6, 0);
      ctx.stroke();
      break;
    }
    case 'toxin': {
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.75, cy + r * 0.5);
      ctx.lineTo(cx, cy - r * 0.88);
      ctx.lineTo(cx + r * 0.75, cy + r * 0.5);
      ctx.closePath();
      ctx.fill();
      break;
    }
    case 'poreforming': {
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.8, 0, TAU);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.32, 0, TAU);
      ctx.fill();
      break;
    }
    case 'sensing':
    case 'hunting':
    case 'family_toward':
    case 'family_away': {
      ctx.beginPath();
      ctx.moveTo(cx, cy + r * 0.75);
      ctx.lineTo(cx, cy - r * 0.2);
      ctx.stroke();
      for (const rad of [0.35, 0.72]) {
        ctx.beginPath();
        ctx.arc(cx, cy - r * 0.2, r * rad, -Math.PI * 0.85, -Math.PI * 0.15);
        ctx.stroke();
      }
      break;
    }
    case 'mitochondrion': {
      ctx.beginPath();
      ctx.ellipse(cx, cy, r * 0.9, r * 0.52, -0.3, 0, TAU);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.55, cy + r * 0.15);
      ctx.lineTo(cx - r * 0.2, cy - r * 0.2);
      ctx.lineTo(cx + r * 0.15, cy + r * 0.2);
      ctx.lineTo(cx + r * 0.5, cy - r * 0.15);
      ctx.stroke();
      break;
    }
    case 'proboscis': {
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.75, cy + r * 0.65);
      ctx.quadraticCurveTo(cx - r * 0.1, cy - r * 0.1, cx + r * 0.85, cy - r * 0.75);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx + r * 0.85, cy - r * 0.75, r * 0.2, 0, TAU);
      ctx.fill();
      break;
    }
    case 'toxin_sac': {
      ctx.beginPath();
      ctx.arc(cx, cy + r * 0.1, r * 0.72, 0, TAU);
      ctx.fillStyle = color + '99';
      ctx.fill();
      ctx.stroke();
      break;
    }
    default: {
      drawPolygon(ctx, cx, cy, r * 0.78, 5, -Math.PI / 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.24, 0, TAU);
      ctx.fill();
      break;
    }
  }

  ctx.restore();
}

const PLANT_PALETTES = [
  { stem: '#1e6e58', twig: '#2e8e6e', frond: 'rgba(68, 198, 134, 0.56)', rim: 'rgba(180, 245, 200, 0.5)' },
  { stem: '#276846', twig: '#469e5d', frond: 'rgba(116, 206, 98, 0.56)', rim: 'rgba(218, 248, 165, 0.5)' },
  { stem: '#1d666e', twig: '#2d9399', frond: 'rgba(66, 200, 192, 0.54)', rim: 'rgba(170, 248, 240, 0.5)' },
  { stem: '#446838', twig: '#6b9444', frond: 'rgba(156, 198, 86, 0.54)', rim: 'rgba(232, 244, 150, 0.5)' },
];

function drawPlantAtlasLayer(form: PlantForm | undefined, formIdx: number, size: number): HTMLCanvasElement {
  const c = makeCanvas(size, size);
  const ctx = c.getContext('2d')!;
  const half = size * 0.5;
  ctx.clearRect(0, 0, size, size);
  if (!form) return c;

  // Map habitat branch coordinates (canonical radius = 100, padded to 132) onto 512x512 atlas
  const scale = size / 270;
  const pal = PLANT_PALETTES[(form.palette + formIdx) % PLANT_PALETTES.length];
  ctx.save();
  ctx.translate(half, half);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  // Soft translucent foliage halo along outer branches first
  for (const br of form.branches) {
    if (br.depth < 1) continue;
    const bx = br.b.x * scale;
    const by = br.b.y * scale;
    const ax = br.a.x * scale;
    const ay = br.a.y * scale;
    const ang = Math.atan2(by - ay, bx - ax);
    const rad = Math.max(2.5, br.r * scale);
    ctx.fillStyle = pal.frond;
    ctx.beginPath();
    if (form.leaf === 'blade') {
      ctx.ellipse(bx, by, rad * 2.6, rad * 1.15, ang, 0, TAU);
    } else if (form.leaf === 'oval') {
      ctx.ellipse(bx, by, rad * 2.0, rad * 1.45, ang, 0, TAU);
    } else {
      ctx.arc(bx, by, rad * 1.65, 0, TAU);
    }
    ctx.fill();
  }

  // Stem & branch strokes ordered root -> tips
  const ordered = form.branches.slice().sort((a, b) => a.depth - b.depth);
  for (const br of ordered) {
    const ax = br.a.x * scale;
    const ay = br.a.y * scale;
    const bx = br.b.x * scale;
    const by = br.b.y * scale;
    const thick = Math.max(2.0, br.r * 2.0 * scale);
    ctx.strokeStyle = br.depth <= 1 ? pal.stem : pal.twig;
    ctx.lineWidth = thick;
    ctx.beginPath();
    ctx.moveTo(ax, ay);
    ctx.lineTo(bx, by);
    ctx.stroke();

    if (br.depth <= 1) {
      ctx.strokeStyle = pal.rim;
      ctx.lineWidth = Math.max(1.0, thick * 0.28);
      ctx.beginPath();
      ctx.moveTo(ax, ay);
      ctx.lineTo(bx, by);
      ctx.stroke();
    }
  }

  // Root node badge matching form.root
  ctx.fillStyle = pal.stem;
  ctx.beginPath();
  ctx.arc(form.root.x * scale, form.root.y * scale, Math.max(4, form.rootRadius * scale), 0, TAU);
  ctx.fill();
  ctx.restore();
  return c;
}

export function generatePlantAtlas(device: GPUDevice, plantForms: PlantForm[]): GPUTexture {
  const plantCanvases: HTMLCanvasElement[] = [];
  for (let f = 0; f < 8; f++) {
    plantCanvases.push(drawPlantAtlasLayer(plantForms[f], f, 512));
  }
  return createMipmappedArrayTexture(device, plantCanvases, 512, 'plantAtlas');
}

export function generateProceduralAtlases(device: GPUDevice, plantForms: PlantForm[]): ProceduralAtlases {
  const speciesDetailedCanvases: HTMLCanvasElement[] = [];
  const speciesSimpleCanvases: HTMLCanvasElement[] = [];
  for (let s = 0; s < SPECIES_COUNT; s++) {
    const dC = makeCanvas(96, 96);
    drawSpeciesIcon2D(dC.getContext('2d')!, s, 96, false);
    speciesDetailedCanvases.push(dC);

    const sC = makeCanvas(96, 96);
    drawSpeciesIcon2D(sC.getContext('2d')!, s, 96, true);
    speciesSimpleCanvases.push(sC);
  }

  const plants = generatePlantAtlas(device, plantForms);

  const organCanvases: HTMLCanvasElement[] = [];
  const organIcons2D = new Map<OrganKind, string>();
  for (const kind of ORGAN_KINDS) {
    const c = makeCanvas(96, 96);
    drawOrganIcon2D(c.getContext('2d')!, kind, 96);
    organCanvases.push(c);
    organIcons2D.set(kind, c.toDataURL());
  }

  const nucleusCanvases: HTMLCanvasElement[] = [];
  for (let f = 0; f < 3; f++) {
    const c = makeCanvas(96, 96);
    const ctx = c.getContext('2d')!;
    const cx = 48;
    const cy = 48;
    const rad = 34;
    ctx.beginPath();
    for (let i = 0; i < 32; i++) {
      const a = (TAU * i) / 32;
      let rx = rad;
      let ry = rad;
      if (f === 0) {
        rx = rad * 1.06;
        ry = rad * 0.91;
      } else if (f === 1) {
        rx = ry = rad * (1 + 0.18 * Math.cos(3 * a));
      } else {
        rx = ry = rad * (1 + 0.16 * Math.cos(2 * a) - 0.12 * Math.cos(a));
      }
      const x = cx + Math.cos(a) * rx;
      const y = cy + Math.sin(a) * ry;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();
    const g = ctx.createRadialGradient(40, 38, 4, 48, 48, 36);
    g.addColorStop(0, '#ffffff');
    g.addColorStop(0.55, '#9fd9ff');
    g.addColorStop(1, '#3b73a8');
    ctx.fillStyle = g;
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(255,255,255,0.6)';
    ctx.stroke();
    nucleusCanvases.push(c);
  }

  const vacuoleCanvases: HTMLCanvasElement[] = [];
  const vacSpecs = [
    { rim: UI_COLORS.vacuoleFoodRim, core: '#ffd359' },
    { rim: UI_COLORS.vacuoleWasteRim, core: '#a1b063' },
    { rim: UI_COLORS.oxygenCyan, core: '#dffcff' },
    { rim: UI_COLORS.carbonSlate, core: '#b6cce0' },
  ];
  for (const spec of vacSpecs) {
    const c = makeCanvas(96, 96);
    const ctx = c.getContext('2d')!;
    const g = ctx.createRadialGradient(38, 36, 4, 48, 48, 34);
    g.addColorStop(0, spec.core);
    g.addColorStop(0.75, spec.rim + 'aa');
    g.addColorStop(1, spec.rim + '22');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(48, 48, 34, 0, TAU);
    ctx.fill();
    ctx.lineWidth = 3.5;
    ctx.strokeStyle = spec.rim;
    ctx.stroke();
    vacuoleCanvases.push(c);
  }

  const sampler = device.createSampler({
    magFilter: 'linear',
    minFilter: 'linear',
    mipmapFilter: 'linear',
    addressModeU: 'clamp-to-edge',
    addressModeV: 'clamp-to-edge',
  });

  return {
    speciesDetailed: createMipmappedArrayTexture(device, speciesDetailedCanvases, 96, 'speciesDetailedAtlas'),
    speciesSimple: createMipmappedArrayTexture(device, speciesSimpleCanvases, 96, 'speciesSimpleAtlas'),
    plants,
    organs: createMipmappedArrayTexture(device, organCanvases, 96, 'organAtlas'),
    nuclei: createMipmappedArrayTexture(device, nucleusCanvases, 96, 'nucleusAtlas'),
    vacuoles: createMipmappedArrayTexture(device, vacuoleCanvases, 96, 'vacuoleAtlas'),
    sampler,
    organIcons2D,
  };
}
