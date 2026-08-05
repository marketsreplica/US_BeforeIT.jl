/* phases.js — Tab 2: the 15 phases of one simulated quarter (src/one_step.jl),
   rendered as an animated vertical pipeline. Teaches HOW the machine cycles. */
"use strict";

/* Minimal geometric agent icons (inline SVG, stroke = currentColor). */
const AGENT_ICONS = {
  firm: { title: "firm", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M2 14V7l4 2V7l4 2V7l4 2v5H2z"/><path d="M3.5 7V3.5h2V7"/></svg>` },
  household: { title: "household", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="4.6" r="2.3"/><path d="M3.5 14c.6-3 2.3-4.5 4.5-4.5S12 11 12.5 14"/></svg>` },
  bank: { title: "commercial bank", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M2 6l6-3.5L14 6"/><path d="M3.5 6v6M6.5 6v6M9.5 6v6M12.5 6v6"/><path d="M2 13.5h12"/></svg>` },
  cb: { title: "central bank", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="8" r="5.6"/><path d="M8 4.5v3.5l2.4 1.6"/></svg>` },
  gov: { title: "government", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M8 2.2L14 6H2z"/><path d="M4 6v6M8 6v6M12 6v6"/><path d="M2.5 13.8h11"/></svg>` },
  world: { title: "rest of world", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="8" r="5.6"/><path d="M2.4 8h11.2M8 2.4c2 1.8 2 9.4 0 11.2M8 2.4c-2 1.8-2 9.4 0 11.2"/></svg>` },
  bolt: { title: "exogenous shock", svg: `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M9 2L4 9h3.2L7 14l5-7H8.8z"/></svg>` },
};

const PHASES = [
  { title: "Insolvent firms restructured", agents: ["firm", "bank"], knobs: ["zeta_b"],
    text: "Firms that ended last quarter unable to service their debt don't vanish. Their debt is written down against the bank's equity and new owners refinance them with a loan worth a fraction (zeta_b) of their capital." },
  { title: "Expectations form", agents: ["firm", "household", "bank", "gov"], knobs: [],
    text: "Every agent extrapolates recent growth and inflation into a simple forecast. These adaptive expectations — not perfect foresight — drive all the decisions that follow." },
  { title: "Central bank sets the policy rate", agents: ["cb"], knobs: ["rho", "xi_pi", "xi_gamma", "pi_star", "r_star"],
    text: "A Taylor rule: the rate rises when expected inflation exceeds the target (weight xi_pi) or growth runs hot (xi_gamma), smoothed heavily by rho so the bank moves slowly." },
  { title: "Shock applied (optional)", agents: ["bolt"], knobs: [],
    text: "If the experiment defines a shock — a rate hike, a productivity jump, a consumption surge — it hits the machine here. Otherwise this phase passes silently." },
  { title: "Bank prices credit", agents: ["bank", "cb"], knobs: ["mu"],
    text: "The commercial bank sets its loan rate as the policy rate plus a risk premium mu. Monetary policy transmits to firms through this single wire." },
  { title: "Firms plan the quarter", agents: ["firm"], knobs: ["theta"],
    text: "Each of the 652 firms sets its price and target output from expected demand, then works out how many workers, how much investment, and how big a loan that plan requires." },
  { title: "Credit market clears", agents: ["firm", "bank"], knobs: ["zeta"],
    text: "Firms queue for loans; the bank lends only while its capital requirement zeta allows. Credit rationing here can cut production plans before a single good is made." },
  { title: "Labour market clears", agents: ["firm", "household"], knobs: [],
    text: "Firms with vacancies and unemployed workers search and match at random. Hiring — and firing, when plans shrink — happens in this phase." },
  { title: "Production runs", agents: ["firm", "household"], knobs: [],
    text: "Matched labour, capital and intermediate inputs produce output in fixed Leontief proportions: no input can substitute for another. Wages are updated." },
  { title: "Household budgets set", agents: ["gov", "household"], knobs: ["psi", "psi_H", "theta_UB", "sb_other", "sb_inact", "w_UB"],
    text: "Government sets social benefits. Households sum wages, benefits and dividends, pay income tax, then commit a share psi of it to consumption and psi_H to housing investment." },
  { title: "Public & foreign demand set", agents: ["gov", "world"], knobs: ["tau_G", "tau_EXPORT"],
    text: "The government fixes its purchase budget; the rest of the world decides its import demand from — and export supply to — the economy." },
  { title: "Goods market clears", agents: ["firm", "household", "gov", "world"], knobs: [],
    text: "The machine's biggest gear: every buyer — households, government, investing firms, foreigners — searches across sellers and buys at posted prices until budgets or inventories run out." },
  { title: "Prices roll up to inflation", agents: ["firm", "household"], knobs: [],
    text: "Realized transaction prices aggregate into price indices. This is the quarter's inflation — and next quarter it feeds straight back into expectations." },
  { title: "Profits, dividends, taxes", agents: ["firm", "household", "gov"], knobs: ["theta_DIV", "tau_FIRM", "tau_VAT", "tau_INC", "tau_SIF", "tau_SIW"],
    text: "Firms tally profits and pay dividends (theta_DIV) and corporate tax; VAT, income tax and social insurance flow to the government." },
  { title: "Balance sheets settle", agents: ["firm", "household", "bank", "gov", "cb"], knobs: [],
    text: "Deposits, loans, bank equity and government debt are updated; GDP is recorded. The machine is wound and ready for the next quarter." },
];

const Phases = {
  idx: -1, playing: false, timer: 0,

  init() {
    const list = document.getElementById("phase-list");
    list.innerHTML = "";
    PHASES.forEach((p, i) => {
      const li = document.createElement("li");
      li.className = "phase-card";
      li.dataset.n = i + 1;
      li.innerHTML = `
        <div class="ph-top">
          <div class="ph-title">${p.title.toUpperCase()}</div>
          <div class="ph-agents">${p.agents.map((a) =>
            `<span class="agent-ic" title="${AGENT_ICONS[a].title}">${AGENT_ICONS[a].svg}</span>`).join("")}</div>
        </div>
        <div class="ph-text">${p.text}</div>
        ${p.knobs.length ? `<div class="ph-knobs">${p.knobs.map((k) => `<span class="ph-knob">${k}</span>`).join("")}</div>` : ""}`;
      li.addEventListener("click", () => { this.pause(); this.goto(i); });
      list.appendChild(li);
    });

    document.getElementById("phase-play").addEventListener("click", () => this.toggle());
    document.getElementById("phase-restart").addEventListener("click", () => { this.goto(0); this.play(); });
  },

  goto(i) {
    this.idx = i;
    const cards = document.querySelectorAll(".phase-card");
    cards.forEach((c, j) => {
      c.classList.toggle("active", j === i);
      c.classList.toggle("done", j < i);
    });
    const fill = document.getElementById("phase-pipe-fill");
    fill.style.height = `${((i + 0.5) / PHASES.length) * 100}%`;
    const el = cards[i];
    if (el) el.scrollIntoView({ block: "nearest", behavior: "smooth" });
  },

  play() {
    this.playing = true;
    document.getElementById("phase-play").textContent = "❚❚ PAUSE";
    if (this.idx < 0 || this.idx >= PHASES.length - 1) this.goto(0);
    clearInterval(this.timer);
    this.timer = setInterval(() => {
      if (this.idx >= PHASES.length - 1) { this.pause(); return; }
      this.goto(this.idx + 1);
    }, 2800);
  },

  pause() {
    this.playing = false;
    clearInterval(this.timer);
    document.getElementById("phase-play").textContent = "▶ AUTOPLAY";
  },

  toggle() { this.playing ? this.pause() : this.play(); },
};
