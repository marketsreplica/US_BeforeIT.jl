/* main.js — orchestrates THE MACHINE: boot, run selection, derived-flow
   recipes, scrubber/play, knob→circuit highlight routing, POST /api/runs. */
"use strict";

/* 62 sectors → 12 groups (1-based index ranges into sector-metadata / real_sector_gva). */
const SECTOR_GROUPS = [
  { id: "AGRI",  name: "Agriculture & Resources",      lo: 1,  hi: 4,  color: "#7da35c" },
  { id: "MANU",  name: "Manufacturing",                lo: 5,  hi: 23, color: "#c9834a" },
  { id: "UTIL",  name: "Energy & Utilities",           lo: 24, hi: 26, color: "#d9c05b" },
  { id: "CONS",  name: "Construction",                 lo: 27, hi: 27, color: "#a8794f" },
  { id: "TRADE", name: "Trade & Retail",               lo: 28, hi: 30, color: "#6b9bd9" },
  { id: "TRANS", name: "Transport & Logistics",        lo: 31, hi: 35, color: "#5b8a8f" },
  { id: "HOSP",  name: "Hotels & Restaurants",         lo: 36, hi: 36, color: "#e08a3c" },
  { id: "ICT",   name: "Information & Media",          lo: 37, hi: 40, color: "#8f7bd9" },
  { id: "FIN",   name: "Finance & Real Estate",        lo: 41, hi: 44, color: "#45c9a5" },
  { id: "PROF",  name: "Professional & Business Svcs", lo: 45, hi: 53, color: "#b0637a" },
  { id: "PUB",   name: "Public, Health & Education",   lo: 54, hi: 57, color: "#5e7ab0" },
  { id: "ARTS",  name: "Arts & Other Services",        lo: 58, hi: 62, color: "#9aa25c" },
];

const S = {
  knobs: [],            // defs from /api/knobs
  runs: [],             // /api/runs list
  summary: null,        // loaded run summary
  runId: null,
  sectorMeta: [],       // 62 {index, code, label}
  t: 0,                 // scrubber index 0..T
  playing: false,
  playTimer: 0,
  runOverrides: {},     // run_id -> {key: value} for runs launched this session
  posting: false,
};

/* ============================ boot ============================ */

async function boot() {
  try {
    // sector metadata is our own asset → relative path; /api is absolute
    const [knobs, runs, meta] = await Promise.all([
      getJSON("/api/knobs?dataset_id=AUSTRIA2026Q1"),
      getJSON("/api/runs"),
      getJSON("sector-metadata.json"),
    ]);
    hideError();
    S.knobs = knobs;
    S.runs = runs;
    S.sectorMeta = meta;

    KnobRail.init(knobs, { onChange: onKnobChange, onHover: onKnobHover });
    Sankey.init();
    Sankey.onFirmsHover = onFirmsHover;
    Gauges.init();
    Phases.init();
    wireUI();

    const pick = pickDefaultRun(runs);
    fillRunPicker(pick && pick.run_id);
    if (pick) {
      await loadRun(pick.run_id);
    } else {
      showError("No completed runs on the backend yet — turn some knobs and RUN THE MACHINE.");
      document.getElementById("run-meta").textContent = "no runs";
    }
  } catch (e) {
    console.error(e);
    showError("Backend unreachable — is the Julia API on port 8080 up? (" + e.message + ")");
  }
}

/* newest done run, preferring the flagship dataset (list arrives newest-first) */
function pickDefaultRun(runs) {
  const done = runs.filter((r) => r.state === "done");
  return done.find((r) => r.dataset_id === "AUSTRIA2026Q1") || done[0] || null;
}

function fillRunPicker(selectedId) {
  const sel = document.getElementById("run-pick");
  const done = S.runs.filter((r) => r.state === "done");
  sel.innerHTML = done.map((r) => {
    const when = (r.created_at || "").replace("T", " ").slice(0, 16);
    return `<option value="${r.run_id}">${r.dataset_id} · ${r.scenario} · ${when}</option>`;
  }).join("");
  if (selectedId) sel.value = selectedId;
}

