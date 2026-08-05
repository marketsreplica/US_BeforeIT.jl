'use strict';
/* ============================================================
 * Flow Atlas — application logic
 * Boot, run loading, timeline playback, KPIs, tooltips,
 * inspector panels, and the run-new-simulation drawer.
 * ============================================================ */

const S = {
  runs: [], datasets: [], sectorMeta: [],
  knobsByDataset: {},    // dataset_id -> {list:[knob], defaults:{key:val}}
  vectorsByDataset: {},  // dataset_id -> {I_s, N_s, b_HH_g, c_G_g, c_E_g, c_I_g}
  specsByRun: {},        // run_id -> persisted run spec, or null when unavailable
  overridesByRun: {},    // run_id -> overrides we sent (for derived-tax accuracy)
  run: null, summary: null, derived: null,
  tFloat: 0, maxT: 0, playing: true, speed: 1, scrubbing: false,
  hover: null, selection: null,
  pollTimer: null, pollingRunId: null,
};
const QPS = 0.55; // quarters per second at 1x speed

const $ = (id) => document.getElementById(id);

/* ============================================================
 * Boot
 * ============================================================ */
async function boot() {
  hideError();
  try {
    const [meta, runs, datasets] = await Promise.all([
      AtlasAPI.json('sector-metadata.json'),
      AtlasAPI.json('/api/runs'),
      AtlasAPI.json('/api/datasets'),
    ]);
    S.sectorMeta = meta;
    S.runs = runs;
    S.datasets = datasets;

    buildLegend();
    populateRunSelect();

    const done = runs.filter((r) => r.state === 'done');
    if (!done.length) {
      showError('No completed runs on the server yet — open "Run new simulation" to launch one.');
      return;
    }
    // Newest done run, preferring the AUSTRIA2026Q1 nowcast dataset.
    const pick = done.find((r) => r.dataset_id === 'AUSTRIA2026Q1') || done[0];
    $('run-select').value = pick.run_id;
    await loadRun(pick.run_id);
  } catch (err) {
    console.error(err);
    showError('Backend API unreachable — is the Julia server running? ' + err.message);
  }
}

/* Fetch per-dataset knob defaults + structural vectors (cached). */
async function datasetAssets(datasetId) {
  if (S.knobsByDataset[datasetId] && S.vectorsByDataset[datasetId]) {
    return { knobs: S.knobsByDataset[datasetId], vectors: S.vectorsByDataset[datasetId] };
  }
  const knobList = await AtlasAPI.json('/api/knobs?dataset_id=' + encodeURIComponent(datasetId));
  const defaults = {};
  for (const k of knobList) defaults[k.key] = k.default;
  const knobs = { list: knobList, defaults };

  const vecSpec = [
    ['I_s', 'parameters'], ['b_HH_g', 'parameters'], ['c_G_g', 'parameters'],
    ['c_E_g', 'parameters'], ['c_I_g', 'parameters'], ['N_s', 'initial_conditions'],
  ];
  const vectors = {};
  await Promise.all(vecSpec.map(async ([key, group]) => {
    try {
      const res = await AtlasAPI.json(
        `/api/datasets/value?dataset_id=${encodeURIComponent(datasetId)}&group=${group}&key=${key}`);
      vectors[key] = flattenVec(res.value);
    } catch (_) {
      vectors[key] = null; // buildDerived falls back to GVA shares
    }
  }));

  S.knobsByDataset[datasetId] = knobs;
  S.vectorsByDataset[datasetId] = vectors;
  return { knobs, vectors };
}

/* Fetch persisted run provenance when the backend exposes it (cached, optional). */
async function runSpec(runId) {
  if (Object.prototype.hasOwnProperty.call(S.specsByRun, runId)) {
    return S.specsByRun[runId];
  }
  try {
    const spec = await AtlasAPI.json(`/api/runs/${runId}/spec`);
    S.specsByRun[runId] = spec;
    return spec;
  } catch (err) {
    // Older servers do not expose run specs. Keep local-run overrides as a fallback.
    console.debug(`Run provenance unavailable for ${runId}: ${err.message}`);
    S.specsByRun[runId] = null;
    return null;
  }
}

async function loadRun(runId) {
  hideError();
  try {
    const run = S.runs.find((r) => r.run_id === runId);
    const [summary, spec] = await Promise.all([
      AtlasAPI.json(`/api/runs/${runId}/summary`),
      runSpec(runId),
    ]);
    const { knobs, vectors } = await datasetAssets(summary.dataset_id);
    const persistedOverrides = spec && spec.overrides && typeof spec.overrides === 'object'
      ? spec.overrides
      : null;

    S.run = run || { run_id: runId, dataset_id: summary.dataset_id, scenario: summary.scenario };
    S.summary = summary;
    S.derived = buildDerived(
      summary,
      knobs.defaults,
      vectors,
      persistedOverrides || S.overridesByRun[runId],
    );
    S.maxT = summary.periods.length - 1;
    S.tFloat = 0;
    S.playing = true;
    S.selection = null;
    S.hover = null;
    closePanel();

    $('kpi-scenario').textContent =
      `${summary.dataset_id} · ${summary.scenario} · ${summary.n_sims | 0} sims`;
    $('btn-play').innerHTML = '&#10074;&#10074;';
    buildTimelineTicks();
    Renderer.buildEdges(S);
  } catch (err) {
    console.error(err);
    showError('Failed to load run summary: ' + err.message);
  }
}

