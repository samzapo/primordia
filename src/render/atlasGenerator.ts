import { ORGAN_KINDS, type OrganKind } from '../sim/cell.ts';
import { SPECIES, SPECIES_COUNT, TAU } from '../sim/constants.ts';
import type { PlantForm } from '../sim/habitat.ts';
import type { LandmarkKind } from './factoryLayout.ts';
import { ORGAN_COLORS, UI_COLORS } from './palette.ts';

export const LANDMARK_SPRITE_KINDS: readonly LandmarkKind[] = [
  'assembly',
  'chemistry',
  'receptors',
  'bud',
  'atp',
];

export interface ProceduralAtlases {
  speciesDetailed: GPUTexture;
  speciesSimple: GPUTexture;
  plants: GPUTexture;
  organs: GPUTexture;
  nuclei: GPUTexture;
  landmarks: GPUTexture;
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

function mixHexWithWhite(hex: string, amount: number): string {
  const m = hex.replace('#', '');
  const r = parseInt(m.slice(0, 2), 16);
  const g = parseInt(m.slice(2, 4), 16);
  const b = parseInt(m.slice(4, 6), 16);
  const mr = Math.round(r + (255 - r) * amount);
  const mg = Math.round(g + (255 - g) * amount);
  const mb = Math.round(b + (255 - b) * amount);
  return `rgb(${mr}, ${mg}, ${mb})`;
}

function mixHexWithDark(hex: string, amount: number): string {
  const m = hex.replace('#', '');
  const r = parseInt(m.slice(0, 2), 16);
  const g = parseInt(m.slice(2, 4), 16);
  const b = parseInt(m.slice(4, 6), 16);
  const mr = Math.round(r * (1 - amount) + 10 * amount);
  const mg = Math.round(g * (1 - amount) + 20 * amount);
  const mb = Math.round(b * (1 - amount) + 32 * amount);
  return `rgb(${mr}, ${mg}, ${mb})`;
}

export function drawOrganIcon2D(
  ctx: CanvasRenderingContext2D,
  kind: OrganKind,
  size: number,
  color = ORGAN_COLORS[kind],
): void {
  const cx = size * 0.5;
  const cy = size * 0.5;
  const r = size * 0.36;
  const hi = mixHexWithWhite(color, 0.58);
  const mid = color;
  const deep = mixHexWithDark(color, 0.58);
  const ink = 'rgba(9, 20, 32, 0.88)';
  ctx.save();
  ctx.clearRect(0, 0, size, size);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const lw = Math.max(1.8, size * 0.05);

  switch (kind) {
    case 'propulsion': {
      // Kinetosome basal cylinder anchored at membrane (-X) + helical whip flagellum extending +X
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 2.1;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.55, cy);
      ctx.bezierCurveTo(cx - r * 0.05, cy - r * 0.65, cx + r * 0.38, cy + r * 0.65, cx + r * 0.94, cy - r * 0.08);
      ctx.stroke();

      ctx.strokeStyle = mid;
      ctx.lineWidth = lw * 1.25;
      ctx.stroke();

      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.48;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.45, cy - r * 0.04);
      ctx.bezierCurveTo(cx - r * 0.05, cy - r * 0.62, cx + r * 0.38, cy + r * 0.58, cx + r * 0.9, cy - r * 0.09);
      ctx.stroke();

      // Basal body anchor collar
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.75;
      ctx.beginPath();
      ctx.ellipse(cx - r * 0.6, cy, r * 0.28, r * 0.38, 0, 0, TAU);
      ctx.fill();
      ctx.stroke();
      ctx.fillStyle = hi;
      ctx.beginPath();
      ctx.arc(cx - r * 0.58, cy - r * 0.08, r * 0.13, 0, TAU);
      ctx.fill();
      break;
    }
    case 'cilia': {
      // Curved basal plaque at left + 5 flexible motile bristle hairs sweeping +X
      for (let i = -2; i <= 2; i++) {
        const a = i * 0.3;
        const y0 = cy + i * r * 0.16;
        const tx = cx + Math.cos(a) * r * 0.92;
        const ty = cy + Math.sin(a) * r * 0.76;
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 1.35;
        ctx.beginPath();
        ctx.moveTo(cx - r * 0.45, y0);
        ctx.quadraticCurveTo(cx + r * 0.25, y0 - r * 0.22, tx, ty);
        ctx.stroke();

        ctx.strokeStyle = i % 2 === 0 ? hi : mid;
        ctx.lineWidth = lw * 0.72;
        ctx.stroke();

        ctx.fillStyle = '#ffffff';
        ctx.beginPath();
        ctx.arc(tx, ty, lw * 0.34, 0, TAU);
        ctx.fill();
      }
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.7;
      ctx.beginPath();
      ctx.roundRect(cx - r * 0.7, cy - r * 0.48, r * 0.34, r * 0.96, r * 0.15);
      ctx.fill();
      ctx.stroke();
      break;
    }
    case 'feeding': {
      // Cytostome oral groove cup opening +X with golden engulfed nutrient bolus inside gullet
      const grad = ctx.createRadialGradient(cx - r * 0.15, cy, r * 0.1, cx, cy, r * 0.95);
      grad.addColorStop(0, deep);
      grad.addColorStop(0.65, mid);
      grad.addColorStop(1, hi);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.85;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.88, 0.58, TAU - 0.58, false);
      ctx.lineTo(cx + r * 0.28, cy - r * 0.24);
      ctx.quadraticCurveTo(cx - r * 0.38, cy, cx + r * 0.28, cy + r * 0.24);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Pharyngeal ciliary striations inside lip
      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.45;
      for (const ang of [-1.2, 1.2, 2.2, -2.2]) {
        ctx.beginPath();
        ctx.moveTo(cx + Math.cos(ang) * r * 0.48, cy + Math.sin(ang) * r * 0.48);
        ctx.lineTo(cx + Math.cos(ang) * r * 0.74, cy + Math.sin(ang) * r * 0.74);
        ctx.stroke();
      }
      // Captured food speck in oral pocket
      ctx.fillStyle = '#ffd859';
      ctx.strokeStyle = '#6b3b06';
      ctx.lineWidth = lw * 0.45;
      ctx.beginPath();
      ctx.arc(cx + r * 0.42, cy, r * 0.22, 0, TAU);
      ctx.fill();
      ctx.stroke();
      break;
    }
    case 'photosynthesis': {
      // Shaded chloroplast capsule with thylakoid grana stacks & stromal lamellae
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(-0.18);
      const grad = ctx.createLinearGradient(0, -r * 0.8, 0, r * 0.8);
      grad.addColorStop(0, hi);
      grad.addColorStop(0.55, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.8;
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.96);
      ctx.bezierCurveTo(r * 0.74, -r * 0.72, r * 0.74, r * 0.72, 0, r * 0.96);
      ctx.bezierCurveTo(-r * 0.74, r * 0.72, -r * 0.74, -r * 0.72, 0, -r * 0.96);
      ctx.fill();
      ctx.stroke();

      // Stromal lamellae midrib
      ctx.strokeStyle = 'rgba(220, 255, 228, 0.65)';
      ctx.lineWidth = lw * 0.5;
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.72);
      ctx.lineTo(0, r * 0.72);
      ctx.stroke();

      // Stacked thylakoid grana discs
      for (const gy of [-r * 0.4, 0, r * 0.4]) {
        ctx.fillStyle = deep;
        ctx.beginPath();
        ctx.ellipse(0, gy, r * 0.4, r * 0.14, 0, 0, TAU);
        ctx.fill();
        ctx.fillStyle = hi;
        ctx.beginPath();
        ctx.ellipse(0, gy - r * 0.03, r * 0.34, r * 0.07, 0, 0, TAU);
        ctx.fill();
      }
      ctx.restore();
      break;
    }
    case 'protection': {
      // Overlapping curved chitin/cell-wall armor scute plate oriented along membrane tangent
      const grad = ctx.createLinearGradient(cx - r * 0.7, cy, cx + r * 0.7, cy);
      grad.addColorStop(0, deep);
      grad.addColorStop(0.5, hi);
      grad.addColorStop(1, mid);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.82;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.36, cy - r * 0.92);
      ctx.quadraticCurveTo(cx + r * 0.85, cy - r * 0.42, cx + r * 0.68, cy);
      ctx.quadraticCurveTo(cx + r * 0.85, cy + r * 0.42, cx - r * 0.36, cy + r * 0.92);
      ctx.quadraticCurveTo(cx - r * 0.06, cy, cx - r * 0.36, cy - r * 0.92);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Beveled scale ribs & anchor studs
      ctx.strokeStyle = deep;
      ctx.lineWidth = lw * 0.55;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.05, cy - r * 0.45);
      ctx.lineTo(cx + r * 0.45, cy);
      ctx.lineTo(cx - r * 0.05, cy + r * 0.45);
      ctx.stroke();
      for (const ry of [-r * 0.42, 0, r * 0.42]) {
        ctx.fillStyle = hi;
        ctx.beginPath();
        ctx.arc(cx + r * 0.16, cy + ry, lw * 0.35, 0, TAU);
        ctx.fill();
      }
      break;
    }
    case 'toxin': {
      // Bulbous venom gland on left narrowing outward (+X) into hypodermic fang nozzle
      const grad = ctx.createRadialGradient(cx - r * 0.28, cy - r * 0.12, r * 0.08, cx - r * 0.1, cy, r * 0.85);
      grad.addColorStop(0, hi);
      grad.addColorStop(0.55, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.8;
      ctx.beginPath();
      ctx.moveTo(cx + r * 0.98, cy);
      ctx.bezierCurveTo(cx + r * 0.25, cy - r * 0.18, cx + r * 0.1, cy - r * 0.72, cx - r * 0.42, cy - r * 0.62);
      ctx.bezierCurveTo(cx - r * 0.86, cy - r * 0.45, cx - r * 0.86, cy + r * 0.45, cx - r * 0.42, cy + r * 0.62);
      ctx.bezierCurveTo(cx + r * 0.1, cy + r * 0.72, cx + r * 0.25, cy + r * 0.18, cx + r * 0.98, cy);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Venom duct & glowing tip bead
      ctx.strokeStyle = '#ffd2dc';
      ctx.lineWidth = lw * 0.45;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.36, cy);
      ctx.lineTo(cx + r * 0.7, cy);
      ctx.stroke();
      ctx.fillStyle = '#fff0f4';
      ctx.beginPath();
      ctx.arc(cx + r * 0.86, cy, lw * 0.4, 0, TAU);
      ctx.fill();
      break;
    }
    case 'poreforming': {
      // 6-subunit transmembrane perforin rosette barrel around dark pore lumen
      ctx.fillStyle = '#1b0714';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.78, 0, TAU);
      ctx.fill();

      for (let i = 0; i < 6; i++) {
        const a = (TAU * i) / 6;
        const sx = cx + Math.cos(a) * r * 0.56;
        const sy = cy + Math.sin(a) * r * 0.56;
        ctx.fillStyle = i % 2 === 0 ? mid : hi;
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.55;
        ctx.beginPath();
        ctx.arc(sx, sy, r * 0.27, 0, TAU);
        ctx.fill();
        ctx.stroke();
      }
      ctx.fillStyle = '#15040d';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.28, 0, TAU);
      ctx.fill();
      break;
    }
    case 'regenerative': {
      // Twin soothing buffer vesicles + stitched repair cross & effervescent droplets
      for (const sy of [-r * 0.34, r * 0.34]) {
        ctx.fillStyle = mid;
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.72;
        ctx.beginPath();
        ctx.ellipse(cx - r * 0.12, cy + sy, r * 0.52, r * 0.3, 0, 0, TAU);
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = hi;
        ctx.beginPath();
        ctx.arc(cx - r * 0.22, cy + sy - r * 0.06, r * 0.12, 0, TAU);
        ctx.fill();
      }
      // Crisp patch bridge + tiny secreted buffer beads +X
      ctx.strokeStyle = '#ffffff';
      ctx.lineWidth = lw * 0.7;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.12, cy - r * 0.26);
      ctx.lineTo(cx - r * 0.12, cy + r * 0.26);
      ctx.moveTo(cx - r * 0.34, cy);
      ctx.lineTo(cx + r * 0.16, cy);
      ctx.stroke();
      for (const [bx, by] of [[0.58, -0.22], [0.76, 0.1], [0.46, 0.28]]) {
        ctx.fillStyle = hi;
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.42;
        ctx.beginPath();
        ctx.arc(cx + bx * r, cy + by * r, r * 0.15, 0, TAU);
        ctx.fill();
        ctx.stroke();
      }
      break;
    }
    case 'acidifying': {
      // Corrosive proton-pump flask with fiery inner H+ core & directional nozzle (+X)
      const grad = ctx.createRadialGradient(cx - r * 0.2, cy, r * 0.1, cx - r * 0.1, cy, r * 0.72);
      grad.addColorStop(0, '#fff2b8');
      grad.addColorStop(0.5, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      ctx.beginPath();
      ctx.arc(cx - r * 0.22, cy, r * 0.56, 0.42, TAU - 0.42);
      ctx.lineTo(cx + r * 0.9, cy - r * 0.12);
      ctx.lineTo(cx + r * 0.9, cy + r * 0.12);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Inner glowing diamond proton badge
      drawPolygon(ctx, cx - r * 0.2, cy, r * 0.25, 4, 0);
      ctx.fillStyle = '#fff5c8';
      ctx.fill();
      break;
    }
    case 'counterattack': {
      // Armored nematocyst capsule with coiled helical spring & protruding barb (+X)
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      ctx.beginPath();
      ctx.roundRect(cx - r * 0.75, cy - r * 0.55, r * 0.95, r * 1.1, r * 0.35);
      ctx.fill();
      ctx.stroke();

      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.7;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.52, cy);
      ctx.lineTo(cx - r * 0.3, cy - r * 0.28);
      ctx.lineTo(cx - r * 0.08, cy + r * 0.28);
      ctx.lineTo(cx + r * 0.14, cy - r * 0.24);
      ctx.lineTo(cx + r * 0.85, cy);
      ctx.stroke();

      // Retaliatory barb head
      ctx.fillStyle = mid;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.55;
      ctx.beginPath();
      ctx.moveTo(cx + r * 0.96, cy);
      ctx.lineTo(cx + r * 0.46, cy - r * 0.26);
      ctx.lineTo(cx + r * 0.58, cy);
      ctx.lineTo(cx + r * 0.46, cy + r * 0.26);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      break;
    }
    case 'neutralizing': {
      // Antitoxin Gland: teal secretory sac + Y-shaped antibody prong facing outward (+X)
      const grad = ctx.createRadialGradient(cx - r * 0.35, cy, r * 0.08, cx - r * 0.32, cy, r * 0.56);
      grad.addColorStop(0, hi);
      grad.addColorStop(0.55, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      ctx.beginPath();
      ctx.arc(cx - r * 0.36, cy, r * 0.48, 0, TAU);
      ctx.fill();
      ctx.stroke();

      // Projecting Y-shaped neutralizing antibody prong (+X)
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 1.65;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.25, cy);
      ctx.lineTo(cx + r * 0.28, cy);
      ctx.lineTo(cx + r * 0.76, cy - r * 0.44);
      ctx.moveTo(cx + r * 0.28, cy);
      ctx.lineTo(cx + r * 0.76, cy + r * 0.44);
      ctx.stroke();

      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.9;
      ctx.stroke();
      break;
    }
    case 'sensing': {
      // Y-shaped chemoreceptor chalice facing +X cradling golden ligand bead
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 1.9;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.76, cy);
      ctx.lineTo(cx - r * 0.08, cy);
      ctx.moveTo(cx + r * 0.68, cy - r * 0.58);
      ctx.quadraticCurveTo(cx - r * 0.12, cy - r * 0.42, cx - r * 0.08, cy);
      ctx.quadraticCurveTo(cx - r * 0.12, cy + r * 0.42, cx + r * 0.68, cy + r * 0.58);
      ctx.stroke();

      ctx.strokeStyle = mid;
      ctx.lineWidth = lw * 1.1;
      ctx.stroke();

      for (const py of [-r * 0.58, r * 0.58]) {
        ctx.fillStyle = hi;
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.5;
        ctx.beginPath();
        ctx.arc(cx + r * 0.68, cy + py, r * 0.17, 0, TAU);
        ctx.fill();
        ctx.stroke();
      }
      ctx.fillStyle = '#ffe680';
      ctx.beginPath();
      ctx.arc(cx + r * 0.36, cy, r * 0.16, 0, TAU);
      ctx.fill();
      break;
    }
    case 'hunting': {
      // Predatory directional pincer sensor hood aimed +X with glowing amber tracking orb
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.72, cy);
      ctx.quadraticCurveTo(cx - r * 0.25, cy - r * 0.85, cx + r * 0.82, cy - r * 0.42);
      ctx.quadraticCurveTo(cx + r * 0.12, cy - r * 0.36, cx - r * 0.08, cy);
      ctx.quadraticCurveTo(cx + r * 0.12, cy + r * 0.36, cx + r * 0.82, cy + r * 0.42);
      ctx.quadraticCurveTo(cx - r * 0.25, cy + r * 0.85, cx - r * 0.72, cy);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = mid;
      ctx.beginPath();
      ctx.arc(cx + r * 0.2, cy, r * 0.24, 0, TAU);
      ctx.fill();
      ctx.fillStyle = '#fff3b8';
      ctx.beginPath();
      ctx.arc(cx + r * 0.24, cy - r * 0.05, r * 0.1, 0, TAU);
      ctx.fill();
      break;
    }
    case 'family_toward': {
      // Interlocked kinship bond arcs facing +X around luminous warm node
      for (const sgn of [-1, 1]) {
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 1.4;
        ctx.beginPath();
        ctx.arc(cx + r * 0.05, cy + sgn * r * 0.2, r * 0.56, sgn > 0 ? -Math.PI * 0.15 : -Math.PI * 0.85, sgn > 0 ? Math.PI * 0.85 : Math.PI * 0.15);
        ctx.stroke();
        ctx.strokeStyle = mid;
        ctx.lineWidth = lw * 0.82;
        ctx.stroke();
      }
      ctx.fillStyle = hi;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.55;
      ctx.beginPath();
      ctx.arc(cx + r * 0.24, cy, r * 0.24, 0, TAU);
      ctx.fill();
      ctx.stroke();
      break;
    }
    case 'family_away': {
      // Twin repulsion deflector chevron baffles diverging outward along +X
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      for (const offX of [-r * 0.32, r * 0.16]) {
        ctx.beginPath();
        ctx.moveTo(cx + offX - r * 0.2, cy - r * 0.58);
        ctx.lineTo(cx + offX + r * 0.42, cy);
        ctx.lineTo(cx + offX - r * 0.2, cy + r * 0.58);
        ctx.lineTo(cx + offX + r * 0.08, cy);
        ctx.closePath();
        ctx.fillStyle = offX > 0 ? hi : mid;
        ctx.fill();
        ctx.stroke();
      }
      break;
    }
    case 'mitochondrion': {
      // Double-membraned peanut bean with deep outer casing, folded serpentine cristae & golden ATP specks
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(-0.28);
      const grad = ctx.createRadialGradient(-r * 0.2, -r * 0.18, r * 0.08, 0, 0, r * 0.92);
      grad.addColorStop(0, hi);
      grad.addColorStop(0.6, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.8;
      ctx.beginPath();
      ctx.ellipse(0, 0, r * 0.92, r * 0.54, 0, 0, TAU);
      ctx.fill();
      ctx.stroke();

      // Inner matrix & serpentine cristae folds
      ctx.fillStyle = deep;
      ctx.beginPath();
      ctx.ellipse(0, 0, r * 0.74, r * 0.36, 0, 0, TAU);
      ctx.fill();
      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.6;
      ctx.beginPath();
      ctx.moveTo(-r * 0.62, 0);
      ctx.lineTo(-r * 0.42, -r * 0.22);
      ctx.lineTo(-r * 0.22, r * 0.22);
      ctx.lineTo(0, -r * 0.24);
      ctx.lineTo(r * 0.22, r * 0.22);
      ctx.lineTo(r * 0.44, -r * 0.2);
      ctx.lineTo(r * 0.62, 0);
      ctx.stroke();

      // Gold ATP synth speckles
      ctx.fillStyle = '#ffec8b';
      for (const [ax, ay] of [[-0.32, 0], [0.1, -0.05], [0.38, 0.08]]) {
        ctx.beginPath();
        ctx.arc(ax * r, ay * r, lw * 0.34, 0, TAU);
        ctx.fill();
      }
      ctx.restore();
      break;
    }
    case 'proboscis': {
      // Muscular pharyngeal sheath bulb + ringed stylet needle pointing outward (+X)
      ctx.fillStyle = deep;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.78;
      ctx.beginPath();
      ctx.ellipse(cx - r * 0.48, cy, r * 0.4, r * 0.46, 0, 0, TAU);
      ctx.fill();
      ctx.stroke();

      // Stylet shaft & barbed siphon tip
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 1.45;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.22, cy);
      ctx.lineTo(cx + r * 0.88, cy);
      ctx.stroke();
      ctx.strokeStyle = hi;
      ctx.lineWidth = lw * 0.75;
      ctx.stroke();

      ctx.fillStyle = mid;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.5;
      ctx.beginPath();
      ctx.moveTo(cx + r * 0.98, cy);
      ctx.lineTo(cx + r * 0.56, cy - r * 0.24);
      ctx.lineTo(cx + r * 0.68, cy);
      ctx.lineTo(cx + r * 0.56, cy + r * 0.24);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      break;
    }
    case 'toxin_sac': {
      // Bilobed venom storage bladder with constricted sphincter neck (+X) & toxic marble core
      const grad = ctx.createRadialGradient(cx - r * 0.2, cy - r * 0.18, r * 0.08, cx - r * 0.05, cy, r * 0.8);
      grad.addColorStop(0, hi);
      grad.addColorStop(0.55, mid);
      grad.addColorStop(1, deep);
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.8;
      ctx.beginPath();
      ctx.moveTo(cx + r * 0.82, cy - r * 0.14);
      ctx.bezierCurveTo(cx + r * 0.35, cy - r * 0.24, cx + r * 0.18, cy - r * 0.78, cx - r * 0.36, cy - r * 0.68);
      ctx.bezierCurveTo(cx - r * 0.86, cy - r * 0.55, cx - r * 0.86, cy + r * 0.55, cx - r * 0.36, cy + r * 0.68);
      ctx.bezierCurveTo(cx + r * 0.18, cy + r * 0.78, cx + r * 0.35, cy + r * 0.24, cx + r * 0.82, cy + r * 0.14);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();

      // Internal coiled venom reservoir veins & droplets
      ctx.fillStyle = '#ffd1dc';
      ctx.beginPath();
      ctx.arc(cx - r * 0.28, cy - r * 0.18, r * 0.18, 0, TAU);
      ctx.arc(cx - r * 0.06, cy + r * 0.2, r * 0.13, 0, TAU);
      ctx.fill();
      break;
    }
  }

  ctx.restore();
}