async function loadRun(runId) {
  try {
    const sum = await getJSON(`/api/runs/${runId}/summary`);
    hideError();
    S.summary = sum;
    S.runId = runId;
    S.t = 0;

    // If we launched this run ourselves, restore the knobs it was run with,
    // so the derived tax wedges match the machine's actual settings.
    const ov = S.runOverrides[runId];
    if (ov) {
      KnobRail.resetAll();
      Object.entries(ov).forEach(([k, v]) => KnobRail.set(k, v, true));
    }

    const scrub = document.getElementById("time-scrub");
    scrub.max = sum.periods.length - 1;
    scrub.value = 0;

    Gauges.setData(sum);
    refreshQuarter(true);
    updateRunMeta();
    updateRunButton();
    document.getElementById("run-note").textContent =
      `${sum.n_sims} sims · T=${sum.T} · forecast starts ${sum.forecast_start_period}`;
  } catch (e) {
    console.error(e);
    showError("Could not load run summary: " + e.message);
  }
}

function updateRunMeta() {
  const s = S.summary;
  if (!s) return;
  const dsLabel = (s.dataset_metadata && s.dataset_metadata.label) || s.dataset_id;
  document.getElementById("run-meta").innerHTML =
    `<b>${dsLabel}</b> · ${s.scenario}<br>run ${String(S.runId).slice(0, 8)} · ${Math.round(s.n_sims)} sims`;
}

/* ===================== derived money flows ===================== */

/* Contract recipes: run aggregates at quarter i × the CURRENT knob settings.
   Using live knob values makes the wedges respond instantly to the dials —
   honest because every flow is badged "derived". */
function computeFlows(i) {
  const s = S.summary;
  const v = KnobRail.vals;
  if (!s) return {};
  const defl = Number.isFinite(at(s.gdp_deflator.mean, i)) ? at(s.gdp_deflator.mean, i) : 1;
  const C = at(s.real_household_consumption.mean, i) * defl;
  const G = at(s.real_government_consumption.mean, i) * defl;
  const X = at(s.real_exports.mean, i) * defl;
  const M = at(s.real_imports.mean, i) * defl;
  const I = at(s.real_fixed_capitalformation.mean, i) * defl;
  const W = at(s.wages.mean, i);                       // already nominal
  const nomGDP = at(s.real_gdp.mean, i) * defl;
  const z = (x) => (Number.isFinite(x) ? x : 0);
  return {
    cons: z(C),
    gov: z(G),
    exports: z(X),
    wages: z(W),
    imports: z(M),
    invest: z(I),
    corptax: z(v.tau_FIRM * Math.max(0, nomGDP - W)),
    vat: z(v.tau_VAT * C),
    inctax: z(v.tau_INC * W),
    socins: z((v.tau_SIF + v.tau_SIW) * W),
    // benefits: per-household benefit levels × household counts × deflator
    benefits: z((v.sb_inact * 4130 + v.sb_other * 9215) * defl),
  };
}

function refreshQuarter(immediate) {
  const s = S.summary;
  if (!s) return;
  const i = S.t;
  Sankey.update(computeFlows(i), immediate);
  Gauges.setCursor(i);
  renderSectorStrip(i);
  updateCreditChip(i);

  const period = s.periods[i] || "—";
  document.getElementById("qtr-label").textContent = period;
  document.getElementById("scrub-read").textContent =
    `${period} · Q${i}/${s.periods.length - 1}`;
  const scrub = document.getElementById("time-scrub");
  scrub.style.setProperty("--pct", `${(i / Math.max(1, s.periods.length - 1)) * 100}%`);
}

/* credit-market chip: bank loan rate = policy rate + risk premium mu (derived) */
function updateCreditChip(i) {
  const s = S.summary;
  const el = document.getElementById("credit-chip-text");
  if (!s || !el) return;
  const q = at(s.euribor_q.mean, i);
  if (!Number.isFinite(q)) { el.textContent = "CREDIT MARKET"; return; }
  const loanQ = q + KnobRail.vals.mu;
  const loanAnnual = Math.pow(1 + loanQ, 4) - 1;
  el.textContent = `CREDIT · loan rate ≈ ${fmtPct(loanAnnual, 2)} (policy + mu)`;
}