/* ============================================================
 * Header: run selector + legend
 * ============================================================ */
function populateRunSelect() {
  const sel = $('run-select');
  sel.innerHTML = '';
  for (const r of S.runs.filter((x) => x.state === 'done')) {
    const opt = document.createElement('option');
    opt.value = r.run_id;
    opt.textContent = `${r.scenario} · ${r.dataset_id} · ${fmtDate(r.created_at)}`;
    sel.appendChild(opt);
  }
}

function buildLegend() {
  const wrap = $('legend-items');
  wrap.innerHTML = '';
  const shortNames = {
    CONS: 'Consumption', WAGES: 'Wages', GOV: 'Gov purchases', BEN: 'Benefits',
    HHTAX: 'Household taxes', CORP: 'Corporate tax', EXP: 'Exports', IMP: 'Imports', INV: 'Investment',
  };
  for (const f of FLOW_DEFS) {
    const row = document.createElement('div');
    row.className = 'legend-row';
    row.innerHTML = `<span class="legend-swatch" style="background:${f.color};color:${f.color}"></span>${shortNames[f.id] || f.name}`;
    wrap.appendChild(row);
  }
}

/* ============================================================
 * Timeline
 * ============================================================ */
function buildTimelineTicks() {
  const scrub = $('scrubber');
  scrub.max = S.maxT;
  scrub.value = 0;
  const ticks = $('tl-ticks');
  ticks.innerHTML = '';
  S.summary.periods.forEach((p, i) => {
    if (!p.endsWith('Q1')) return;
    const el = document.createElement('span');
    el.className = 'tl-tick';
    el.style.left = (i / S.maxT) * 100 + '%';
    el.textContent = p.slice(0, 4);
    ticks.appendChild(el);
  });
}

$('btn-play').addEventListener('click', () => {
  S.playing = !S.playing;
  $('btn-play').innerHTML = S.playing ? '&#10074;&#10074;' : '&#9654;';
});
document.querySelectorAll('.speed-btn').forEach((b) => {
  b.addEventListener('click', () => {
    document.querySelectorAll('.speed-btn').forEach((x) => x.classList.remove('active'));
    b.classList.add('active');
    S.speed = parseFloat(b.dataset.speed);
  });
});
{
  const scrub = $('scrubber');
  scrub.addEventListener('pointerdown', () => { S.scrubbing = true; });
  window.addEventListener('pointerup', () => { S.scrubbing = false; });
  scrub.addEventListener('input', () => { S.tFloat = parseFloat(scrub.value); });
}

/* ============================================================
 * Animation loop + KPIs
 * ============================================================ */
let lastTs = 0;
const kpiCache = {};
function setText(id, txt) {
  if (kpiCache[id] !== txt) { kpiCache[id] = txt; $(id).textContent = txt; }
}

function frame(ts) {
  const dt = Math.min(0.05, (ts - lastTs) / 1000) || 0.016;
  lastTs = ts;
  if (S.derived) {
    if (S.playing && !S.scrubbing) {
      S.tFloat += dt * S.speed * QPS;
      if (S.tFloat >= S.maxT) S.tFloat = 0; // loop the movie
    }
    updateKPIs();
    if (!S.scrubbing) $('scrubber').value = S.tFloat;
    $('scrubber').style.setProperty('--fill', (S.tFloat / Math.max(1e-9, S.maxT)) * 100 + '%');
  }
  Renderer.draw(S, dt);
  requestAnimationFrame(frame);
}

function updateKPIs() {
  const d = S.derived, tf = S.tFloat;
  const qi = Math.round(Math.max(0, Math.min(S.maxT, tf)));
  setText('kpi-quarter', S.summary.periods[qi]);
  setText('tl-period', S.summary.periods[qi]);
  setText('kpi-gdp', fmtBn(sampleSeries(d.D.nomGDP, tf)));
  setText('kpi-infl', fmtPct(sampleSeries(d.D.inflYoY, tf), 2));
  setText('kpi-rate', fmtPct(sampleSeries(d.D.rate, tf), 2));
  setText('kpi-trade', fmtBn(sampleSeries(d.D.tradeBal, tf)));
}

