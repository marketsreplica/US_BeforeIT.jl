/* knobs.js — the parameter rail: rotary dials, grouping, and the knob→circuit
   wiring table (which Sankey links / indicator each knob modulates). */
"use strict";

/* Which part of the machine each knob is wired to.
   links: Sankey link ids that light up (wire-glow) on hover/adjust.
   chip:  'credit'  → the credit-market chip near FIRMS.
   gauge: 'rate'    → the policy-rate gauge card.
   nodes: Sankey node ids to highlight. */
const KNOB_FX = {
  tau_VAT:    { links: ["vat"],      why: "sets the VAT wedge on household spending" },
  tau_INC:    { links: ["inctax"],   why: "sets the income-tax wedge on wages" },
  tau_SIF:    { links: ["socins"],   why: "employer share of the social-insurance wedge" },
  tau_SIW:    { links: ["socins"],   why: "employee share of the social-insurance wedge" },
  tau_FIRM:   { links: ["corptax"],  why: "taxes firm operating surplus" },
  tau_EXPORT: { links: ["exports"],  why: "taxes goods sold abroad" },
  tau_CF:     { links: ["invest"],   why: "taxes capital formation" },
  tau_G:      { links: ["gov"],      why: "taxes government purchases" },
  psi:        { links: ["cons"], nodes: ["HH"], why: "share of household income spent on consumption (rest is saved)" },
  psi_H:      { links: ["invest"], nodes: ["HH"], why: "share of household income invested in housing" },
  theta_UB:   { links: ["benefits"], why: "unemployment benefit as a share of the lost wage" },
  sb_other:   { links: ["benefits"], why: "other social benefits per household" },
  sb_inact:   { links: ["benefits"], why: "benefits per inactive (pensioner) household" },
  w_UB:       { links: ["benefits"], why: "wage base for unemployment benefits" },
  theta_DIV:  { chip: "credit", nodes: ["FIRMS"], why: "share of profits paid out as dividends" },
  mu:         { chip: "credit", why: "bank markup over the policy rate" },
  zeta:       { chip: "credit", why: "bank equity required per unit of loans" },
  zeta_LTV:   { chip: "credit", why: "mortgage loan-to-value cap" },
  zeta_b:     { chip: "credit", why: "how easily failed firms are refinanced" },
  theta:      { chip: "credit", why: "fraction of debt firms repay each quarter" },
  rho:        { gauge: "rate", why: "how slowly the central bank moves its rate" },
  r_star:     { gauge: "rate", why: "the neutral real rate in the Taylor rule" },
  pi_star:    { gauge: "rate", why: "the central bank's inflation target" },
  xi_pi:      { gauge: "rate", why: "Taylor-rule response to inflation" },
  xi_gamma:   { gauge: "rate", why: "Taylor-rule response to growth" },
  r_G:        { gauge: "rate", why: "spread the government pays over the policy rate" },
  r_bar:      { gauge: "rate", why: "policy rate at t=0 (annualized)" },
  omega:      { nodes: ["FIRMS"], why: "initial capacity utilization of firms" },
};

/* Rail grouping (order matters). Keys not listed fall into MISC. */
const KNOB_GROUPS = [
  { title: "TAXES", keys: ["tau_INC", "tau_FIRM", "tau_VAT", "tau_SIF", "tau_SIW", "tau_EXPORT", "tau_CF", "tau_G"] },
  { title: "HOUSEHOLD BEHAVIOR", keys: ["psi", "psi_H", "theta_UB"] },
  { title: "BANKING & CREDIT", keys: ["theta_DIV", "mu", "zeta", "zeta_LTV", "zeta_b", "theta"] },
  { title: "CENTRAL BANK", keys: ["rho", "r_star", "pi_star", "xi_pi", "xi_gamma", "r_G"] },
  { title: "INITIAL CONDITIONS", keys: ["r_bar", "sb_other", "sb_inact", "w_UB", "omega"] },
];