/* ================== sector-group strip under the Sankey ================== */

function groupShares(i) {
  const s = S.summary;
  if (!s || !s.real_sector_gva) return [];
  const row = s.real_sector_gva.mean[i];
  if (!row) return [];
  let total = 0;
  const sums = SECTOR_GROUPS.map((g) => {
    let acc = 0;
    for (let k = g.lo - 1; k <= g.hi - 1 && k < row.length; k++) {
      const v = row[k];
      if (Number.isFinite(v) && v > 0) acc += v;
    }
    total += acc;
    return acc;
  });
  if (total <= 0) return [];
  return SECTOR_GROUPS.map((g, j) => ({ ...g, share: sums[j] / total, gva: sums[j] }));
}

function renderSectorStrip(i) {
  const host = document.getElementById("sector-strip");
  const shares = groupShares(i);
  if (!shares.length) { host.innerHTML = ""; return; }
  // build once, then only mutate widths (keeps :hover stable while playing)
  if (host.childElementCount !== shares.length) {
    host.innerHTML = shares.map((g) =>
      `<div class="seg" data-g="${g.id}" style="background:${g.color}"></div>`).join("");
  }
  const segs = host.children;
  shares.forEach((g, j) => {
    segs[j].style.width = `${(g.share * 100).toFixed(2)}%`;
    segs[j].title = `${g.name} — ${(g.share * 100).toFixed(1)}% of real GVA (${fmtMoney(g.gva)})`;
  });
}

/* FIRMS node hover → tooltip listing the top sector groups this quarter */
function onFirmsHover(on, ev) {
  const tip = document.getElementById("flow-tip");
  if (!on) { tip.hidden = true; return; }
  const shares = groupShares(S.t).sort((a, b) => b.share - a.share).slice(0, 6);
  if (!shares.length) return;
  tip.innerHTML =
    `<b>Inside FIRMS</b> — 652 firms across 62 sectors<br>` +
    shares.map((g) =>
      `<span style="color:${g.color}">▮</span> ${g.name} <b>${(g.share * 100).toFixed(1)}%</b>`
    ).join("<br>") +
    `<br><span class="dnote">share of real GVA · derived</span>`;
  tip.hidden = false;
  const wrap = document.getElementById("sankey-wrap").getBoundingClientRect();
  tip.style.left = clamp(ev.clientX - wrap.left + 14, 0, wrap.width - 270) + "px";
  tip.style.top = clamp(ev.clientY - wrap.top + 12, 0, wrap.height - 150) + "px";
}

/* ================== knob → circuit highlight routing ================== */

function onKnobHover(key) {
  const fx = key ? KNOB_FX[key] : null;
  Sankey.highlight(fx ? fx.links || [] : [], fx ? fx.nodes || [] : []);
  document.getElementById("credit-chip").classList.toggle("hl", !!(fx && fx.chip === "credit"));
  GAUGE_DEFS.forEach((g) => Gauges.highlight(g.id, !!(fx && fx.gauge === g.id)));
}

function onKnobChange(key) {
  // re-derive the wedge flows with the new settings; keep the wire lit while turning
  refreshQuarter(false);
  if (key) onKnobHover(key);
  updateRunButton();
}

function updateRunButton() {
  const { count } = KnobRail.changedOverrides();
  const btn = document.getElementById("btn-run");
  if (!S.posting) {
    btn.textContent = count ? `RUN THE MACHINE · ${count} change${count > 1 ? "s" : ""}` : "RUN THE MACHINE";
  }
  // server enforces psi + psi_H <= 1 — warn before it 400s
  const bad = KnobRail.vals.psi + KnobRail.vals.psi_H > 1;
  document.getElementById("psi-warn").hidden = !bad;
  btn.disabled = S.posting || bad;
}

/* ============================ RUN flow ============================ */