/* ============================================================
 * Mouse: hover tooltips + click panels
 * ============================================================ */
const canvas = $('atlas-canvas');
const tooltip = $('tooltip');

canvas.addEventListener('mousemove', (ev) => {
  if (!S.derived) return;
  const hit = Renderer.hitTest(ev.clientX, ev.clientY);
  S.hover = hit;
  canvas.classList.toggle('pointer', !!hit);
  if (hit) showTooltip(hit, ev.clientX, ev.clientY);
  else tooltip.classList.add('hidden');
});
canvas.addEventListener('mouseleave', () => {
  S.hover = null;
  tooltip.classList.add('hidden');
});
canvas.addEventListener('click', (ev) => {
  if (!S.derived) return;
  const hit = Renderer.hitTest(ev.clientX, ev.clientY);
  if (hit && hit.type === 'node') openPanel(hit.node);
  else if (!hit) { S.selection = null; closePanel(); }
});

function showTooltip(hit, mx, my) {
  let html = '';
  const badge = '<span class="derived-badge" title="Estimated from aggregate output — not a direct model observable">derived</span>';
  const tf = S.tFloat, d = S.derived;

  if (hit.type === 'edge') {
    const e = hit.edge, f = e.flow;
    const total = flowValue(d, f.id, tf);
    const val = Renderer.edgeValue(S, e, tf);
    const fromName = f.from === 'FIRMS' ? 'Firms' : ANCHOR_DEFS[f.from].name;
    const toName = f.to === 'FIRMS' ? 'Firms' : ANCHOR_DEFS[f.to].name;
    html = `<div class="tt-title"><span style="color:${f.color}">&#9679;</span> ${fromName} &rarr; ${toName} · ${f.name} ${badge}</div>`;
    html += `<div class="tt-value">${fmtBn(val)}<span style="font-size:11px;color:#8b97c4"> /quarter</span></div>`;
    html += `<div class="tt-model">${fmtModel(val)}</div>`;
    if (e.gIdx != null) {
      const share = flowGroupShare(d, f, e.gIdx, tf);
      html += `<div class="tt-share">${GROUP_DEFS[e.gIdx].name}: ${fmtPct(share, 1)} of total ${fmtBn(total)}</div>`;
    }
    if (f.id === 'HHTAX') {
      const parts = [
        sampleSeries(d.D.hhTaxParts.map((p) => p[0]), tf),
        sampleSeries(d.D.hhTaxParts.map((p) => p[1]), tf),
        sampleSeries(d.D.hhTaxParts.map((p) => p[2]), tf),
      ];
      html += `<div class="tt-share">VAT ${fmtBn(parts[0])} · income ${fmtBn(parts[1])} · soc.ins. ${fmtBn(parts[2])}</div>`;
    }
    html += `<div class="tt-formula">${f.formula}\n${f.note}</div>`;
  } else if (hit.type === 'halo') {
    const val = flowValue(d, 'INV', tf);
    const f = FLOW_DEFS.find((x) => x.id === 'INV');
    html = `<div class="tt-title"><span style="color:#6fa8ff">&#9679;</span> Firms &rarr; Firms · Investment ${badge}</div>`;
    html += `<div class="tt-value">${fmtBn(val)}<span style="font-size:11px;color:#8b97c4"> /quarter</span></div>`;
    html += `<div class="tt-model">${fmtModel(val)}</div>`;
    html += `<div class="tt-formula">${f.formula}\n${f.note}</div>`;
  } else if (hit.type === 'node') {
    const n = hit.node;
    if (n.kind === 'group') {
      html = `<div class="tt-title"><span style="color:${n.color}">&#9679;</span> ${n.def.name}</div>`;
      html += `<div class="tt-value">${fmtBn(n.gva)}<span style="font-size:11px;color:#8b97c4"> real GVA/q</span></div>`;
      html += `<div class="tt-share">${fmtPct(n.share, 1)} of all-sector GVA · ${S.derived.groupFirms[n.gIdx]} firms · ${S.derived.groupEmp[n.gIdx]} workers</div>`;
      html += `<div class="tt-formula">node area ∝ group share of real_sector_gva\nclick for member sectors</div>`;
    } else {
      const blurb = {
        HH: 'Earn wages & dividends, pay taxes, consume & invest in housing.',
        GOV: 'Taxes in, purchases & benefits out; issues debt to cover the gap.',
        CB: 'Sets the policy rate by a Taylor rule; the aura pulses with the rate.',
        BANK: 'Lends to firms at policy rate + mu; holds all deposits.',
        ROW: 'Trades imports & exports with domestic firms.',
      }[n.id];
      html = `<div class="tt-title"><span style="color:${n.color}">&#9679;</span> ${ANCHOR_DEFS[n.id].name}</div>`;
      html += `<div class="tt-share">${blurb}</div>`;
      html += `<div class="tt-formula">click for details & time series</div>`;
    }
  }
  tooltip.innerHTML = html;
  tooltip.classList.remove('hidden');
  const pad = 14;
  const bw = tooltip.offsetWidth, bh = tooltip.offsetHeight;
  let x = mx + pad, y = my + pad;
  if (x + bw > window.innerWidth - 8) x = mx - bw - pad;
  if (y + bh > window.innerHeight - 8) y = my - bh - pad;
  tooltip.style.left = x + 'px';
  tooltip.style.top = y + 'px';
}

