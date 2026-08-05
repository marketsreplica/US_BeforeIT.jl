/* gauges.js — right rail: small-multiple output charts (mean ± σ band) with a
   shared time cursor synced to the Sankey scrubber. */
"use strict";

/* Gauge roster. get(summary, i) → value at quarter index i (NaN allowed).
   std(summary, i) → σ at i (NaN → no band segment). */
const GAUGE_DEFS = [
  {
    id: "gdp", name: "REAL GDP",
    get: (s, i) => at(s.real_gdp.mean, i),
    std: (s, i) => at(s.real_gdp.std, i),
    fmt: fmtMoney,
  },
  {
    id: "infl", name: "INFLATION YoY",
    // YoY from the GDP deflator; first 4 quarters fall back to annualized q/q.
    get: (s, i) => {
      const d = s.gdp_deflator.mean;
      const di = at(d, i);
      if (!Number.isFinite(di)) return NaN;
      if (i >= 4) {
        const prev = at(d, i - 4);
        return Number.isFinite(prev) && prev !== 0 ? di / prev - 1 : NaN;
      }
      if (i >= 1) {
        const prev = at(d, i - 1);
        return Number.isFinite(prev) && prev !== 0 ? Math.pow(di / prev, 4) - 1 : NaN;
      }
      return NaN;
    },
    std: () => NaN,
    fmt: (v) => fmtPct(v, 2),
    zero: true,
  },
  {
    id: "rate", name: "POLICY RATE (annual)",
    get: (s, i) => at(s.euribor_annual.mean, i),
    std: (s, i) => at(s.euribor_annual.std, i),
    fmt: (v) => fmtPct(v, 2),
  },
  {
    id: "wages", name: "WAGE BILL (nominal)",
    get: (s, i) => at(s.wages.mean, i),
    std: (s, i) => at(s.wages.std, i),
    fmt: fmtMoney,
  },
  {
    id: "trade", name: "TRADE BALANCE (real)",
    get: (s, i) => {
      const x = at(s.real_exports.mean, i), m = at(s.real_imports.mean, i);
      return Number.isFinite(x) && Number.isFinite(m) ? x - m : NaN;
    },
    std: (s, i) => {
      // crude combined σ: sqrt(σx² + σm²); NaN-safe
      const a = at(s.real_exports.std, i), b = at(s.real_imports.std, i);
      return Number.isFinite(a) && Number.isFinite(b) ? Math.hypot(a, b) : NaN;
    },
    fmt: fmtMoney,
    zero: true,
  },
];

const Gauges = {
  summary: null, cursor: 0,
  els: new Map(),   // id -> {card, svg, valEl}
  VW: 256, VH: 56,

  init() {
    const host = document.getElementById("gauges");
    host.innerHTML = "";
    this.els.clear();
    for (const g of GAUGE_DEFS) {
      const card = document.createElement("div");
      card.className = "gauge";
      card.dataset.g = g.id;
      card.innerHTML = `
        <div class="g-head"><span class="g-name">${g.name}</span><span class="g-val mono">—</span></div>
        <svg viewBox="0 0 ${this.VW} ${this.VH}" preserveAspectRatio="none"></svg>`;
      host.appendChild(card);
      this.els.set(g.id, { card, svg: card.querySelector("svg"), valEl: card.querySelector(".g-val") });
    }
  },

  setData(summary) { this.summary = summary; this.redraw(); },

  setCursor(i) {
    this.cursor = i;
    this.redraw();   // cheap: 5 tiny SVGs
  },

  highlight(id, on) {
    const e = this.els.get(id);
    if (e) e.card.classList.toggle("hl", !!on);
  },

  redraw() {
    const s = this.summary;
    if (!s) return;
    const n = s.periods.length;
    const fcIdx = s.periods.indexOf(s.forecast_start_period);

    for (const g of GAUGE_DEFS) {
      const e = this.els.get(g.id);
      const vals = [], stds = [];
      for (let i = 0; i < n; i++) { vals.push(g.get(s, i)); stds.push(g.std(s, i)); }

      // scale over finite mean±σ
      let lo = Infinity, hi = -Infinity;
      for (let i = 0; i < n; i++) {
        if (!Number.isFinite(vals[i])) continue;
        const sd = Number.isFinite(stds[i]) ? stds[i] : 0;
        lo = Math.min(lo, vals[i] - sd);
        hi = Math.max(hi, vals[i] + sd);
      }
      if (!Number.isFinite(lo) || !Number.isFinite(hi)) { e.svg.innerHTML = ""; e.valEl.textContent = "—"; continue; }
      if (g.zero) { lo = Math.min(lo, 0); hi = Math.max(hi, 0); }
      if (hi - lo < 1e-12) { hi = lo + 1; }            // flat series guard
      const pad = (hi - lo) * 0.08;
      lo -= pad; hi += pad;

      const X = (i) => (i / Math.max(1, n - 1)) * (this.VW - 4) + 2;
      const Y = (v) => this.VH - 4 - ((v - lo) / (hi - lo)) * (this.VH - 8);

      // σ band: contiguous finite segments only (std arrays may contain nulls)
      let bands = "";
      let seg = [];
      const flush = () => {
        if (seg.length > 1) {
          const up = seg.map(([i, v, sd]) => `${X(i)},${Y(v + sd)}`).join(" ");
          const dn = seg.slice().reverse().map(([i, v, sd]) => `${X(i)},${Y(v - sd)}`).join(" ");
          bands += `<polygon class="g-band" points="${up} ${dn}"/>`;
        }
        seg = [];
      };
      for (let i = 0; i < n; i++) {
        if (Number.isFinite(vals[i]) && Number.isFinite(stds[i])) seg.push([i, vals[i], stds[i]]);
        else flush();
      }
      flush();

      // mean line: break on NaN
      let dAttr = "", pen = false;
      for (let i = 0; i < n; i++) {
        if (Number.isFinite(vals[i])) {
          dAttr += `${pen ? "L" : "M"}${X(i).toFixed(1)},${Y(vals[i]).toFixed(1)}`;
          pen = true;
        } else pen = false;
      }

      const zeroLine = g.zero && lo < 0 && hi > 0 ? `<line class="g-zero" x1="0" x2="${this.VW}" y1="${Y(0)}" y2="${Y(0)}"/>` : "";
      const fcLine = fcIdx > 0 ? `<line class="g-fc" x1="${X(fcIdx)}" x2="${X(fcIdx)}" y1="2" y2="${this.VH - 2}"/>` : "";
      const ci = clamp(this.cursor, 0, n - 1);
      const cv = vals[ci];
      const cursor = `<line class="g-cursor" x1="${X(ci)}" x2="${X(ci)}" y1="2" y2="${this.VH - 2}"/>` +
        (Number.isFinite(cv) ? `<circle class="g-dot" cx="${X(ci)}" cy="${Y(cv)}" r="2.5"/>` : "");

      e.svg.innerHTML = `${zeroLine}${fcLine}${bands}<path class="g-line" d="${dAttr}"/>${cursor}`;
      e.valEl.textContent = g.fmt(cv);
      e.valEl.classList.toggle("neg", Number.isFinite(cv) && cv < 0);
    }
  },
};
