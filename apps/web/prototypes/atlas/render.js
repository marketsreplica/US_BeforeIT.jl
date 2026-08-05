'use strict';
/* ============================================================
 * Flow Atlas — canvas renderer
 * Full-viewport 2D canvas, devicePixelRatio-aware.
 * Draw order: starfield → CB aura → CB–bank link → investment
 * halo → flow edges → particles → nodes → labels.
 * Particles are emitted per-edge at a rate proportional to the
 * flow's nominal value and travel along quadratic curves.
 * ============================================================ */

const Renderer = {
  canvas: null, ctx: null,
  w: 0, h: 0, dpr: 1,
  stars: null,            // offscreen starfield layer
  nodes: {},              // id -> node object (rebuilt every frame; positions/radii animate)
  edges: [],              // rebuilt when a run loads
  particles: [],
  haloParticles: [],
  spriteCache: {},
  time: 0,

  PARTICLE_BUDGET: 240,   // particles/second across all flows
  MAX_PARTICLES: 950,

  init(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.resize();
    window.addEventListener('resize', () => this.resize());
  },

  resize() {
    this.dpr = Math.min(2.5, window.devicePixelRatio || 1);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
    this.buildStars();
  },

  /* ---------- static background: stars + nebula vignette ---------- */
  buildStars() {
    const c = document.createElement('canvas');
    c.width = Math.round(this.w * this.dpr);
    c.height = Math.round(this.h * this.dpr);
    const g = c.getContext('2d');
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    g.fillStyle = '#060a18';
    g.fillRect(0, 0, this.w, this.h);

    // faint nebulae
    const neb = (x, y, r, col) => {
      const grad = g.createRadialGradient(x, y, 0, x, y, r);
      grad.addColorStop(0, col);
      grad.addColorStop(1, 'rgba(0,0,0,0)');
      g.fillStyle = grad;
      g.fillRect(x - r, y - r, r * 2, r * 2);
    };
    neb(this.w * 0.5, this.h * 0.46, Math.max(this.w, this.h) * 0.5, 'rgba(38,58,128,0.16)');
    neb(this.w * 0.15, this.h * 0.85, this.w * 0.35, 'rgba(90,40,120,0.10)');
    neb(this.w * 0.88, this.h * 0.15, this.w * 0.3, 'rgba(20,90,110,0.10)');

    // stars
    const n = Math.round((this.w * this.h) / 6500);
    for (let i = 0; i < n; i++) {
      const x = Math.random() * this.w, y = Math.random() * this.h;
      const r = Math.random() * 1.1 + 0.2;
      const a = Math.random() * 0.5 + 0.08;
      g.fillStyle = `rgba(${180 + Math.random() * 60 | 0},${190 + Math.random() * 50 | 0},255,${a})`;
      g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
    }
    this.stars = c;
  },

  /* ---------- layout: recomputed each frame so sizes animate ---------- */
  layout(S) {
    const { w, h } = this;
    const topPad = 66, bottomPad = 100;
    const availH = h - topPad - bottomPad;
    const cx = w * 0.5;
    const cy = topPad + availH * 0.5;
    const ringR = Math.max(105, Math.min(w * 0.175, availH * 0.26));
    // scale node sizes down with the ring so a small viewport stays readable
    const sizeK = Math.max(0.5, Math.min(1, ringR / 175));
    this.geom = { cx, cy, ringR, topPad, bottomPad, availH, sizeK };

    const nodes = {};
    const d = S.derived;

    // --- 12 sector-group ring nodes: area ~ group GVA this quarter ---
    for (let g = 0; g < GROUP_DEFS.length; g++) {
      const def = GROUP_DEFS[g];
      const ang = -Math.PI / 2 + (g / GROUP_DEFS.length) * Math.PI * 2;
      let share = 1 / 12, gva = 0;
      if (d) {
        share = flowGroupShare(d, { basis: 'gva' }, g, S.tFloat);
        const t0 = Math.max(0, Math.min(d.T1 - 1, Math.floor(S.tFloat)));
        const t1 = Math.min(d.T1 - 1, t0 + 1);
        const f = Math.max(0, Math.min(1, S.tFloat - t0));
        gva = d.groupGVA[t0][g] * (1 - f) + d.groupGVA[t1][g] * f;
      }
      const r = Math.max(9, Math.min(ringR * 0.29, (10 + Math.sqrt(share) * 76) * sizeK));
      nodes[def.id] = {
        id: def.id, kind: 'group', gIdx: g, def,
        x: cx + Math.cos(ang) * ringR, y: cy + Math.sin(ang) * ringR,
        r, color: def.color, share, gva,
        label: def.short,
        sub: (d ? d.groupFirms[g] : 0) + ' firms',
      };
    }

    // --- anchors ---
    const sideDx = Math.min(340, w * 0.26);
    const hhX = Math.max(96, cx - ringR - sideDx);
    const rowX = Math.min(w - 96, cx + ringR + sideDx);
    const ringTop = cy - ringR - 46;
    const ringBot = cy + ringR + 46;
    const govY = Math.max(topPad + 34, (topPad + ringTop) / 2);
    const cbY = Math.min(h - bottomPad - 26, (ringBot + (h - bottomPad)) / 2 + 6);

    const aK = Math.max(0.72, sizeK); // gentle anchor shrink on small screens
    nodes.HH = {
      id: 'HH', kind: 'anchor', x: hhX, y: cy - 10, r: 42 * aK, color: ANCHOR_DEFS.HH.color,
      label: 'HOUSEHOLDS', sub: '5,085 active', sub2: '4,130 inactive', glyph: 'house',
    };
    nodes.GOV = {
      id: 'GOV', kind: 'anchor', x: cx, y: govY, r: 36 * aK, color: ANCHOR_DEFS.GOV.color,
      label: 'GOVERNMENT', sub: 'taxes in · spending out', glyph: 'gov',
    };
    nodes.CB = {
      id: 'CB', kind: 'anchor', x: cx, y: cbY, r: 27 * aK, color: ANCHOR_DEFS.CB.color,
      label: 'CENTRAL BANK',
      sub: d ? 'policy rate ' + fmtPct(sampleSeries(d.D.rate, S.tFloat)) : '',
      glyph: 'euro',
    };
    nodes.BANK = {
      id: 'BANK', kind: 'anchor',
      x: Math.max(150, cx - ringR - sideDx * 0.55), y: Math.min(h - bottomPad - 40, cbY - 26),
      r: 25 * aK, color: ANCHOR_DEFS.BANK.color,
      label: 'BANK', sub: 'credit & deposits', glyph: 'bank',
    };
    nodes.ROW = {
      id: 'ROW', kind: 'anchor', x: rowX, y: cy - 10, r: 38 * aK, color: ANCHOR_DEFS.ROW.color,
      label: 'REST OF WORLD', sub: 'imports · exports', glyph: 'globe',
    };

    // FIRMS pseudo-node = ring centre (used only as an endpoint fallback)
    nodes.FIRMS = { id: 'FIRMS', kind: 'virtual', x: cx, y: cy, r: ringR };
    this.nodes = nodes;
  },

  /* ---------- edges: one sub-edge per (flow, group) or anchor pair ---------- */
  buildEdges(S) {
    this.edges = [];
    this.particles = [];
    this.haloParticles = [];
    const d = S.derived;
    if (!d) return;

    // Bow (perpendicular curvature): money flowing INTO the ring bows one
    // way, money flowing OUT the other, so paired flows don't overlap.
    // HHTAX/BEN both arc through the upper-left corridor at different radii.
    const bows = { CONS: 0.20, WAGES: -0.20, GOV: 0.20, CORP: -0.28, EXP: 0.20, IMP: -0.20, HHTAX: -0.14, BEN: 0.32 };

    for (const flow of FLOW_DEFS) {
      if (flow.id === 'INV') continue; // rendered as halo, not edges
      const firmSide = flow.from === 'FIRMS' || flow.to === 'FIRMS';
      if (firmSide) {
        for (let g = 0; g < GROUP_DEFS.length; g++) {
          // Static-basis groups with ~zero share never light up: skip.
          if (flow.basis !== 'gva' && flowGroupShare(d, flow, g, 0) < 0.0012) continue;
          this.edges.push({
            flow, gIdx: g,
            fromId: flow.from === 'FIRMS' ? GROUP_DEFS[g].id : flow.from,
            toId: flow.to === 'FIRMS' ? GROUP_DEFS[g].id : flow.to,
            bow: bows[flow.id] || 0.2, color: flow.color, acc: Math.random(),
          });
        }
      } else {
        this.edges.push({
          flow, gIdx: null, fromId: flow.from, toId: flow.to,
          bow: bows[flow.id] || 0.3, color: flow.color, acc: Math.random(),
        });
      }
    }
  },

  /* Current nominal value of one sub-edge (model units). */
  edgeValue(S, e, tf) {
    const v = flowValue(S.derived, e.flow.id, tf);
    return e.gIdx == null ? v : v * flowGroupShare(S.derived, e.flow, e.gIdx, tf);
  },

  /* Quadratic-bezier geometry for an edge, from node rims. */
  edgeGeom(e) {
    const a = this.nodes[e.fromId], b = this.nodes[e.toId];
    const dx = b.x - a.x, dy = b.y - a.y;
    const dist = Math.hypot(dx, dy) || 1;
    const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    // control point offset perpendicular to the chord
    const px = -dy / dist, py = dx / dist;
    const c = { x: mx + px * dist * e.bow, y: my + py * dist * e.bow };
    return { p0: { x: a.x, y: a.y }, p1: c, p2: { x: b.x, y: b.y } };
  },

  qPoint(g, u) {
    const w0 = (1 - u) * (1 - u), w1 = 2 * u * (1 - u), w2 = u * u;
    return {
      x: w0 * g.p0.x + w1 * g.p1.x + w2 * g.p2.x,
      y: w0 * g.p0.y + w1 * g.p1.y + w2 * g.p2.y,
    };
  },

  /* ---------- particle sprite cache (soft glow dots) ---------- */
  sprite(color) {
    if (this.spriteCache[color]) return this.spriteCache[color];
    const s = document.createElement('canvas');
    s.width = s.height = 32;
    const g = s.getContext('2d');
    const grad = g.createRadialGradient(16, 16, 0, 16, 16, 16);
    grad.addColorStop(0, '#ffffff');
    grad.addColorStop(0.25, color);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 32, 32);
    this.spriteCache[color] = s;
    return s;
  },

  /* ============================================================
   * draw — one animation frame
   * ============================================================ */
  draw(S, dt) {
    const ctx = this.ctx;
    this.time += dt;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.w, this.h);
    if (this.stars) ctx.drawImage(this.stars, 0, 0, this.w, this.h);

    this.layout(S);
    const d = S.derived;
    const { cx, cy, ringR } = this.geom;
    const tf = S.tFloat;

    /* --- central-bank rate aura: pulse speed & intensity track the policy rate --- */
    const cb = this.nodes.CB;
    if (d) {
      const rate = Math.max(0, sampleSeries(d.D.rate, tf));
      const norm = Math.min(1, rate / 0.05);              // 5% annual = full blast
      const pulse = 0.5 + 0.5 * Math.sin(this.time * (1.2 + norm * 4.5));
      const auraR = cb.r * (2.1 + pulse * 1.1 + norm * 1.4);
      const grad = ctx.createRadialGradient(cb.x, cb.y, cb.r * 0.4, cb.x, cb.y, auraR);
      grad.addColorStop(0, `rgba(126,240,255,${0.10 + norm * 0.22 + pulse * 0.05})`);
      grad.addColorStop(1, 'rgba(126,240,255,0)');
      ctx.fillStyle = grad;
      ctx.beginPath(); ctx.arc(cb.x, cb.y, auraR, 0, Math.PI * 2); ctx.fill();
    }

    /* --- dashed CB → BANK transmission link --- */
    const bank = this.nodes.BANK;
    ctx.save();
    ctx.strokeStyle = 'rgba(126,240,255,0.35)';
    ctx.lineWidth = 1;
    ctx.setLineDash([3, 6]);
    ctx.lineDashOffset = -this.time * 12;                 // slow crawl toward the bank
    ctx.beginPath(); ctx.moveTo(cb.x, cb.y); ctx.lineTo(bank.x, bank.y); ctx.stroke();
    ctx.restore();

    /* --- investment self-loop halo around the firm ring --- */
    if (d) {
      const invV = flowValue(d, 'INV', tf);
      const gdpV = Math.max(1, sampleSeries(d.D.nomGDP, tf));
      const haloR = ringR + 58;
      const intensity = Math.min(1, (invV / gdpV) / 0.35);
      const hovered = S.hover && S.hover.type === 'halo';
      ctx.save();
      ctx.strokeStyle = `rgba(111,168,255,${(hovered ? 0.5 : 0.16) + intensity * 0.12})`;
      ctx.lineWidth = (hovered ? 4 : 2) + intensity * 5;
      ctx.setLineDash([1, 7]);
      ctx.beginPath(); ctx.arc(cx, cy, haloR, 0, Math.PI * 2); ctx.stroke();
      ctx.restore();
      this.haloR = haloR;

      // orbiting investment particles
      const rate = this.PARTICLE_BUDGET * 1.5 * (invV / this.totalFlow(S, tf));
      this.haloAcc = (this.haloAcc || 0) + rate * dt;
      while (this.haloAcc >= 1 && this.haloParticles.length < 160) {
        this.haloAcc -= 1;
        this.haloParticles.push({
          a: Math.random() * Math.PI * 2,
          sp: 0.25 + Math.random() * 0.3,
          life: 0, maxLife: 5 + Math.random() * 4,
          size: 1.2 + Math.random() * 1.4,
        });
      }
      const spr = this.sprite('#6fa8ff');
      ctx.globalCompositeOperation = 'lighter';
      for (let i = this.haloParticles.length - 1; i >= 0; i--) {
        const p = this.haloParticles[i];
        p.a += p.sp * dt; p.life += dt;
        if (p.life > p.maxLife) { this.haloParticles.splice(i, 1); continue; }
        const fade = Math.min(1, p.life * 2, (p.maxLife - p.life) * 2);
        const px = cx + Math.cos(p.a) * haloR, py = cy + Math.sin(p.a) * haloR;
        const s = p.size * 6;
        ctx.globalAlpha = 0.7 * fade;
        ctx.drawImage(spr, px - s / 2, py - s / 2, s, s);
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';
    }

    /* --- flow edges --- */
    if (d) {
      const totalFlow = this.totalFlow(S, tf);
      for (const e of this.edges) {
        const val = this.edgeValue(S, e, tf);
        e.geom = this.edgeGeom(e);
        e.val = val;
        if (val < 2) { e.width = 0; continue; }
        const hovered = S.hover && S.hover.type === 'edge' && S.hover.edge === e;
        const related = S.hover && S.hover.type === 'edge' && S.hover.edge.flow === e.flow;
        e.width = Math.min(11, 0.7 + Math.sqrt(val) / 15);
        ctx.strokeStyle = e.color;
        ctx.globalAlpha = hovered ? 0.85 : related ? 0.45 : 0.24;
        ctx.lineWidth = hovered ? e.width + 1.5 : e.width;
        ctx.beginPath();
        ctx.moveTo(e.geom.p0.x, e.geom.p0.y);
        ctx.quadraticCurveTo(e.geom.p1.x, e.geom.p1.y, e.geom.p2.x, e.geom.p2.y);
        ctx.stroke();

        /* emit particles ∝ flow value (particles always flow; the
           timeline only controls the values they represent) */
        const rate = this.PARTICLE_BUDGET * (val / totalFlow);
        e.acc += rate * dt;
        while (e.acc >= 1 && this.particles.length < this.MAX_PARTICLES) {
          e.acc -= 1;
          this.particles.push({
            e, u: 0,
            dur: 1.5 + Math.random() * 1.3,
            size: 1.0 + Math.random() * 1.4,
            jx: (Math.random() - 0.5) * 3, jy: (Math.random() - 0.5) * 3,
          });
        }
        if (e.acc > 4) e.acc = 4;
      }
      ctx.globalAlpha = 1;

      /* --- particles --- */
      ctx.globalCompositeOperation = 'lighter';
      for (let i = this.particles.length - 1; i >= 0; i--) {
        const p = this.particles[i];
        p.u += dt / p.dur;
        if (p.u >= 1 || !p.e.geom) { this.particles.splice(i, 1); continue; }
        const pt = this.qPoint(p.e.geom, p.u);
        const fade = Math.min(1, p.u * 6, (1 - p.u) * 6);
        const s = p.size * 6;
        ctx.globalAlpha = 0.75 * fade;
        ctx.drawImage(this.sprite(p.e.color), pt.x + p.jx - s / 2, pt.y + p.jy - s / 2, s, s);
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';
    }

    /* --- nodes + labels --- */
    for (const id of Object.keys(this.nodes)) {
      const n = this.nodes[id];
      if (n.kind === 'virtual') continue;
      this.drawNode(n, S);
    }
  },

  totalFlow(S, tf) {
    const d = S.derived;
    let sum = 0;
    for (const f of FLOW_DEFS) sum += flowValue(d, f.id, tf);
    return Math.max(1, sum);
  },

  /* ---------- node rendering ---------- */
  drawNode(n, S) {
    const ctx = this.ctx;
    const hovered = S.hover && S.hover.type === 'node' && S.hover.node.id === n.id;
    const selected = S.selection && S.selection.id === n.id;

    // glow + body
    ctx.save();
    ctx.shadowColor = n.color;
    ctx.shadowBlur = hovered || selected ? 26 : 14;
    const grad = ctx.createRadialGradient(n.x - n.r * 0.3, n.y - n.r * 0.3, n.r * 0.1, n.x, n.y, n.r);
    grad.addColorStop(0, this.shade(n.color, 0.55));
    grad.addColorStop(0.75, this.shade(n.color, 0.16));
    grad.addColorStop(1, this.shade(n.color, 0.08));
    ctx.fillStyle = grad;
    ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2); ctx.fill();
    ctx.restore();

    ctx.strokeStyle = n.color;
    ctx.globalAlpha = hovered || selected ? 0.95 : 0.55;
    ctx.lineWidth = hovered || selected ? 2 : 1.2;
    ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2); ctx.stroke();
    if (selected) {
      ctx.setLineDash([4, 5]);
      ctx.globalAlpha = 0.8;
      ctx.beginPath(); ctx.arc(n.x, n.y, n.r + 6, 0, Math.PI * 2); ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.globalAlpha = 1;

    if (n.glyph) this.drawGlyph(n);

    // labels (dark under-stroke keeps text legible over edges)
    const label = (txt, x, y, size, color, bold) => {
      ctx.font = `${bold ? '700' : '400'} ${size}px -apple-system, system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(4,7,18,0.75)';
      ctx.strokeText(txt, x, y);
      ctx.fillStyle = color;
      ctx.fillText(txt, x, y);
    };
    const ly = n.y + n.r + 14;
    if (n.kind === 'group') {
      label(n.label, n.x, ly, 11, '#e6ecff', true);
      label(n.sub, n.x, ly + 12, 9.5, '#93a0cc', false);
    } else {
      label(n.label, n.x, ly, 11.5, '#eef2ff', true);
      if (n.sub) label(n.sub, n.x, ly + 12, 9.5, '#a3b0dc', false);
      if (n.sub2) label(n.sub2, n.x, ly + 23, 9.5, '#a3b0dc', false);
    }
  },

  /* simple vector glyphs inside anchor nodes */
  drawGlyph(n) {
    const ctx = this.ctx;
    const s = n.r * 0.52;
    ctx.save();
    ctx.translate(n.x, n.y);
    ctx.strokeStyle = 'rgba(240,246,255,0.9)';
    ctx.fillStyle = 'rgba(240,246,255,0.9)';
    ctx.lineWidth = 1.6;
    ctx.lineJoin = 'round';
    switch (n.glyph) {
      case 'house': {
        ctx.beginPath();
        ctx.moveTo(-s, 0); ctx.lineTo(0, -s); ctx.lineTo(s, 0);          // roof
        ctx.moveTo(-s * 0.72, -0.1 * s); ctx.lineTo(-s * 0.72, s * 0.8);
        ctx.lineTo(s * 0.72, s * 0.8); ctx.lineTo(s * 0.72, -0.1 * s);   // walls
        ctx.stroke();
        ctx.strokeRect(-s * 0.2, s * 0.15, s * 0.4, s * 0.65);           // door
        break;
      }
      case 'gov': {
        ctx.beginPath();
        ctx.moveTo(-s, -s * 0.25); ctx.lineTo(0, -s * 0.85); ctx.lineTo(s, -s * 0.25);
        ctx.closePath(); ctx.stroke();                                    // pediment
        for (const fx of [-0.62, 0, 0.62]) {
          ctx.beginPath();
          ctx.moveTo(fx * s, -s * 0.1); ctx.lineTo(fx * s, s * 0.6);
          ctx.stroke();                                                   // columns
        }
        ctx.beginPath(); ctx.moveTo(-s, s * 0.8); ctx.lineTo(s, s * 0.8); ctx.stroke();
        break;
      }
      case 'euro': {
        ctx.font = `700 ${n.r * 1.05}px ${'"SF Mono", Menlo, monospace'}`;
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillText('€', 0, n.r * 0.06);
        break;
      }
      case 'bank': {
        ctx.strokeRect(-s, -s * 0.7, s * 2, s * 1.5);                    // vault box
        ctx.beginPath(); ctx.arc(0, 0.05 * s, s * 0.45, 0, Math.PI * 2); ctx.stroke();
        ctx.beginPath(); ctx.arc(0, 0.05 * s, s * 0.12, 0, Math.PI * 2); ctx.fill();
        break;
      }
      case 'globe': {
        ctx.beginPath(); ctx.arc(0, 0, s, 0, Math.PI * 2); ctx.stroke();
        ctx.beginPath(); ctx.ellipse(0, 0, s * 0.45, s, 0, 0, Math.PI * 2); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(-s, 0); ctx.lineTo(s, 0); ctx.stroke();
        ctx.beginPath(); ctx.ellipse(0, -s * 0.45, s * 0.88, s * 0.45, 0, 0, Math.PI, true); ctx.stroke();
        break;
      }
    }
    ctx.restore();
  },

  /* lighten/darken helper: returns rgba of hex color at given luminance mix */
  shade(hex, mix) {
    const r = parseInt(hex.slice(1, 3), 16), g = parseInt(hex.slice(3, 5), 16), b = parseInt(hex.slice(5, 7), 16);
    return `rgba(${Math.round(r * mix + 10)},${Math.round(g * mix + 14)},${Math.round(b * mix + 30)},0.95)`;
  },

  /* ---------- hit testing (mousemove/click) ---------- */
  hitTest(mx, my) {
    // nodes first
    for (const id of Object.keys(this.nodes)) {
      const n = this.nodes[id];
      if (n.kind === 'virtual') continue;
      if (Math.hypot(mx - n.x, my - n.y) <= n.r + 4) return { type: 'node', node: n };
    }
    // investment halo ring
    if (this.geom && this.haloR) {
      const dc = Math.hypot(mx - this.geom.cx, my - this.geom.cy);
      if (Math.abs(dc - this.haloR) < 9) return { type: 'halo' };
    }
    // edges: nearest sampled point
    let best = null, bestD = 1e9;
    for (const e of this.edges) {
      if (!e.geom || !e.width) continue;
      for (let i = 0; i <= 20; i++) {
        const pt = this.qPoint(e.geom, i / 20);
        const dd = Math.hypot(mx - pt.x, my - pt.y);
        if (dd < bestD) { bestD = dd; best = e; }
      }
    }
    if (best && bestD < Math.max(7, best.width / 2 + 4)) return { type: 'edge', edge: best };
    return null;
  },
};