/* ============================================================
 * Inspector panel
 * ============================================================ */
function closePanel() { $('panel').classList.add('hidden'); }
$('panel-close').addEventListener('click', () => { S.selection = null; closePanel(); });

function openPanel(node) {
  S.selection = node;
  const c = $('panel-content');
  const qi = Math.round(S.tFloat);
  const q = S.summary.periods[qi];

  if (node.kind === 'group') {
    const g = node.def, gi = node.gIdx;
    let html = `<div class="panel-kicker">Sector group · ${q}</div>`;
    html += `<div class="panel-title"><span class="panel-chip" style="background:${g.color};color:${g.color}"></span>${g.name}</div>`;
    html += `<div class="panel-stats">
      <div class="pstat"><div class="ps-v">${fmtBn(node.gva)}</div><div class="ps-l">real GVA/q</div></div>
      <div class="pstat"><div class="ps-v">${S.derived.groupFirms[gi]}</div><div class="ps-l">firms (I_s)</div></div>
      <div class="pstat"><div class="ps-v">${S.derived.groupEmp[gi]}</div><div class="ps-l">workers (N_s)</div></div>
    </div>`;
    html += `<div class="panel-body">Firm agents here hire workers, take bank loans, produce with Leontief technology and sell to households, government, other firms and abroad. Node area tracks the group's share of real GVA as time plays.</div>`;
    html += `<div class="panel-section-h">Member sectors · GVA path (${S.summary.periods[0]} &rarr; ${S.summary.periods[S.maxT]})</div>`;
    const vecs = S.vectorsByDataset[S.summary.dataset_id] || {};
    for (let s = g.from; s <= g.to; s++) {
      const m = S.sectorMeta[s - 1] || { code: '?', label: 'Sector ' + s };
      const firms = vecs.I_s ? Math.round(vecs.I_s[s - 1]) : '—';
      const emp = vecs.N_s ? Math.round(vecs.N_s[s - 1]) : '—';
      html += `<div class="sector-row">
        <div class="sector-info">
          <div class="s-label">${m.label}</div>
          <div class="s-meta">${m.code} · ${firms} firms · ${emp} workers</div>
        </div>
        <canvas data-spark="${s}"></canvas>
      </div>`;
    }
    c.innerHTML = html;
    $('panel').classList.remove('hidden');
    // sparklines from real_sector_gva mean columns
    c.querySelectorAll('canvas[data-spark]').forEach((cv) => {
      const s = parseInt(cv.dataset.spark, 10);
      const data = S.summary.real_sector_gva.mean.map((row) => row[s - 1] || 0);
      drawSparkline(cv, data, g.color);
    });
    return;
  }

  // ---- anchor panels ----
  const D = S.derived.D;
  const mean = (k) => (S.summary[k] && S.summary[k].mean) || [];
  const std = (k) => (S.summary[k] && S.summary[k].std) || [];
  const defs = {
    HH: {
      kicker: 'Agent · Households', color: ANCHOR_DEFS.HH.color,
      stats: [['5,085', 'active'], ['4,130', 'inactive'], [fmtBn(sampleSeries(D.C, S.tFloat)), 'consumption/q']],
      body: `Active households supply labour; inactive ones draw pensions. Each quarter they form expectations <span class="phase-tag">phase 2</span>, search for jobs in the labour market <span class="phase-tag">phase 8</span>, receive wages and dividends, set a consumption budget (share <b>psi</b> of expected income) and a housing-investment budget (<b>psi_H</b>) <span class="phase-tag">phase 10</span>, then shop across all 62 sectors <span class="phase-tag">phase 12</span>. They pay income tax and social insurance on wages, and VAT on purchases <span class="phase-tag">phase 14</span>.`,
      chart: { series: [{ data: mean('real_household_consumption'), band: std('real_household_consumption'), color: '#ffc86b', label: 'real consumption' }], caption: 'real household consumption (model units/q)' },
    },
    GOV: {
      kicker: 'Agent · Government', color: ANCHOR_DEFS.GOV.color,
      stats: [[fmtBn(sampleSeries(D.G, S.tFloat)), 'purchases/q'], [fmtBn(sampleSeries(D.BEN, S.tFloat)), 'benefits/q'], [fmtBn(sampleSeries(D.HHTAX, S.tFloat) + sampleSeries(D.CORP, S.tFloat)), 'tax take/q']],
      body: `Sets social benefits <span class="phase-tag">phase 10</span> and its expenditure budget <span class="phase-tag">phase 11</span>, buys goods and services in the goods market <span class="phase-tag">phase 12</span>, collects VAT, income, social-insurance and corporate taxes <span class="phase-tag">phase 14</span>, and issues bonds at the policy rate + <b>r_G</b> spread to fund any deficit <span class="phase-tag">phase 15</span>.`,
      chart: { series: [{ data: mean('real_government_consumption'), band: std('real_government_consumption'), color: '#b18cff', label: 'real gov consumption' }], caption: 'real government consumption (model units/q)' },
    },
    CB: {
      kicker: 'Agent · Central bank', color: ANCHOR_DEFS.CB.color,
      stats: [[fmtPct(sampleSeries(D.rate, S.tFloat)), 'policy rate (annual)'], [fmtPct(sampleSeries(D.inflYoY, S.tFloat)), 'inflation YoY']],
      body: `Sets the policy rate each quarter by a Taylor rule <span class="phase-tag">phase 3</span>: <br><span style="font-family:var(--mono);font-size:11px">r = &rho;&middot;r&#8331;&#8321; + (1&minus;&rho;)(r* + &pi;* + &xi;<sub>&pi;</sub>(&pi;&minus;&pi;*) + &xi;<sub>&gamma;</sub>&middot;&gamma;)</span><br>High inflation or fast growth pushes the rate up; smoothing <b>rho</b> makes it move slowly. The rate reaches the economy through the bank's loan rate. The aura around the node pulses faster and brighter as the rate rises.`,
      chart: { series: [{ data: mean('euribor_annual').map((v) => (v || 0) * 100), band: std('euribor_annual').map((v) => (v || 0) * 100), color: '#7ef0ff', label: 'policy rate' }], caption: 'policy rate, % annualized', fmt: (v) => v.toFixed(2) + '%' },
    },
    BANK: {
      kicker: 'Agent · Commercial bank', color: ANCHOR_DEFS.BANK.color,
      stats: [[fmtPct(sampleSeries(D.rate, S.tFloat)), 'policy rate'], ['+ mu', 'loan spread']],
      body: `The single commercial bank sets its loan rate = policy rate + risk premium <b>mu</b> <span class="phase-tag">phase 5</span>, then matches with firms demanding credit <span class="phase-tag">phase 7</span>. It finances restructured insolvent firms <span class="phase-tag">phase 1</span>, holds every agent's deposits, and must keep equity above <b>zeta</b> &times; assets. The dashed line from the central bank is the policy-rate transmission channel.`,
      chart: { series: [{ data: mean('euribor_annual').map((v) => (v || 0) * 100), band: std('euribor_annual').map((v) => (v || 0) * 100), color: '#9fb4e8', label: 'policy rate' }], caption: 'loan-rate driver: policy rate % (loan = policy + mu)', fmt: (v) => v.toFixed(2) + '%' },
    },
    ROW: {
      kicker: 'Agent · Rest of world', color: ANCHOR_DEFS.ROW.color,
      stats: [[fmtBn(sampleSeries(D.EXP, S.tFloat)), 'exports/q'], [fmtBn(sampleSeries(D.IMP, S.tFloat)), 'imports/q'], [fmtBn(sampleSeries(D.tradeBal, S.tFloat)), 'balance']],
      body: `The rest of the world sets import and export budgets from expectations <span class="phase-tag">phase 11</span> and trades with domestic firms in the goods market <span class="phase-tag">phase 12</span>. Exports (green) bring foreign money to firms; imports (pink) leak spending abroad. Austria runs the balance you see counting in the corner.`,
      chart: {
        series: [
          { data: mean('real_exports'), band: std('real_exports'), color: '#5ee08a', label: 'exports' },
          { data: mean('real_imports'), band: std('real_imports'), color: '#ff8fa3', label: 'imports' },
        ], caption: 'real exports vs imports (model units/q)',
      },
    },
  };
  const def = defs[node.id];
  if (!def) return;
  let html = `<div class="panel-kicker">${def.kicker}</div>`;
  html += `<div class="panel-title"><span class="panel-chip" style="background:${def.color};color:${def.color}"></span>${ANCHOR_DEFS[node.id].name}</div>`;
  html += `<div class="panel-stats">${def.stats.map(([v, l]) =>
    `<div class="pstat"><div class="ps-v">${v}</div><div class="ps-l">${l}</div></div>`).join('')}</div>`;
  html += `<div class="panel-section-h">Time series</div>`;
  html += `<div class="panel-chart-wrap"><canvas id="panel-chart"></canvas><div class="chart-caption">${def.chart.caption} · shaded band = ±1 s.d. across ${S.summary.n_sims | 0} sims</div></div>`;
  html += `<div class="panel-section-h">Role in the model</div>`;
  html += `<div class="panel-body">${def.body}</div>`;
  c.innerHTML = html;
  $('panel').classList.remove('hidden');
  drawLineChart($('panel-chart'), def.chart.series, Math.round(S.tFloat));
}

