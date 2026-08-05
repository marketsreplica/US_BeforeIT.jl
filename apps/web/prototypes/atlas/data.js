'use strict';
/* ============================================================
 * Flow Atlas — data layer
 * API access, sector grouping, and the derived money-flow
 * recipes from CONTRACT.md. Everything flow-related here is an
 * ESTIMATE reconstructed from aggregate simulation output; the
 * UI labels these with a "derived" badge.
 * ============================================================ */

/* ---------- tiny fetch helper ---------- */
const AtlasAPI = {
  async json(url, opts) {
    const res = await fetch(url, opts);
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`HTTP ${res.status} ${url} ${body.slice(0, 200)}`);
    }
    return res.json();
  },
};

/* ---------- the 12 sector groups (1-based sector indices) ---------- */
const GROUP_DEFS = [
  { id: 'AGRI',  name: 'Agriculture & Resources',       short: 'Agriculture',    from: 1,  to: 4,  color: '#7ed957' },
  { id: 'MANU',  name: 'Manufacturing',                 short: 'Manufacturing',  from: 5,  to: 23, color: '#ff9440' },
  { id: 'UTIL',  name: 'Energy & Utilities',            short: 'Utilities',      from: 24, to: 26, color: '#ffd23f' },
  { id: 'CONS',  name: 'Construction',                  short: 'Construction',   from: 27, to: 27, color: '#ff6047' },
  { id: 'TRADE', name: 'Trade & Retail',                short: 'Trade & Retail', from: 28, to: 30, color: '#2fd6c3' },
  { id: 'TRANS', name: 'Transport & Logistics',         short: 'Transport',      from: 31, to: 35, color: '#38a6ff' },
  { id: 'HOSP',  name: 'Hotels & Restaurants',          short: 'Hospitality',    from: 36, to: 36, color: '#ff5f95' },
  { id: 'ICT',   name: 'Information & Media',           short: 'Info & Media',   from: 37, to: 40, color: '#9d6bff' },
  { id: 'FIN',   name: 'Finance & Real Estate',         short: 'Finance & RE',   from: 41, to: 44, color: '#5f7cff' },
  { id: 'PROF',  name: 'Professional & Business Svcs',  short: 'Professional',   from: 45, to: 53, color: '#c95dff' },
  { id: 'PUB',   name: 'Public, Health & Education',    short: 'Public & Health',from: 54, to: 57, color: '#35d07a' },
  { id: 'ARTS',  name: 'Arts & Other Services',         short: 'Arts & Other',   from: 58, to: 62, color: '#f45fd0' },
];

/* ---------- flow catalogue ----------
 * Each bundled flow knows its endpoints, color, formula text and
 * how firm-side values are split across the 12 group nodes.
 * basis: 'b_HH' | 'c_G' | 'c_E' | 'c_I' | 'gva' | null (anchor↔anchor)
 */
const FLOW_DEFS = [
  { id: 'CONS',  name: 'Consumption',    from: 'HH',    to: 'FIRMS', color: '#ffc86b', basis: 'b_HH',
    formula: 'C = real_household_consumption[t] × deflator[t]',
    note: 'split across groups by household basket b_HH_g' },
  { id: 'WAGES', name: 'Wages',          from: 'FIRMS', to: 'HH',    color: '#49e3c2', basis: 'gva',
    formula: 'W = wages[t]  (nominal)',
    note: 'split across groups by share of real sector GVA' },
  { id: 'GOV',   name: 'Gov purchases',  from: 'GOV',   to: 'FIRMS', color: '#b18cff', basis: 'c_G',
    formula: 'G = real_government_consumption[t] × deflator[t]',
    note: 'split across groups by gov purchase basket c_G_g' },
  { id: 'BEN',   name: 'Social benefits',from: 'GOV',   to: 'HH',    color: '#d6b3ff', basis: null,
    formula: 'B = (sb_inact × 4,130 + sb_other × 9,215) × deflator[t]',
    note: 'pensions, unemployment and other transfers (rough)' },
  { id: 'HHTAX', name: 'VAT + income tax + social insurance', from: 'HH', to: 'GOV', color: '#ff8a5c', basis: null,
    formula: 'tau_VAT×C + tau_INC×W + (tau_SIF+tau_SIW)×W',
    note: 'employer social insurance (tau_SIF) is nominally paid by firms but bundled here' },
  { id: 'CORP',  name: 'Corporate tax',  from: 'FIRMS', to: 'GOV',   color: '#ff6d6d', basis: 'gva',
    formula: 'tau_FIRM × max(0, nominal GDP − W)  (rough)',
    note: 'split across groups by share of real sector GVA' },
  { id: 'EXP',   name: 'Exports',        from: 'ROW',   to: 'FIRMS', color: '#5ee08a', basis: 'c_E',
    formula: 'X = real_exports[t] × deflator[t]',
    note: 'foreign demand paid to firms; split by export basket c_E_g' },
  { id: 'IMP',   name: 'Imports',        from: 'FIRMS', to: 'ROW',   color: '#ff8fa3', basis: 'c_I',
    formula: 'M = real_imports[t] × deflator[t]',
    note: 'payments abroad for imported inputs/goods; split by import basket c_I_g' },
  { id: 'INV',   name: 'Investment (firms ↔ firms)', from: 'FIRMS', to: 'FIRMS', color: '#6fa8ff', basis: null,
    formula: 'I = real_fixed_capitalformation[t] × deflator[t]',
    note: 'capital formation circulating inside the firm ring — drawn as a halo' },
];

