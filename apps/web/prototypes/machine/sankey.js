/* sankey.js — the central monetary circuit.
   A d3-sankey layout re-solved every animation frame from smoothly-lerped link
   values, so widths glide when the quarter changes. All flows are DERIVED
   estimates (contract recipes: run aggregates × knob settings). */
"use strict";

/* Node roster. Left column = money sources this quarter, middle = the firm
   sector where all spending meets production, right = where the money ends up. */
const SK_NODES = [
  { id: "HH",    name: "HOUSEHOLDS" },
  { id: "GOV",   name: "GOVERNMENT" },
  { id: "ROW",   name: "REST OF WORLD" },
  { id: "FIRMS", name: "FIRMS ×652" },
  { id: "HH2",   name: "HOUSEHOLDS′" },
  { id: "GOV2",  name: "GOVERNMENT′" },
  { id: "INV",   name: "INVESTMENT (ret.)" },
  { id: "ROW2",  name: "REST OF WORLD′" },
];

/* Flow roster. fam picks the hue; pos places the value label along the path
   (staggered so parallel HH→GOV′ wedges don't collide). */
const SK_FLOWS = [
  { id: "cons",     s: "HH",    t: "FIRMS", fam: "spend",    name: "Consumption",       pos: 0.42, recipe: "real_household_consumption × deflator" },
  { id: "gov",      s: "GOV",   t: "FIRMS", fam: "spend",    name: "Gov purchases",     pos: 0.40, recipe: "real_government_consumption × deflator" },
  { id: "exports",  s: "ROW",   t: "FIRMS", fam: "trade",    name: "Exports",           pos: 0.45, recipe: "real_exports × deflator" },
  { id: "wages",    s: "FIRMS", t: "HH2",   fam: "distrib",  name: "Wages",             pos: 0.50, recipe: "wages (nominal, from run)" },
  { id: "imports",  s: "FIRMS", t: "ROW2",  fam: "trade",    name: "Imports",           pos: 0.78, recipe: "real_imports × deflator" },
  { id: "corptax",  s: "FIRMS", t: "GOV2",  fam: "tax",      name: "Corporate tax",     pos: 0.30, recipe: "tau_FIRM × max(0, nominal GDP − wages)" },
  { id: "invest",   s: "FIRMS", t: "INV",   fam: "invest",   name: "Investment",        pos: 0.42, recipe: "real_fixed_capitalformation × deflator (retained in the firm sector)" },
  { id: "vat",      s: "HH",    t: "GOV2",  fam: "tax",      name: "VAT",               pos: 0.20, recipe: "tau_VAT × consumption" },
  { id: "inctax",   s: "HH",    t: "GOV2",  fam: "tax",      name: "Income tax",        pos: 0.38, recipe: "tau_INC × wages" },
  { id: "socins",   s: "HH",    t: "GOV2",  fam: "tax",      name: "Social insurance",  pos: 0.82, recipe: "(tau_SIF + tau_SIW) × wages" },
  { id: "benefits", s: "GOV",   t: "HH2",   fam: "transfer", name: "Social benefits",   pos: 0.72, recipe: "(sb_inact×4130 + sb_other×9215) × deflator" },
];

const FAM_COLOR = {
  spend:    "#e08a3c",
  tax:      "#e06060",
  transfer: "#45c9a5",
  trade:    "#6b9bd9",
  invest:   "#d9c05b",
};

/* "wages" is a distribution back to households — copper family too but a touch lighter */
FAM_COLOR.distrib = "#e8a866";