/* ---------- tiny canvas charts ---------- */
function drawSparkline(cv, data, color) {
  const dpr = Math.min(2.5, window.devicePixelRatio || 1);
  const W = cv.clientWidth || 104, H = cv.clientHeight || 26;
  cv.width = W * dpr; cv.height = H * dpr;
  const g = cv.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  let mn = Infinity, mx = -Infinity;
  for (const v of data) { if (v < mn) mn = v; if (v > mx) mx = v; }
  const span = mx - mn || 1;
  g.strokeStyle = color; g.lineWidth = 1.3; g.globalAlpha = 0.9;
  g.beginPath();
  data.forEach((v, i) => {
    const x = 2 + (i / (data.length - 1 || 1)) * (W - 6);
    const y = H - 3 - ((v - mn) / span) * (H - 7);
    i ? g.lineTo(x, y) : g.moveTo(x, y);
  });
  g.stroke();
  const lx = 2 + (W - 6), lv = data[data.length - 1];
  g.fillStyle = color;
  g.beginPath(); g.arc(lx, H - 3 - ((lv - mn) / span) * (H - 7), 2, 0, Math.PI * 2); g.fill();
}

function drawLineChart(cv, series, markerIdx) {
  const dpr = Math.min(2.5, window.devicePixelRatio || 1);
  const W = cv.clientWidth || 300, H = cv.clientHeight || 130;
  cv.width = W * dpr; cv.height = H * dpr;
  const g = cv.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  const padL = 6, padR = 6, padT = 8, padB = 14;

  let mn = Infinity, mx = -Infinity;
  for (const s of series) {
    s.data.forEach((v, i) => {
      const sd = s.band && Number.isFinite(s.band[i]) ? s.band[i] : 0;
      if (Number.isFinite(v)) { mn = Math.min(mn, v - sd); mx = Math.max(mx, v + sd); }
    });
  }
  if (!Number.isFinite(mn)) { mn = 0; mx = 1; }
  const span = mx - mn || 1;
  const X = (i, n) => padL + (i / (n - 1 || 1)) * (W - padL - padR);
  const Y = (v) => padT + (1 - (v - mn) / span) * (H - padT - padB);

  // grid
  g.strokeStyle = 'rgba(120,150,255,0.12)'; g.lineWidth = 1;
  for (let k = 0; k <= 2; k++) {
    const y = padT + (k / 2) * (H - padT - padB);
    g.beginPath(); g.moveTo(padL, y); g.lineTo(W - padR, y); g.stroke();
  }

  for (const s of series) {
    const n = s.data.length;
    // ±1 s.d. band (std may contain nulls — treated as 0)
    if (s.band) {
      g.fillStyle = s.color + '26';
      g.beginPath();
      s.data.forEach((v, i) => {
        const y = Y((v || 0) + (Number.isFinite(s.band[i]) ? s.band[i] : 0));
        i ? g.lineTo(X(i, n), y) : g.moveTo(X(i, n), y);
      });
      for (let i = n - 1; i >= 0; i--) {
        g.lineTo(X(i, n), Y((s.data[i] || 0) - (Number.isFinite(s.band[i]) ? s.band[i] : 0)));
      }
      g.closePath(); g.fill();
    }
    g.strokeStyle = s.color; g.lineWidth = 1.6;
    g.beginPath();
    s.data.forEach((v, i) => { i ? g.lineTo(X(i, n), Y(v || 0)) : g.moveTo(X(i, n), Y(v || 0)); });
    g.stroke();
  }

  // current-quarter marker
  const n0 = series[0].data.length;
  if (markerIdx != null && n0 > 1) {
    const x = X(Math.min(markerIdx, n0 - 1), n0);
    g.strokeStyle = 'rgba(255,255,255,0.35)'; g.setLineDash([3, 4]);
    g.beginPath(); g.moveTo(x, padT); g.lineTo(x, H - padB); g.stroke();
    g.setLineDash([]);
  }

  // min/max labels
  g.font = '9px Menlo, monospace'; g.fillStyle = '#8b97c4'; g.textAlign = 'left';
  const fmt = (v) => Math.abs(v) >= 1000 ? (v / 1000).toFixed(1) + 'k' : v.toFixed(Math.abs(v) < 10 ? 2 : 0);
  g.fillText(fmt(mx), padL + 2, padT + 8);
  g.fillText(fmt(mn), padL + 2, H - padB - 3);
}