export function drawLandmarkIcon2D(
  ctx: CanvasRenderingContext2D,
  kind: LandmarkKind,
  size: number,
): void {
  const cx = size * 0.5;
  const cy = size * 0.5;
  const r = size * 0.36;
  const lw = Math.max(1.8, size * 0.048);
  const ink = 'rgba(10, 22, 36, 0.82)';

  ctx.save();
  ctx.clearRect(0, 0, size, size);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  switch (kind) {
    case 'assembly': {
      // Rough Endoplasmic Reticulum: 3 curved folded cisternae ribbons studded with ribosomes
      const folds = [0.82, 0.52, 0.24];
      for (let idx = 0; idx < folds.length; idx++) {
        const rr = r * folds[idx];
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 1.9;
        ctx.beginPath();
        ctx.arc(cx + r * 0.14, cy + r * 0.1, rr, Math.PI * 0.62, Math.PI * 1.88);
        ctx.stroke();

        ctx.strokeStyle = idx === 0 ? '#7ec8ff' : idx === 1 ? '#57adff' : '#a8deff';
        ctx.lineWidth = lw * 1.15;
        ctx.stroke();
      }
      // Studded ribosomes along ER cisternae
      ctx.fillStyle = '#e2f4ff';
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.4;
      for (const a of [2.1, 2.7, 3.3, 3.9, 4.5, 5.1, 5.6]) {
        const rx = cx + r * 0.14 + Math.cos(a) * r * 0.72;
        const ry = cy + r * 0.1 + Math.sin(a) * r * 0.72;
        ctx.beginPath();
        ctx.arc(rx, ry, r * 0.11, 0, TAU);
        ctx.fill();
        ctx.stroke();
      }
      break;
    }
    case 'chemistry': {
      // Golgi Apparatus: stacked bi-concave cisternae with swollen budding secretory vesicles
      for (let i = -1; i <= 2; i++) {
        const y = cy + (i - 0.5) * r * 0.34;
        const span = r * (0.82 - Math.abs(i - 0.5) * 0.14);
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 1.7;
        ctx.beginPath();
        ctx.moveTo(cx - span, y + r * 0.12);
        ctx.quadraticCurveTo(cx, y - r * 0.22, cx + span, y + r * 0.12);
        ctx.stroke();

        ctx.strokeStyle = i % 2 === 0 ? '#72f0b5' : '#40cc8e';
        ctx.lineWidth = lw * 1.0;
        ctx.stroke();

        // Swollen cisternae ends
        for (const sx of [-1, 1]) {
          ctx.fillStyle = '#9ffad0';
          ctx.strokeStyle = ink;
          ctx.lineWidth = lw * 0.4;
          ctx.beginPath();
          ctx.arc(cx + sx * span, y + r * 0.12, r * 0.12, 0, TAU);
          ctx.fill();
          ctx.stroke();
        }
      }
      // Budding enzyme vesicles
      for (const [bx, by] of [[0.46, -0.58], [-0.52, 0.54], [0.52, 0.5]]) {
        ctx.fillStyle = '#c8ffe6';
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.42;
        ctx.beginPath();
        ctx.arc(cx + bx * r, cy + by * r, r * 0.13, 0, TAU);
        ctx.fill();
        ctx.stroke();
      }
      break;
    }
    case 'receptors': {
      // Centrosome / Signaling Aster: orthogonal barrel centrioles + radiating astral fibers
      ctx.strokeStyle = 'rgba(230, 136, 255, 0.72)';
      ctx.lineWidth = lw * 0.52;
      for (let k = 0; k < 8; k++) {
        const a = (TAU * k) / 8 + 0.2;
        const tx = cx + Math.cos(a) * r * 0.9;
        const ty = cy + Math.sin(a) * r * 0.9;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(tx, ty);
        ctx.stroke();
        ctx.fillStyle = '#f5ccff';
        ctx.beginPath();
        ctx.arc(tx, ty, r * 0.08, 0, TAU);
        ctx.fill();
      }
      // Twin orthogonal centriole barrels
      for (const [ox, oy, ang] of [[-0.14, -0.06, -0.35], [0.16, 0.16, 1.18]]) {
        ctx.save();
        ctx.translate(cx + ox * r, cy + oy * r);
        ctx.rotate(ang);
        ctx.fillStyle = '#e688ff';
        ctx.strokeStyle = ink;
        ctx.lineWidth = lw * 0.65;
        ctx.beginPath();
        ctx.roundRect(-r * 0.34, -r * 0.16, r * 0.68, r * 0.32, r * 0.1);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
      }
      break;
    }
    case 'atp': {
      // ATP Crystal Sac: soft bioenergetic pouch enclosing glowing faceted ATP polyphosphate crystals
      const grad = ctx.createRadialGradient(cx - r * 0.15, cy - r * 0.15, r * 0.05, cx, cy, r * 0.82);
      grad.addColorStop(0, 'rgba(255, 248, 195, 0.92)');
      grad.addColorStop(0.6, 'rgba(255, 206, 86, 0.75)');
      grad.addColorStop(1, 'rgba(220, 136, 26, 0.32)');
      ctx.fillStyle = grad;
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.68;
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.8, 0, TAU);
      ctx.fill();
      ctx.stroke();

      // Faceted ATP star crystals inside sac
      for (const [dx, dy, rad, rot] of [
        [-0.14, -0.04, 0.38, 0.15],
        [0.24, 0.22, 0.26, 0.65],
        [0.22, -0.26, 0.22, 0.4],
      ]) {
        drawPolygon(ctx, cx + dx * r, cy + dy * r, rad * r, 4, rot);
        ctx.fillStyle = '#fff9d1';
        ctx.strokeStyle = '#995c08';
        ctx.lineWidth = lw * 0.45;
        ctx.fill();
        ctx.stroke();
      }
      break;
    }
    case 'bud': {
      // Division Bud: contractile actin ring pinching off a nascent daughter bud with chromatin seed
      ctx.fillStyle = 'rgba(255, 190, 107, 0.65)';
      ctx.strokeStyle = ink;
      ctx.lineWidth = lw * 0.72;
      ctx.beginPath();
      ctx.ellipse(cx - r * 0.16, cy, r * 0.56, r * 0.52, 0, 0, TAU);
      ctx.fill();
      ctx.stroke();

      ctx.beginPath();
      ctx.ellipse(cx + r * 0.42, cy - r * 0.12, r * 0.34, r * 0.32, 0.3, 0, TAU);
      ctx.fillStyle = '#ffd599';
      ctx.fill();
      ctx.stroke();

      // Contractile septum collar ring
      ctx.strokeStyle = '#fff0d6';
      ctx.lineWidth = lw * 0.8;
      ctx.beginPath();
      ctx.ellipse(cx + r * 0.16, cy - r * 0.05, r * 0.11, r * 0.38, -0.25, 0, TAU);
      ctx.stroke();

      // Nascent chromatin seed inside daughter bud
      ctx.fillStyle = '#ff9248';
      ctx.beginPath();
      ctx.arc(cx + r * 0.44, cy - r * 0.12, r * 0.13, 0, TAU);
      ctx.fill();
      break;
    }
    default: {
      ctx.fillStyle = '#9fd9ff';
      ctx.beginPath();
      ctx.arc(cx, cy, r * 0.55, 0, TAU);
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
    g.addColorStop(0, '#eef9ff');
    g.addColorStop(0.55, '#8acaf5');
    g.addColorStop(1, '#265380');
    ctx.fillStyle = g;
    ctx.fill();

    // Porous double nuclear envelope
    ctx.lineWidth = 3.2;
    ctx.setLineDash([7, 3]);
    ctx.strokeStyle = 'rgba(225, 246, 255, 0.72)';
    ctx.stroke();
    ctx.setLineDash([]);

    // Chromatin loop filaments inside nucleoplasm
    ctx.strokeStyle = 'rgba(18, 46, 78, 0.45)';
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    ctx.bezierCurveTo(32, 34, 44, 24, 62, 40);
    ctx.bezierCurveTo(68, 56, 46, 68, 34, 54);
    ctx.stroke();

    // Dense off-center nucleolus body with specular glint
    const ng = ctx.createRadialGradient(42, 41, 1.5, 44, 44, 11);
    ng.addColorStop(0, '#dff4ff');
    ng.addColorStop(0.45, '#4682ba');
    ng.addColorStop(1, '#183757');
    ctx.fillStyle = ng;
    ctx.beginPath();
    ctx.arc(44, 44, 10.5, 0, TAU);
    ctx.fill();

    nucleusCanvases.push(c);
  }

  const landmarkCanvases: HTMLCanvasElement[] = [];
  for (const lKind of LANDMARK_SPRITE_KINDS) {
    const c = makeCanvas(96, 96);
    drawLandmarkIcon2D(c.getContext('2d')!, lKind, 96);
    landmarkCanvases.push(c);
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
    landmarks: createMipmappedArrayTexture(device, landmarkCanvases, 96, 'landmarkAtlas'),
    vacuoles: createMipmappedArrayTexture(device, vacuoleCanvases, 96, 'vacuoleAtlas'),
    sampler,
    organIcons2D,
  };
}