const Sankey = {
  svg: null, gLinks: null, gNodes: null,
  target: {},        // link id -> target value
  shown: {},         // link id -> displayed (lerped) value
  linkEls: new Map(),
  nodeEls: new Map(),
  firmsRect: null,   // for the credit-chip anchor
  _raf: 0, _lastTs: 0, _labelTs: 0,
  W: 940, H: 520,
  onFirmsHover: null,   // cb(bool, evt) → main shows sector-group breakdown tip

  init() {
    this.svg = d3.select("#sankey");
    this.svg.selectAll("*").remove();
    const defs = this.svg.append("defs");
    const grad = defs.append("linearGradient")
      .attr("id", "nodeMetal").attr("x1", 0).attr("y1", 0).attr("x2", 0).attr("y2", 1);
    grad.append("stop").attr("offset", "0%").attr("stop-color", "#3a3f4a");
    grad.append("stop").attr("offset", "45%").attr("stop-color", "#262b34");
    grad.append("stop").attr("offset", "100%").attr("stop-color", "#1b1f26");

    this.gLinks = this.svg.append("g");
    this.gNodes = this.svg.append("g");

    // build persistent DOM for links & nodes (layout only mutates attributes)
    for (const f of SK_FLOWS) {
      const g = this.gLinks.append("g")
        .attr("class", "s-link")
        .attr("data-id", f.id)
        .style("color", FAM_COLOR[f.fam]);
      g.append("path").attr("class", "base").attr("stroke", FAM_COLOR[f.fam]);
      g.append("path").attr("class", "pulse").attr("stroke", FAM_COLOR[f.fam]);
      const lbl = g.append("text").attr("class", "lbl");
      lbl.append("tspan").attr("class", "ln").text(f.name + " ");
      lbl.append("tspan").attr("class", "lv");
      this.linkEls.set(f.id, g);
      g.on("pointermove", (ev) => this._tip(ev, f))
       .on("pointerleave", () => this._tipHide());
    }
    for (const n of SK_NODES) {
      const g = this.gNodes.append("g").attr("class", "s-node").attr("data-id", n.id);
      g.append("rect").attr("rx", 3).attr("fill", "url(#nodeMetal)");
      g.append("text").attr("class", "n-name").text(n.name);
      g.append("text").attr("class", "n-val");
      this.nodeEls.set(n.id, g);
      if (n.id === "FIRMS") {
        g.style("cursor", "help")
         .on("pointermove", (ev) => this.onFirmsHover && this.onFirmsHover(true, ev))
         .on("pointerleave", () => this.onFirmsHover && this.onFirmsHover(false, null));
      }
    }

    this.layout = d3.sankey()
      .nodeId((d) => d.id)
      .nodeWidth(16)
      .nodePadding(30)
      .nodeSort(null)     // keep our input order → stable animation
      .linkSort(null)
      .extent([[130, 18], [this.W - 150, this.H - 14]]);

    this._loop = this._loop.bind(this);
    this._raf = requestAnimationFrame(this._loop);
  },

  /** Set new target values; widths glide there. immediate=true snaps (first load). */
  update(values, immediate) {
    for (const f of SK_FLOWS) {
      const v = Math.max(1, Number.isFinite(values[f.id]) ? values[f.id] : 0); // floor: keep wires visible & sankey solvable
      this.target[f.id] = v;
      if (immediate || !Number.isFinite(this.shown[f.id])) this.shown[f.id] = v;
    }
    if (immediate) this._render();
  },

  _loop(ts) {
    const dt = Math.min(64, ts - (this._lastTs || ts));
    this._lastTs = ts;
    let moving = false;
    const k = 1 - Math.exp(-dt / 180);          // exp smoothing ≈ 180 ms time-constant
    for (const f of SK_FLOWS) {
      const t = this.target[f.id], s = this.shown[f.id];
      if (!Number.isFinite(t) || !Number.isFinite(s)) continue;
      const d = t - s;
      if (Math.abs(d) > Math.max(0.5, t * 0.0005)) {
        this.shown[f.id] = s + d * k;
        moving = true;
      } else {
        this.shown[f.id] = t;
      }
    }
    if (moving) this._render(ts);
    this._raf = requestAnimationFrame(this._loop);
  },

  _render(ts) {
    if (!Number.isFinite(this.target[SK_FLOWS[0].id])) return;
    const graph = this.layout({
      nodes: SK_NODES.map((n) => ({ id: n.id })),
      links: SK_FLOWS.map((f) => ({ source: f.s, target: f.t, value: this.shown[f.id], fid: f.id })),
    });
    const pathGen = d3.sankeyLinkHorizontal();

    for (const l of graph.links) {
      const g = this.linkEls.get(l.fid);
      const d = pathGen(l);
      const w = Math.max(1, l.width);
      g.select(".base").attr("d", d).attr("stroke-width", w);
      g.select(".pulse").attr("d", d);
    }
    for (const n of graph.nodes) {
      const g = this.nodeEls.get(n.id);
      const h = Math.max(4, n.y1 - n.y0);
      g.select("rect")
        .attr("x", n.x0).attr("y", n.y0)
        .attr("width", n.x1 - n.x0).attr("height", h);
      const mid = n.y0 + h / 2;
      const leftSide = n.x0 < this.W / 2;
      const name = g.select(".n-name"), val = g.select(".n-val");
      if (n.id === "FIRMS") {
        name.attr("x", (n.x0 + n.x1) / 2).attr("y", n.y0 - 22).attr("text-anchor", "middle");
        val.attr("x", (n.x0 + n.x1) / 2).attr("y", n.y0 - 10).attr("text-anchor", "middle");
        this.firmsRect = { x0: n.x0, x1: n.x1, y0: n.y0, y1: n.y1 };
      } else if (leftSide) {
        name.attr("x", n.x0 - 8).attr("y", mid - 3).attr("text-anchor", "end");
        val.attr("x", n.x0 - 8).attr("y", mid + 9).attr("text-anchor", "end");
      } else {
        name.attr("x", n.x1 + 8).attr("y", mid - 3).attr("text-anchor", "start");
        val.attr("x", n.x1 + 8).attr("y", mid + 9).attr("text-anchor", "start");
      }
      val.text(fmtMoney(n.value));
    }

    // link value labels along the path — throttled (getPointAtLength is not free)
    if (!ts || ts - this._labelTs > 90) {
      this._labelTs = ts || 0;
      for (const f of SK_FLOWS) {
        const g = this.linkEls.get(f.id);
        const p = g.select(".base").node();
        try {
          const L = p.getTotalLength();
          const pt = p.getPointAtLength(L * f.pos);
          g.select(".lbl")
            .attr("x", pt.x).attr("y", pt.y + 3)
            .attr("text-anchor", "middle");
          g.select(".lv").text(fmtMoney(this.shown[f.id]));
        } catch (_) { /* path not ready yet */ }
      }
      this._positionChip();
    }
  },

  /* pin the credit-market chip just above the FIRMS node (svg → css coords) */
  _positionChip() {
    const chip = document.getElementById("credit-chip");
    const svgEl = this.svg.node();
    if (!chip || !svgEl || !this.firmsRect) return;
    const box = svgEl.getBoundingClientRect();
    const sx = box.width / this.W, sy = box.height / this.H;
    // svg is centered with xMidYMid meet — compute the uniform scale + offsets
    const s = Math.min(sx, sy);
    const ox = (box.width - this.W * s) / 2, oy = (box.height - this.H * s) / 2;
    const x = ox + ((this.firmsRect.x0 + this.firmsRect.x1) / 2) * s;
    const y = oy + this.firmsRect.y1 * s + 8;
    chip.style.left = `${x}px`;
    chip.style.top = `${y}px`;
    chip.style.transform = "translateX(-50%)";
  },

  /** Wire-glow: light the given link ids (and dim the rest). */
  highlight(linkIds, nodeIds) {
    const any = (linkIds && linkIds.length) || (nodeIds && nodeIds.length);
    this.svg.classed("dimmed", !!(linkIds && linkIds.length));
    for (const [id, g] of this.linkEls) g.classed("glow", !!(linkIds && linkIds.includes(id)));
    for (const [id, g] of this.nodeEls) g.classed("hl", !!(nodeIds && nodeIds.includes(id)));
    return any;
  },

  _tip(ev, f) {
    const tip = document.getElementById("flow-tip");
    const wrap = document.getElementById("sankey-wrap");
    const r = wrap.getBoundingClientRect();
    tip.innerHTML =
      `<div class="fam" style="color:${FAM_COLOR[f.fam]}">${f.fam}</div>` +
      `<b>${f.name}</b> — ${fmtMoney(this.shown[f.id])} this quarter<br>` +
      `<span class="recipe">= ${f.recipe}</span><br>` +
      `<span class="dnote">derived estimate, not direct model output</span>`;
    tip.hidden = false;
    const x = clamp(ev.clientX - r.left + 14, 0, r.width - 270);
    const y = clamp(ev.clientY - r.top + 12, 0, r.height - 90);
    tip.style.left = x + "px";
    tip.style.top = y + "px";
  },
  _tipHide() { document.getElementById("flow-tip").hidden = true; },
};