/* ============================================================
 * Run-new-simulation drawer (POST /api/runs per contract)
 * ============================================================ */
const KNOB_KEYS = [
  { key: 'tau_VAT', group: 'parameters', desc: 'VAT rate — raises consumer prices, feeds the tax flow.', pct: true },
  { key: 'r_bar', group: 'initial_conditions', desc: 'Initial policy rate, annualized (UI units; server converts).', pct: true },
  { key: 'psi', group: 'parameters', desc: 'Share of income households consume. psi + psi_H must stay ≤ 1.', pct: false },
  { key: 'zeta_b', group: 'parameters', desc: 'Loan-to-capital cap for new/restarted firms — ease of restarting business.', pct: false },
];
let drawerState = { datasetId: null, knobs: [], launching: false };

$('btn-new-run').addEventListener('click', () => openDrawer());
$('drawer-cancel').addEventListener('click', closeDrawer);
$('drawer-veil').addEventListener('click', closeDrawer);
$('run-progress-chip').addEventListener('click', () => openDrawer());

function closeDrawer() {
  $('drawer').classList.add('hidden');
  $('drawer-veil').classList.add('hidden');
}

async function openDrawer() {
  $('drawer').classList.remove('hidden');
  $('drawer-veil').classList.remove('hidden');
  const dsSel = $('drawer-dataset');
  if (!dsSel.options.length) {
    for (const ds of S.datasets) {
      const opt = document.createElement('option');
      opt.value = ds.id;
      opt.textContent = `${ds.label} (${ds.period})`;
      dsSel.appendChild(opt);
    }
    dsSel.addEventListener('change', () => rebuildDrawerForm(dsSel.value));
    $('drawer-shock').addEventListener('change', buildShockParams);
  }
  const initial = (S.summary && S.summary.dataset_id) || 'AUSTRIA2026Q1';
  dsSel.value = initial;
  if (!dsSel.value) dsSel.selectedIndex = 0;
  await rebuildDrawerForm(dsSel.value);
  buildShockParams();
}