/* ---------- anchor node metadata (positions set by render layout) ---------- */
const ANCHOR_DEFS = {
  HH:   { id: 'HH',   name: 'Households',    color: '#ffc86b' },
  GOV:  { id: 'GOV',  name: 'Government',    color: '#b18cff' },
  CB:   { id: 'CB',   name: 'Central Bank',  color: '#7ef0ff' },
  BANK: { id: 'BANK', name: 'Bank',          color: '#9fb4e8' },
  ROW:  { id: 'ROW',  name: 'Rest of World', color: '#5ee08a' },
};

/* ---------- helpers ---------- */

// Flatten possibly-nested vectors (c_E_g arrives with shape [62,1]).
function flattenVec(v) {
  if (!Array.isArray(v)) return null;
  return v.map((x) => (Array.isArray(x) ? x[0] : x)).map((x) => (Number.isFinite(x) ? x : 0));
}

// Sum vector entries over a group's 1-based [from..to] range.
function groupSum(vec, g) {
  let s = 0;
  for (let i = g.from - 1; i < g.to; i++) s += vec[i] || 0;
  return s;
}

// Normalize a 12-vector of group sums into shares; guard zero totals.
function normalizeShares(arr) {
  const tot = arr.reduce((a, b) => a + b, 0);
  if (!(tot > 0)) return arr.map(() => 1 / arr.length);
  return arr.map((v) => v / tot);
}

// Linear interpolation into a per-quarter array at fractional time tf.
function sampleSeries(arr, tf) {
  if (!arr || !arr.length) return 0;
  const n = arr.length;
  const t = Math.max(0, Math.min(n - 1, tf));
  const i0 = Math.floor(t), i1 = Math.min(n - 1, i0 + 1);
  const a = Number.isFinite(arr[i0]) ? arr[i0] : 0;
  const b = Number.isFinite(arr[i1]) ? arr[i1] : a;
  return a + (b - a) * (t - i0);
}

