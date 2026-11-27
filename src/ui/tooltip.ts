export interface HoldTooltipInfo {
  title: string;
  subtitle?: string;
  body: string;
}

class HoldTooltipManager {
  private tipEl: HTMLDivElement | null = null;
  private titleEl!: HTMLDivElement;
  private subEl!: HTMLDivElement;
  private bodyEl!: HTMLDivElement;
  private autoHideTimer: number | null = null;
  private globalListenersBound = false;

  private ensureDom(): HTMLDivElement {
    if (this.tipEl && this.tipEl.isConnected) return this.tipEl;
    const parent = document.getElementById('hud') ?? document.body;
    const tip = document.createElement('div');
    tip.className = 'hold-tooltip hud-panel';
    tip.hidden = true;
    tip.setAttribute('role', 'tooltip');

    this.titleEl = document.createElement('div');
    this.titleEl.className = 'hold-tooltip-title';
    this.subEl = document.createElement('div');
    this.subEl.className = 'hold-tooltip-sub';
    this.bodyEl = document.createElement('div');
    this.bodyEl.className = 'hold-tooltip-body';

    tip.append(this.titleEl, this.subEl, this.bodyEl);
    parent.appendChild(tip);
    this.tipEl = tip;

    if (!this.globalListenersBound) {
      this.globalListenersBound = true;
      window.addEventListener(
        'pointerdown',
        () => {
          this.hide();
        },
        { capture: true },
      );
      window.addEventListener('blur', () => {
        activePointerHolds = 0;
        this.hide();
      });
      window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') this.hide();
      });
    }
    return tip;
  }

  clearAutoHide(): void {
    if (this.autoHideTimer !== null) {
      window.clearTimeout(this.autoHideTimer);
      this.autoHideTimer = null;
    }
  }

  scheduleAutoHide(ms = 2800): void {
    this.clearAutoHide();
    this.autoHideTimer = window.setTimeout(() => {
      this.hide();
    }, ms);
  }

  showForElement(anchor: HTMLElement, info: HoldTooltipInfo): void {
    this.clearAutoHide();
    const tip = this.ensureDom();
    this.titleEl.textContent = info.title;
    if (info.subtitle) {
      this.subEl.textContent = info.subtitle;
      this.subEl.hidden = false;
    } else {
      this.subEl.hidden = true;
    }
    this.bodyEl.textContent = info.body;
    tip.hidden = false;

    const aRect = anchor.getBoundingClientRect();
    const tRect = tip.getBoundingClientRect();
    const tipW = Math.max(180, tRect.width || 250);
    const tipH = Math.max(54, tRect.height || 84);
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    let x = aRect.left + aRect.width * 0.5 - tipW * 0.5;
    x = Math.max(10, Math.min(vw - tipW - 10, x));

    let y = aRect.top - tipH - 12;
    if (y < 10) {
      y = aRect.bottom + 12;
    }
    if (y + tipH > vh - 10) {
      y = Math.max(10, aRect.top - tipH - 12);
    }
    y = Math.max(10, Math.min(vh - tipH - 10, y));

    tip.style.left = `${Math.round(x)}px`;
    tip.style.top = `${Math.round(y)}px`;
  }

  hide(): void {
    this.clearAutoHide();
    if (this.tipEl) {
      this.tipEl.hidden = true;
    }
  }
}

const tooltipMgr = new HoldTooltipManager();
let activePointerHolds = 0;

export function hasPendingHoldTooltip(): boolean {
  return activePointerHolds > 0;
}

export function hideHoldTooltip(): void {
  tooltipMgr.hide();
}

export function bindHoldTooltip<T extends HTMLElement>(
  el: T,
  getInfo: () => HoldTooltipInfo | null,
): T {
  el.classList.add('has-hold-tooltip');
  let holdTimer: number | null = null;
  let hoverTimer: number | null = null;
  let downX = 0;
  let downY = 0;
  let pressing = false;
  let holdFired = false;
  let suppressClickUntil = 0;

  const clearHold = () => {
    if (holdTimer !== null) {
      window.clearTimeout(holdTimer);
      holdTimer = null;
    }
  };
  const clearHover = () => {
    if (hoverTimer !== null) {
      window.clearTimeout(hoverTimer);
      hoverTimer = null;
    }
  };

  el.addEventListener(
    'click',
    (e) => {
      if (performance.now() < suppressClickUntil) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        suppressClickUntil = 0;
      }
    },
    { capture: true },
  );

  el.addEventListener('contextmenu', (e) => {
    if (holdTimer !== null || holdFired || pressing) {
      e.preventDefault();
    }
  });

  el.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    clearHover();
    clearHold();
    holdFired = false;
    if (!pressing) {
      pressing = true;
      activePointerHolds++;
    }
    downX = e.clientX;
    downY = e.clientY;
    holdTimer = window.setTimeout(() => {
      holdTimer = null;
      if (!el.isConnected) return;
      const info = getInfo();
      if (!info) return;
      holdFired = true;
      suppressClickUntil = performance.now() + 1200;
      tooltipMgr.showForElement(el, info);
    }, 380);
  });

  el.addEventListener('pointermove', (e) => {
    if (holdTimer !== null && Math.hypot(e.clientX - downX, e.clientY - downY) > 10) {
      clearHold();
    }
  });

  const finishPress = () => {
    clearHold();
    if (pressing) {
      pressing = false;
      activePointerHolds = Math.max(0, activePointerHolds - 1);
    }
    if (holdFired) {
      suppressClickUntil = performance.now() + 450;
      tooltipMgr.scheduleAutoHide(2800);
      holdFired = false;
    }
  };

  el.addEventListener('pointerup', finishPress);
  el.addEventListener('pointercancel', finishPress);

  el.addEventListener('pointerenter', (e) => {
    if (e.pointerType !== 'mouse') return;
    clearHover();
    hoverTimer = window.setTimeout(() => {
      hoverTimer = null;
      const info = getInfo();
      if (info) tooltipMgr.showForElement(el, info);
    }, 680);
  });

  el.addEventListener('pointerleave', (e) => {
    clearHover();
    if (e.pointerType === 'mouse' && !holdFired) {
      tooltipMgr.hide();
    }
  });

  return el;
}