async function rebuildDrawerForm(datasetId) {
  drawerState.datasetId = datasetId;
  const ds = S.datasets.find((d) => d.id === datasetId) || {};
  const scSel = $('drawer-scenario');
  scSel.innerHTML = '';
  for (const sc of ds.scenarios || ['unconditional']) {
    const opt = document.createElement('option');
    opt.value = sc; opt.textContent = sc;
    scSel.appendChild(opt);
  }
  scSel.value = ds.default_scenario || (ds.scenarios && ds.scenarios[0]) || 'unconditional';

  let assets;
  try { assets = await datasetAssets(datasetId); }
  catch (err) { showError('Failed to fetch knobs: ' + err.message); return; }

  const wrap = $('drawer-knobs');
  wrap.innerHTML = '';
  drawerState.knobs = [];
  for (const spec of KNOB_KEYS) {
    const meta = assets.knobs.list.find((k) => k.key === spec.key && k.group === spec.group);
    if (!meta) continue;
    // keep psi + psi_H ≤ 1 (server-side constraint) by capping the slider
    let max = meta.max;
    if (spec.key === 'psi') {
      const psiH = assets.knobs.defaults.psi_H || 0;
      max = Math.min(max, 1 - psiH - 0.001);
    }
    const st = { spec, meta, value: meta.default, min: meta.min, max };
    drawerState.knobs.push(st);

    const el = document.createElement('div');
    el.className = 'knob';
    el.innerHTML = `
      <div class="knob-head">
        <span>${meta.label}</span>
        <span><span class="knob-value"></span><button class="knob-reset hidden">reset</button></span>
      </div>
      <input type="range" min="${st.min}" max="${max}" step="${(max - st.min) / 400}" value="${st.value}">
      <div class="knob-desc">${spec.desc}</div>`;
    const slider = el.querySelector('input');
    const valEl = el.querySelector('.knob-value');
    const resetBtn = el.querySelector('.knob-reset');
    const render = () => {
      valEl.textContent = spec.pct ? fmtPct(st.value, 2) : st.value.toFixed(3);
      const changed = Math.abs(st.value - meta.default) > 1e-9;
      valEl.classList.toggle('changed', changed);
      resetBtn.classList.toggle('hidden', !changed);
    };
    slider.addEventListener('input', () => { st.value = parseFloat(slider.value); render(); });
    resetBtn.addEventListener('click', () => { st.value = meta.default; slider.value = meta.default; render(); });
    render();
    wrap.appendChild(el);
  }
}