/* ---------- formatting ---------- */
// Model units ≈ millions of euro per quarter.
function fmtBn(v) {
  const bn = v / 1000;
  const abs = Math.abs(bn);
  const dp = abs >= 100 ? 1 : abs >= 10 ? 1 : 2;
  return (bn < 0 ? '−' : '') + '€' + abs.toFixed(dp) + 'bn';
}
function fmtModel(v) {
  return Math.round(v).toLocaleString('en-US') + ' mu';
}
function fmtPct(v, dp) {
  return (v * 100).toFixed(dp == null ? 2 : dp) + '%';
}
function fmtDate(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return iso || '';
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ' ' +
         d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

/* ============================================================
 * buildDerived(summary, knobDefaults, vectors, overrides)
 * Precomputes, per quarter t = 0..T:
 *   - nominal aggregates and every derived flow value
 *   - group GVA totals and per-quarter GVA shares
 *   - KPI series (inflation YoY, trade balance)
 * knobDefaults: {key: default} from /api/knobs (dataset-specific)
 * overrides:    {parameters:{}, initial_conditions:{}} if we
 *               launched this run ourselves and tracked them.
 * ============================================================ */
function buildDerived(summary, knobDefaults, vectors, overrides) {
  const T1 = summary.periods.length; // T+1 samples
  const mean = (k) => (summary[k] && summary[k].mean) || [];
  const defl = mean('gdp_deflator');
  const gdp = mean('real_gdp');
  const cons = mean('real_household_consumption');
  const gov = mean('real_government_consumption');
  const inv = mean('real_fixed_capitalformation');
  const exp_ = mean('real_exports');
  const imp = mean('real_imports');
  const wages = mean('wages');
  const eurA = mean('euribor_annual');

  // Effective knob values: dataset default unless overridden in this run.
  const ov = overrides || {};
  const ovP = ov.parameters || {}, ovI = ov.initial_conditions || {};
  const K = (key) => {
    if (key in ovP) return ovP[key];
    if (key in ovI) return ovI[key];
    return knobDefaults[key] != null ? knobDefaults[key] : 0;
  };

  const tauVAT = K('tau_VAT'), tauINC = K('tau_INC'), tauSI = K('tau_SIF') + K('tau_SIW');
  const tauFIRM = K('tau_FIRM');
  const sbInact = K('sb_inact'), sbOther = K('sb_other');
  const N_INACTIVE = 4130, N_ALL_HH = 9215; // 5,085 active + 4,130 inactive

  const D = {
    defl: [], nomGDP: [], C: [], W: [], G: [], BEN: [], HHTAX: [], CORP: [],
    EXP: [], IMP: [], INV: [], rate: [], inflYoY: [], tradeBal: [],
    hhTaxParts: [], // [vat, inc, si] per t, for the tooltip breakdown
  };

  for (let t = 0; t < T1; t++) {
    const d = Number.isFinite(defl[t]) && defl[t] > 0 ? defl[t] : 1;
    const W = Number.isFinite(wages[t]) ? wages[t] : 0;
    const C = (cons[t] || 0) * d;
    const nom = (gdp[t] || 0) * d;
    D.defl.push(d);
    D.nomGDP.push(nom);
    D.C.push(C);
    D.W.push(W);
    D.G.push((gov[t] || 0) * d);
    D.BEN.push((sbInact * N_INACTIVE + sbOther * N_ALL_HH) * d);
    const vat = tauVAT * C, inc = tauINC * W, si = tauSI * W;
    D.HHTAX.push(vat + inc + si);
    D.hhTaxParts.push([vat, inc, si]);
    D.CORP.push(tauFIRM * Math.max(0, nom - W));
    D.EXP.push((exp_[t] || 0) * d);
    D.IMP.push((imp[t] || 0) * d);
    D.INV.push((inv[t] || 0) * d);
    D.rate.push(Number.isFinite(eurA[t]) ? eurA[t] : 0);
    D.tradeBal.push(((exp_[t] || 0) - (imp[t] || 0)) * d);

    // Inflation, year over year where 4 quarters of history exist,
    // otherwise annualized from the available window.
    let infl = 0;
    if (t >= 4 && defl[t - 4] > 0) infl = d / defl[t - 4] - 1;
    else if (t >= 1 && defl[0] > 0) infl = Math.pow(d / defl[0], 4 / t) - 1;
    else if (T1 > 1 && defl[0] > 0 && defl[1] > 0) infl = Math.pow(defl[1] / defl[0], 4) - 1;
    D.inflYoY.push(infl);
  }

  // Group GVA per quarter (12 groups) and its share basis.
  const sg = summary.real_sector_gva && summary.real_sector_gva.mean;
  const groupGVA = [];   // [t][12]
  const gvaShare = [];   // [t][12]
  for (let t = 0; t < T1; t++) {
    const row = (sg && sg[t]) || [];
    const sums = GROUP_DEFS.map((g) => Math.max(0, groupSum(row, g)));
    groupGVA.push(sums);
    gvaShare.push(normalizeShares(sums));
  }

  // Static basket-based share bases (fall back to first-quarter GVA shares).
  const basisShares = { gva: null }; // gva handled per-t
  const basketFor = { b_HH: 'b_HH_g', c_G: 'c_G_g', c_E: 'c_E_g', c_I: 'c_I_g' };
  for (const [basis, vecKey] of Object.entries(basketFor)) {
    const vec = vectors[vecKey];
    basisShares[basis] = vec
      ? normalizeShares(GROUP_DEFS.map((g) => Math.max(0, groupSum(vec, g))))
      : gvaShare[0].slice();
  }

  // Per-group firm counts / employment.
  const I_s = vectors.I_s || [];
  const N_s = vectors.N_s || [];
  const groupFirms = GROUP_DEFS.map((g) => Math.round(groupSum(I_s, g)));
  const groupEmp = GROUP_DEFS.map((g) => Math.round(groupSum(N_s, g)));

  return { D, groupGVA, gvaShare, basisShares, groupFirms, groupEmp, T1 };
}

/* Value of a bundled flow at fractional time tf (model units, nominal). */
function flowValue(derived, flowId, tf) {
  return sampleSeries(derived.D[flowId], tf);
}

/* Share of a group g (0-based) in a flow's firm-side split at time tf. */
function flowGroupShare(derived, flow, gIdx, tf) {
  if (flow.basis === 'gva') {
    const t0 = Math.max(0, Math.min(derived.T1 - 1, Math.floor(tf)));
    const t1 = Math.min(derived.T1 - 1, t0 + 1);
    const f = Math.max(0, Math.min(1, tf - t0));
    return derived.gvaShare[t0][gIdx] * (1 - f) + derived.gvaShare[t1][gIdx] * f;
  }
  const s = derived.basisShares[flow.basis];
  return s ? s[gIdx] : 0;
}