async function runMachine() {
  if (S.posting) return;
  const { overrides, count } = KnobRail.changedOverrides();
  const body = {
    dataset_id: "AUSTRIA2026Q1",
    scenario: document.getElementById("scenario-pick").value,
    sim: { T: 12, n_sims: 4, base_seed: 1000 + Math.floor(Math.random() * 100000) },
    overrides: {},           // changed knobs only, UI units (server converts r_bar)
    shock: { type: "none" },
  };
  if (Object.keys(overrides.parameters).length) body.overrides.parameters = overrides.parameters;
  if (Object.keys(overrides.initial_conditions).length) body.overrides.initial_conditions = overrides.initial_conditions;

  const prog = document.getElementById("run-progress");
  const fill = document.getElementById("prog-fill");
  const label = document.getElementById("prog-label");
  const btn = document.getElementById("btn-run");
  S.posting = true;
  btn.disabled = true;
  btn.textContent = "MACHINE RUNNING…";
  prog.hidden = false;
  fill.style.width = "3%";
  label.textContent = "igniting boilers… (queued)";

  try {
    const { run_id } = await postJSON("/api/runs", body);
    // remember what the machine was set to for this run
    const flat = {};
    Object.assign(flat, overrides.parameters, overrides.initial_conditions);
    S.runOverrides[run_id] = flat;

    // poll every ~1.5 s per contract
    while (true) {
      await new Promise((res) => setTimeout(res, 1500));
      const st = await getJSON(`/api/runs/${run_id}/status`);
      const pct = Math.max(3, Math.round((st.progress || 0) * 100));
      fill.style.width = pct + "%";
      label.textContent = `${st.state} · ${pct}% — ${st.message || "…"}`;
      if (st.state === "done") break;
      if (st.state === "error") throw new Error("simulation failed: " + (st.message || "unknown error"));
    }
    fill.style.width = "100%";
    label.textContent = "condensing steam… loading results";
    S.runs = await getJSON("/api/runs");
    fillRunPicker(run_id);
    await loadRun(run_id);
    label.textContent = "done — results loaded";
    setTimeout(() => { prog.hidden = true; }, 1600);
  } catch (e) {
    console.error(e);
    showError("Run failed: " + e.message);
    label.textContent = "run failed";
    setTimeout(() => { prog.hidden = true; }, 2500);
  } finally {
    S.posting = false;
    updateRunButton();
  }
}

/* ============================ UI wiring ============================ */

function wireUI() {
  // tabs
  document.querySelectorAll(".tab").forEach((b) => {
    b.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("active", x === b));
      document.getElementById("tab-machine").classList.toggle("active", b.dataset.tab === "machine");
      document.getElementById("tab-phases").classList.toggle("active", b.dataset.tab === "phases");
      if (b.dataset.tab === "phases" && Phases.idx < 0) Phases.play();
      if (b.dataset.tab !== "phases") Phases.pause();
    });
  });

  // scrubber
  const scrub = document.getElementById("time-scrub");
  scrub.addEventListener("input", () => {
    S.t = +scrub.value;
    stopPlay();
    refreshQuarter(false);
  });

  // play/pause the quarters
  document.getElementById("btn-play").addEventListener("click", () => {
    S.playing ? stopPlay() : startPlay();
  });

  // existing-run picker
  document.getElementById("run-pick").addEventListener("change", (e) => {
    stopPlay();
    loadRun(e.target.value);
  });

  document.getElementById("btn-reset").addEventListener("click", () => {
    KnobRail.resetAll();
    onKnobHover(null);
  });
  document.getElementById("btn-run").addEventListener("click", runMachine);

  window.addEventListener("resize", () => Sankey._positionChip());
}

function startPlay() {
  if (!S.summary) return;
  S.playing = true;
  document.getElementById("btn-play").textContent = "❚❚";
  clearInterval(S.playTimer);
  S.playTimer = setInterval(() => {
    const n = S.summary.periods.length;
    S.t = (S.t + 1) % n;
    document.getElementById("time-scrub").value = S.t;
    refreshQuarter(false);
  }, 1200);
}

function stopPlay() {
  S.playing = false;
  clearInterval(S.playTimer);
  document.getElementById("btn-play").textContent = "▶";
}

document.addEventListener("DOMContentLoaded", boot);