function buildShockParams() {
  const type = $('drawer-shock').value;
  const wrap = $('drawer-shock-params');
  const field = (id, label, val, step) =>
    `<label class="shock-param">${label}<input id="${id}" type="number" value="${val}" step="${step}"></label>`;
  if (type === 'interest_rate') {
    wrap.innerHTML = field('shock-rate', 'Added annual rate (e.g. 0.02 = +2pp)', 0.02, 0.005) +
                     field('shock-final', 'Applied through quarter (final_time)', 4, 1);
  } else if (type === 'productivity') {
    wrap.innerHTML = field('shock-mult', 'Productivity multiplier', 1.05, 0.01);
  } else if (type === 'consumption') {
    wrap.innerHTML = field('shock-mult', 'Consumption multiplier', 1.1, 0.01) +
                     field('shock-final', 'Applied through quarter (final_time)', 4, 1);
  } else {
    wrap.innerHTML = '';
  }
}

$('drawer-launch').addEventListener('click', async () => {
  if (drawerState.launching) return;
  // Build the POST body per CONTRACT.md: UI units, changed knobs only.
  const overrides = {};
  for (const st of drawerState.knobs) {
    if (Math.abs(st.value - st.meta.default) > 1e-9) {
      (overrides[st.spec.group] = overrides[st.spec.group] || {})[st.spec.key] =
        Math.round(st.value * 1e6) / 1e6;
    }
  }
  const type = $('drawer-shock').value;
  let shock = { type: 'none' };
  if (type === 'interest_rate') {
    shock = { type, annual_rate: parseFloat($('shock-rate').value) || 0, final_time: parseInt($('shock-final').value, 10) || 4 };
  } else if (type === 'productivity') {
    shock = { type, multiplier: parseFloat($('shock-mult').value) || 1 };
  } else if (type === 'consumption') {
    shock = { type, multiplier: parseFloat($('shock-mult').value) || 1, final_time: parseInt($('shock-final').value, 10) || 4 };
  }
  const body = {
    dataset_id: drawerState.datasetId,
    scenario: $('drawer-scenario').value,
    sim: { T: 12, n_sims: 4, base_seed: 1000 + Math.floor(Math.random() * 90000) },
    overrides,
    shock,
  };

  drawerState.launching = true;
  $('drawer-launch').disabled = true;
  $('drawer-status').classList.remove('hidden');
  $('drawer-status-text').classList.remove('err');
  $('drawer-status-text').textContent = 'submitting…';
  try {
    const res = await AtlasAPI.json('/api/runs', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    S.overridesByRun[res.run_id] = overrides; // so derived taxes use the new knob values
    pollRun(res.run_id);
  } catch (err) {
    $('drawer-status-text').classList.add('err');
    $('drawer-status-text').textContent = 'Launch failed: ' + err.message;
    drawerState.launching = false;
    $('drawer-launch').disabled = false;
  }
});

/* Poll /api/runs/{id}/status every ~1.5s until done/error. */
function pollRun(runId) {
  S.pollingRunId = runId;
  const chip = $('run-progress-chip');
  chip.classList.remove('hidden');
  const tick = async () => {
    let st;
    try {
      st = await AtlasAPI.json(`/api/runs/${runId}/status`);
    } catch (err) {
      $('drawer-status-text').classList.add('err');
      $('drawer-status-text').textContent = 'Status poll failed: ' + err.message;
      chip.classList.add('hidden');
      drawerState.launching = false;
      $('drawer-launch').disabled = false;
      return;
    }
    const pct = Math.round((st.progress || 0) * 100);
    $('drawer-progress').style.width = pct + '%';
    $('drawer-status-text').textContent = `${st.state} · ${pct}% · ${st.message || ''}`;
    chip.textContent = `sim ${pct}%`;
    if (st.state === 'done') {
      chip.classList.add('hidden');
      drawerState.launching = false;
      $('drawer-launch').disabled = false;
      $('drawer-status-text').textContent = 'done — loading result';
      try {
        S.runs = await AtlasAPI.json('/api/runs');
        populateRunSelect();
        $('run-select').value = runId;
        await loadRun(runId);
        closeDrawer();
        $('drawer-status').classList.add('hidden');
      } catch (err) { showError('Loading finished run failed: ' + err.message); }
    } else if (st.state === 'error') {
      chip.classList.add('hidden');
      drawerState.launching = false;
      $('drawer-launch').disabled = false;
      $('drawer-status-text').classList.add('err');
      $('drawer-status-text').textContent = 'Run failed: ' + (st.message || 'unknown error');
    } else {
      S.pollTimer = setTimeout(tick, 1500);
    }
  };
  tick();
}

/* ============================================================
 * Error banner
 * ============================================================ */
function showError(msg) {
  $('error-text').textContent = msg;
  $('error-banner').classList.remove('hidden');
}
function hideError() { $('error-banner').classList.add('hidden'); }
$('error-retry').addEventListener('click', boot);

$('run-select').addEventListener('change', (e) => loadRun(e.target.value));

/* ============================================================
 * Go
 * ============================================================ */
Renderer.init(canvas);
boot();
requestAnimationFrame((ts) => { lastTs = ts; requestAnimationFrame(frame); });