const KnobRail = {
  defs: new Map(),      // key -> knob def from /api/knobs
  vals: {},             // key -> current UI value
  els: new Map(),       // key -> row element
  onChange: null,       // cb(key)
  onHover: null,        // cb(key|null)

  init(knobDefs, { onChange, onHover }) {
    this.onChange = onChange;
    this.onHover = onHover;
    this.defs.clear();
    knobDefs.forEach((d) => { this.defs.set(d.key, d); this.vals[d.key] = d.default; });

    const host = document.getElementById("knob-groups");
    host.innerHTML = "";
    const placed = new Set();
    for (const g of KNOB_GROUPS) {
      const keys = g.keys.filter((k) => this.defs.has(k));
      if (!keys.length) continue;
      host.appendChild(this._groupEl(g.title, keys));
      keys.forEach((k) => placed.add(k));
    }
    const rest = knobDefs.map((d) => d.key).filter((k) => !placed.has(k));
    if (rest.length) host.appendChild(this._groupEl("MISC", rest));
  },

  _groupEl(title, keys) {
    const frag = document.createElement("div");
    const h = document.createElement("div");
    h.className = "kgroup-title";
    h.textContent = title;
    frag.appendChild(h);
    keys.forEach((k) => frag.appendChild(this._knobEl(k)));
    return frag;
  },

  /* Short human label: strip the "(tau_X)" suffix the API includes. */
  _label(d) { return d.label.replace(/\s*\([^)]*\)\s*$/, ""); },

  _knobEl(key) {
    const d = this.defs.get(key);
    const row = document.createElement("div");
    row.className = "knob";
    row.tabIndex = 0;
    row.dataset.key = key;
    const unit = d.unit === "annual" ? "a" : d.unit === "quarterly" ? "q" : "";
    row.innerHTML = `
      <svg class="dial" viewBox="0 0 40 40" aria-hidden="true">
        <path class="track"></path><path class="arc"></path>
        <line class="tick"></line><line class="needle"></line>
        <circle class="hub" cx="20" cy="20" r="5"></circle>
      </svg>
      <div class="kmeta">
        <div class="klabel" title="${this._label(d)}${KNOB_FX[key] && KNOB_FX[key].why ? " — " + KNOB_FX[key].why : ""}">${this._label(d)}</div>
        <div class="kkey">${key}</div>
      </div>
      <div class="kval"><span class="v"></span><span class="kunit">${unit}</span></div>
      <span class="led" title="changed from default"></span>`;
    this.els.set(key, row);
    this._paint(key);
    this._wire(row, key);
    return row;
  },

  /* --- dial geometry: 270° sweep, -135° (min) → +135° (max), 0° = 12 o'clock --- */
  _pt(angDeg, r) {
    const a = (angDeg * Math.PI) / 180;
    return [20 + r * Math.sin(a), 20 - r * Math.cos(a)];
  },
  _arcPath(f0, f1, r) {
    const a0 = -135 + 270 * f0, a1 = -135 + 270 * f1;
    const [x0, y0] = this._pt(a0, r), [x1, y1] = this._pt(a1, r);
    const large = a1 - a0 > 180 ? 1 : 0;
    return `M${x0.toFixed(2)},${y0.toFixed(2)} A${r},${r} 0 ${large} 1 ${x1.toFixed(2)},${y1.toFixed(2)}`;
  },

  _frac(key, v) {
    const d = this.defs.get(key);
    const span = d.max - d.min;
    return span > 0 ? clamp((v - d.min) / span, 0, 1) : 0;   // guard zero-span
  },

  _paint(key) {
    const d = this.defs.get(key);
    const row = this.els.get(key);
    if (!row) return;
    const v = this.vals[key];
    const f = this._frac(key, v);
    const R = 14.5;
    row.querySelector(".track").setAttribute("d", this._arcPath(0, 1, R));
    row.querySelector(".arc").setAttribute("d", f > 0.004 ? this._arcPath(0, f, R) : this._arcPath(0, 0.004, R));
    // default tick mark on outer rim
    const fd = this._frac(key, d.default);
    const aT = -135 + 270 * fd;
    const [tx0, ty0] = this._pt(aT, R + 2.6), [tx1, ty1] = this._pt(aT, R - 1);
    const tick = row.querySelector(".tick");
    tick.setAttribute("x1", tx0); tick.setAttribute("y1", ty0);
    tick.setAttribute("x2", tx1); tick.setAttribute("y2", ty1);
    // needle
    const aN = -135 + 270 * f;
    const [nx, ny] = this._pt(aN, 11);
    const needle = row.querySelector(".needle");
    needle.setAttribute("x1", 20); needle.setAttribute("y1", 20);
    needle.setAttribute("x2", nx); needle.setAttribute("y2", ny);
    row.querySelector(".v").textContent = fmtKnob(v);
    row.classList.toggle("changed", this.isChanged(key));
  },

  isChanged(key) {
    const d = this.defs.get(key);
    return Math.abs(this.vals[key] - d.default) > 1e-9;
  },

  changedOverrides() {
    // Only keys the user actually changed, in UI units, split per contract group.
    const out = { parameters: {}, initial_conditions: {} };
    let n = 0;
    for (const [key, d] of this.defs) {
      if (this.isChanged(key)) {
        const v = clamp(this.vals[key], d.min, d.max);
        out[d.group === "initial_conditions" ? "initial_conditions" : "parameters"][key] = v;
        n++;
      }
    }
    return { overrides: out, count: n };
  },

  set(key, v, quiet) {
    const d = this.defs.get(key);
    if (!d) return;
    this.vals[key] = clamp(v, d.min, d.max);
    this._paint(key);
    if (!quiet && this.onChange) this.onChange(key);
  },

  /* Restore a knob to its API default WITHOUT clamping — some defaults sit
     outside [min,max] (theta_DIV > max, mu < min) and must round-trip exactly,
     otherwise the knob stays "changed" and leaks a clamped override. */
  reset(key) {
    const d = this.defs.get(key);
    if (!d) return;
    this.vals[key] = d.default;
    this._paint(key);
    if (this.onChange) this.onChange(key);
  },

  resetAll() {
    for (const [key, d] of this.defs) { this.vals[key] = d.default; this._paint(key); }
    if (this.onChange) this.onChange(null);
  },

  _wire(row, key) {
    const d = this.defs.get(key);
    const span = d.max - d.min;

    // vertical drag on the whole row: 150px = full range; Shift = fine (÷10)
    row.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      row.setPointerCapture(e.pointerId);
      row.classList.add("dragging");
      let lastY = e.clientY;
      const move = (ev) => {
        const dy = lastY - ev.clientY;
        lastY = ev.clientY;
        const scale = ev.shiftKey ? 1500 : 150;
        this.set(key, this.vals[key] + (dy / scale) * span);
      };
      const up = (ev) => {
        row.classList.remove("dragging");
        row.removeEventListener("pointermove", move);
        row.removeEventListener("pointerup", up);
        row.removeEventListener("pointercancel", up);
        try { row.releasePointerCapture(ev.pointerId); } catch (_) {}
      };
      row.addEventListener("pointermove", move);
      row.addEventListener("pointerup", up);
      row.addEventListener("pointercancel", up);
    });

    row.addEventListener("dblclick", () => this.set(key, d.default));

    row.addEventListener("keydown", (e) => {
      const step = span * (e.shiftKey ? 0.001 : 0.01);
      if (e.key === "ArrowUp" || e.key === "ArrowRight") { this.set(key, this.vals[key] + step); e.preventDefault(); }
      else if (e.key === "ArrowDown" || e.key === "ArrowLeft") { this.set(key, this.vals[key] - step); e.preventDefault(); }
      else if (e.key === "Backspace" || e.key === "Delete") { this.set(key, d.default); e.preventDefault(); }
    });

    row.addEventListener("pointerenter", () => this.onHover && this.onHover(key));
    row.addEventListener("pointerleave", () => this.onHover && this.onHover(null));
    row.addEventListener("focus", () => this.onHover && this.onHover(key));
    row.addEventListener("blur", () => this.onHover && this.onHover(null));
  },
};
