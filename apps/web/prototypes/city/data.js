/* data.js — API access + the economics of Econopolis.
   Turns a BeforeIT run summary into a "timeline" the city can render:
   per-quarter district GVA indices, inflation, policy rate, trade, headlines. */
window.Econ = (function () {
  'use strict';

  /* ---------- the 12 districts (1-based sector ranges into I_s / N_s / real_sector_gva) ---------- */
  var GROUPS = [
    { id: 'AGRI',  name: 'Agriculture & Resources',        a: 1,  b: 4  },
    { id: 'MANU',  name: 'Manufacturing',                  a: 5,  b: 23 },
    { id: 'UTIL',  name: 'Energy & Utilities',             a: 24, b: 26 },
    { id: 'CONS',  name: 'Construction',                   a: 27, b: 27 },
    { id: 'TRADE', name: 'Trade & Retail',                 a: 28, b: 30 },
    { id: 'TRANS', name: 'Transport & Logistics',          a: 31, b: 35 },
    { id: 'HOSP',  name: 'Hotels & Restaurants',           a: 36, b: 36 },
    { id: 'ICT',   name: 'Information & Media',            a: 37, b: 40 },
    { id: 'FIN',   name: 'Finance & Real Estate',          a: 41, b: 44 },
    { id: 'PROF',  name: 'Professional & Business Svcs',   a: 45, b: 53 },
    { id: 'PUB',   name: 'Public, Health & Education',     a: 54, b: 57 },
    { id: 'ARTS',  name: 'Arts & Other Services',          a: 58, b: 62 }
  ];

  /* consistent 12-hue night palette (district identity everywhere in the UI) */
  var COLORS = {
    AGRI: '#74c95c', MANU: '#e08b45', UTIL: '#ecc94b', CONS: '#bd9a5f',
    TRADE: '#f0567d', TRANS: '#46b1e6', HOSP: '#e26bd2', ICT: '#7f76f2',
    FIN: '#35d9a4', PROF: '#5f86ef', PUB: '#8fa5bd', ARTS: '#b56ef0'
  };

  /* short verbs for the ticker, keyed by district id */
  var TICKER_NOUN = {
    AGRI: 'Farm belt', MANU: 'Manufacturing', UTIL: 'The power grid', CONS: 'Construction',
    TRADE: 'Trade & retail', TRANS: 'Transport', HOSP: 'Hotels & restaurants', ICT: 'The tech quarter',
    FIN: 'Finance', PROF: 'Business services', PUB: 'The public sector', ARTS: 'The arts scene'
  };

  /* Offline fallbacks (AUSTRIA2026Q1 values) so the city can still be drawn
     if /api/datasets/value is unreachable. */
  var FALLBACK_I_S = [5,1,1,1,5,3,3,1,1,1,1,1,1,2,1,4,1,1,1,1,1,7,3,5,1,2,43,15,24,52,14,1,1,2,1,48,2,5,1,25,3,1,11,25,34,19,2,18,23,3,2,2,20,28,22,60,18,21,9,1,2,39];
  var FALLBACK_N_S = [23,7,1,5,89,12,31,16,8,2,21,22,31,27,41,75,35,49,97,34,16,37,24,30,2,23,292,75,209,347,126,1,8,59,25,268,15,12,14,90,74,27,16,58,123,56,21,23,23,12,83,11,134,281,321,277,193,31,24,52,2,39];
  /* contract defaults, used if /api/knobs is unreachable */
  var FALLBACK_KNOBS = {
    tau_INC: 0.212, tau_FIRM: 0.1625, tau_VAT: 0.1391, tau_SIF: 0.2059, tau_SIW: 0.19,
    psi: 0.8447, psi_H: 0.0877, theta_UB: 0.3511, zeta_b: 0.5,
    sb_other: 0.8854, sb_inact: 4.6627, w_UB: 6.5964, r_bar: 0.0205,
    zeta: 0.03, zeta_LTV: 0.6, mu: -0.0005
  };

  var HOUSEHOLDS = { total: 9215, active: 5085, inactive: 4130, employed0: 4180 };

  /* ---------- small utils ---------- */
  function fetchJSON(url, opts) {
    return fetch(url, opts).then(function (r) {
      if (!r.ok) return r.text().then(function (t) {
        throw new Error(url.split('?')[0] + ' -> HTTP ' + r.status + (t ? ' ' + t.slice(0, 140) : ''));
      });
      return r.json();
    });
  }
  function safeDiv(a, b, fb) { return (b == null || b === 0 || !isFinite(b)) ? fb : a / b; }
  /* null/NaN guard for summary mean/std arrays (contract: std may contain nulls) */
  function sanitize(arr, fb) {
    var out = [], prev = (fb == null ? 0 : fb);
    for (var i = 0; i < (arr ? arr.length : 0); i++) {
      var v = arr[i];
      if (typeof v === 'number' && isFinite(v)) prev = v;
      out.push(prev);
    }
    return out;
  }
  function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }
  function lerp(a, b, t) { return a + (b - a) * t; }
  /* linear sample of a per-quarter series at fractional quarter qt */
  function sample(series, qt) {
    var n = series.length;
    if (n === 0) return 0;
    if (qt <= 0) return series[0];
    if (qt >= n - 1) return series[n - 1];
    var i = Math.floor(qt);
    return lerp(series[i], series[i + 1], qt - i);
  }

  /* ---------- formatting ---------- */
  function fmtBn(v) { // model units ≈ € millions/quarter
    var neg = v < 0 ? '−' : '';
    v = Math.abs(v);
    if (v >= 1000) return neg + '€' + (v / 1000).toFixed(1) + 'bn';
    return neg + '€' + v.toFixed(0) + 'm';
  }
  function fmtSignedBn(v) { return (v >= 0 ? '+' : '') + fmtBn(v).replace('−', '-'); }
  function fmtPct(v, d) { return (v * 100).toFixed(d == null ? 1 : d) + '%'; }
  function fmtSignedPct(v, d) { return (v >= 0 ? '+' : '') + (v * 100).toFixed(d == null ? 1 : d) + '%'; }

  /* ---------- timeline: everything the city needs, per quarter ---------- */
  function buildTimeline(sum) {
    var periods = sum.periods || [];
    var T = periods.length - 1;
    var defl = sanitize(sum.gdp_deflator.mean, 1);
    var gdp = sanitize(sum.real_gdp.mean, 0);
    var cons = sanitize(sum.real_household_consumption.mean, 0);
    var gov = sanitize(sum.real_government_consumption.mean, 0);
    var inv = sanitize(sum.real_fixed_capitalformation.mean, 0);
    var exp_ = sanitize(sum.real_exports.mean, 0);
    var imp = sanitize(sum.real_imports.mean, 0);
    var wages = sanitize(sum.wages.mean, 0);
    var rateA = sanitize(sum.euribor_annual.mean, 0.02);

    // per-quarter, per-group real GVA and index (normalized to quarter 0)
    var sectorGva = [];      // [t][62] sanitized
    var groupGva = [];       // [t][12]
    for (var t = 0; t <= T; t++) {
      var row = sanitize(sum.real_sector_gva.mean[t], 0);
      sectorGva.push(row);
      groupGva.push(GROUPS.map(function (g) {
        var s = 0;
        for (var i = g.a - 1; i < g.b; i++) s += (row[i] || 0);
        return s;
      }));
    }
    var groupIdx = groupGva.map(function (row) {
      return row.map(function (v, g) { return safeDiv(v, groupGva[0][g], 1); });
    });

    // inflation YoY (fall back to annualized QoQ for the first 4 quarters)
    var inflYoY = [];
    for (t = 0; t <= T; t++) {
      if (t >= 4) inflYoY.push(safeDiv(defl[t], defl[t - 4], 1) - 1);
      else if (t >= 1) inflYoY.push(Math.pow(safeDiv(defl[t], defl[t - 1], 1), 4) - 1);
      else inflYoY.push(null);
    }
    if (inflYoY[0] == null) inflYoY[0] = (T >= 1 ? inflYoY[1] : 0.02);

    var tradeBal = exp_.map(function (x, i) { return x - imp[i]; });
    var tradeVol = exp_.map(function (x, i) { return x + imp[i]; });
    // employment proxy: real wage bill normalized to quarter 0 (per contract framing)
    var rw0 = safeDiv(wages[0], defl[0], 1);
    var realWageIdx = wages.map(function (w, i) { return safeDiv(safeDiv(w, defl[i], rw0), rw0, 1); });

    var tl = {
      runId: sum.run_id, datasetId: sum.dataset_id, scenario: sum.scenario,
      periods: periods, T: T, defl: defl, gdp: gdp, cons: cons, gov: gov, inv: inv,
      exp: exp_, imp: imp, wages: wages, rateA: rateA,
      sectorGva: sectorGva, groupGva: groupGva, groupIdx: groupIdx,
      inflYoY: inflYoY, tradeBal: tradeBal, tradeVol: tradeVol, realWageIdx: realWageIdx,
      overridesApplied: null, shockApplied: null, cardNames: null
    };
    tl.headlines = buildHeadlines(tl);
    return tl;
  }

  /* ---------- news ticker: rank notable quarter-over-quarter changes ---------- */
  function periodYear(p) { var m = /^(\d{4})/.exec(p || ''); return m ? +m[1] : 0; }

  function buildHeadlines(tl) {
    var out = [[]];                                   // index 0: no news yet
    for (var t = 1; t <= tl.T; t++) {
      var cand = [];
      var period = tl.periods[t];

      // district moves
      for (var g = 0; g < GROUPS.length; g++) {
        var pct = safeDiv(tl.groupIdx[t][g], tl.groupIdx[t - 1][g], 1) - 1;
        if (Math.abs(pct) < 0.004) continue;
        var noun = TICKER_NOUN[GROUPS[g].id];
        var verb = pct > 0.015 ? 'booms' : pct > 0 ? 'expands' : pct < -0.015 ? 'slumps' : 'cools';
        var text = noun + ' ' + verb + ' ' + fmtSignedPct(pct);
        // flourish: sharpest move this calendar year so far
        var yr = periodYear(period), best = true;
        for (var k = 1; k < t; k++) {
          if (periodYear(tl.periods[k]) !== yr) continue;
          var p2 = safeDiv(tl.groupIdx[k][g], tl.groupIdx[k - 1][g], 1) - 1;
          if (pct > 0 ? p2 >= pct : p2 <= pct) { best = false; break; }
        }
        if (best && Math.abs(pct) > 0.012 && t > 1) {
          text += pct > 0 ? ' — sharpest rise this year' : ' — worst quarter this year';
        }
        cand.push({ w: Math.abs(pct) * 100, text: text, cls: pct > 0 ? 'up' : 'down' });
      }

      // GDP
      var dg = safeDiv(tl.gdp[t], tl.gdp[t - 1], 1) - 1;
      if (Math.abs(dg) > 0.002) {
        cand.push({
          w: Math.abs(dg) * 140 + 0.25,
          text: 'Econopolis GDP ' + (dg > 0 ? 'grows ' : 'shrinks ') + fmtSignedPct(dg) + ' this quarter',
          cls: dg > 0 ? 'up' : 'down'
        });
      }

      // inflation
      var di = tl.inflYoY[t] - tl.inflYoY[t - 1];
      if (Math.abs(di) > 0.0012) {
        cand.push({
          w: Math.abs(di) * 320,
          text: 'Inflation ' + (di < 0 ? 'cools to ' : 'heats up to ') + fmtPct(tl.inflYoY[t]),
          cls: di < 0 ? 'up' : 'down'
        });
      }

      // policy rate
      var dr = tl.rateA[t] - tl.rateA[t - 1];
      if (Math.abs(dr) > 0.0004) {
        cand.push({
          w: Math.abs(dr) * 900,
          text: 'Central bank ' + (dr > 0 ? 'lifts' : 'cuts') + ' the rate to ' + fmtPct(tl.rateA[t], 2),
          cls: 'flat'
        });
      } else if (t % 4 === 0) {
        cand.push({ w: 0.3, text: 'Central bank holds at ' + fmtPct(tl.rateA[t], 2), cls: 'flat' });
      }

      // harbor
      var dx = safeDiv(tl.exp[t], tl.exp[t - 1], 1) - 1;
      if (Math.abs(dx) > 0.012) {
        cand.push({
          w: Math.abs(dx) * 80,
          text: 'Harbor ' + (dx > 0 ? 'hums: exports up ' : 'quiet: exports down ') + fmtSignedPct(dx),
          cls: dx > 0 ? 'up' : 'down'
        });
      }

      cand.sort(function (a, b) { return b.w - a.w; });
      out.push(cand.slice(0, 3).map(function (c) { return { period: period, text: c.text, cls: c.cls }; }));
    }
    return out;
  }

  /* ---------- derived money flows (contract recipes) — label these "derived" ---------- */
  function derivedFlows(tl, t, knobs) {
    var k = knobs || FALLBACK_KNOBS;
    var defl = tl.defl[t];
    var C = tl.cons[t] * defl;
    var G = tl.gov[t] * defl;
    var W = tl.wages[t];               // already nominal
    var nomGDP = tl.gdp[t] * defl;
    return {
      nomGDP: nomGDP, C: C, G: G,
      X: tl.exp[t] * defl, M: tl.imp[t] * defl, I: tl.inv[t] * defl, W: W,
      vat: (k.tau_VAT || 0) * C,
      incomeTax: (k.tau_INC || 0) * W,
      socialIns: ((k.tau_SIF || 0) + (k.tau_SIW || 0)) * W,
      corpTax: (k.tau_FIRM || 0) * Math.max(0, nomGDP - W),
      benefits: ((k.sb_inact || 0) * HOUSEHOLDS.inactive + (k.sb_other || 0) * HOUSEHOLDS.total) * defl
    };
  }

  /* top-N member sectors of a district by GVA at quarter t */
  function topSectors(tl, g, t, meta, n) {
    var grp = GROUPS[g], list = [];
    var tot = tl.groupGva[t][g] || 1;
    for (var i = grp.a - 1; i < grp.b; i++) {
      list.push({
        i: i,
        label: (meta && meta[i]) ? meta[i].label : ('sector ' + (i + 1)),
        code: (meta && meta[i]) ? meta[i].code : '',
        gva: tl.sectorGva[t][i],
        share: safeDiv(tl.sectorGva[t][i], tot, 0)
      });
    }
    list.sort(function (a, b) { return b.gva - a.gva; });
    return list.slice(0, n || 3);
  }

  /* ---------- the policy card deck ----------
     build(D) -> partial payload; D = live knob defaults map.
     kind 'shock' cards are mutually exclusive (shock types cannot combine). */
  function r6(v) { return Math.round(v * 1e6) / 1e6; }
  var CARDS = [
    {
      id: 'vat', name: 'VAT Holiday', kind: 'fiscal', mono: 'VH',
      flavor: 'Slash the sales tax and let the tills ring.',
      dials: ['tau_VAT: 13.9% → 9.9% (−4pp)'],
      build: function (D) { return { overrides: { parameters: { tau_VAT: r6(Math.max(0, D.tau_VAT - 0.04)) } } }; }
    },
    {
      id: 'corp', name: 'Corporate Squeeze', kind: 'fiscal', mono: 'CS',
      flavor: 'Firms tighten their belts so the treasury can loosen its own.',
      dials: ['tau_FIRM: 16.3% → 21.3% (+5pp)'],
      build: function (D) { return { overrides: { parameters: { tau_FIRM: r6(Math.min(0.8, D.tau_FIRM + 0.05)) } } }; }
    },
    {
      id: 'startup', name: 'Restart Credit', kind: 'credit', mono: 'RC',
      flavor: 'Refinance insolvent firms with a larger restart loan.',
      dials: ['zeta_b: 0.50 → 0.80 (restart loan-to-capital ratio; firm count stays fixed)'],
      build: function () { return { overrides: { parameters: { zeta_b: 0.8 } } }; }
    },
    {
      id: 'tight', name: 'Tight Money', kind: 'shock', mono: 'TM',
      flavor: 'The central bank slams the brakes for a full year.',
      dials: ['shock: interest_rate +2pp (annual), quarters 1–4'],
      build: function () { return { shock: { type: 'interest_rate', annual_rate: 0.02, final_time: 4 } }; }
    },
    {
      id: 'boom', name: 'Consumption Boom', kind: 'shock', mono: 'CB',
      flavor: 'Households spend like the future is cancelled.',
      dials: ['shock: consumption ×1.10, quarters 1–4'],
      build: function () { return { shock: { type: 'consumption', multiplier: 1.10, final_time: 4 } }; }
    },
    {
      id: 'prod', name: 'Productivity Miracle', kind: 'shock', mono: 'PM',
      flavor: 'Every worker suddenly does 5% more before lunch.',
      dials: ['shock: productivity ×1.05'],
      build: function () { return { shock: { type: 'productivity', multiplier: 1.05 } }; }
    },
    {
      id: 'heli', name: 'Helicopter Benefits', kind: 'welfare', mono: 'HB',
      flavor: 'Social benefits rain gently over the residential quarter.',
      dials: ['sb_inact: +50%', 'sb_other: +50%'],
      build: function (D) {
        return { overrides: { initial_conditions: {
          sb_inact: r6(Math.min(100, D.sb_inact * 1.5)),
          sb_other: r6(Math.min(100, D.sb_other * 1.5))
        } } };
      }
    },
    {
      id: 'safety', name: 'Wage Safety Net', kind: 'welfare', mono: 'WS',
      flavor: 'Losing your job now pays 55% of your old wage.',
      dials: ['theta_UB: 0.35 → 0.55 (benefit replacement rate)'],
      build: function () { return { overrides: { parameters: { theta_UB: 0.55 } } }; }
    }
  ];

  /* Merge selected cards into one POST /api/runs payload (contract shape).
     Changed-knobs-only, UI units; shock defaults to {type:"none"}. */
  function buildRunPayload(selectedIds, knobDefaults, datasetId) {
    var D = knobDefaults || FALLBACK_KNOBS;
    var params = {}, inits = {}, shock = { type: 'none' };
    CARDS.forEach(function (c) {
      if (selectedIds.indexOf(c.id) === -1) return;
      var part = c.build(D);
      if (part.overrides) {
        var p = part.overrides.parameters || {};
        Object.keys(p).forEach(function (k) { params[k] = p[k]; });
        var ic = part.overrides.initial_conditions || {};
        Object.keys(ic).forEach(function (k) { inits[k] = ic[k]; });
      }
      if (part.shock) shock = part.shock;          // exclusivity enforced by UI
    });
    var overrides = {};
    if (Object.keys(params).length) overrides.parameters = params;
    if (Object.keys(inits).length) overrides.initial_conditions = inits;
    var body = {
      dataset_id: datasetId || 'AUSTRIA2026Q1',
      scenario: 'baseline',
      sim: { T: 12, n_sims: 4, base_seed: 1000 + Math.floor(Math.random() * 90000) },
      shock: shock
    };
    if (Object.keys(overrides).length) body.overrides = overrides;
    return body;
  }

  return {
    GROUPS: GROUPS, COLORS: COLORS, CARDS: CARDS, HOUSEHOLDS: HOUSEHOLDS,
    FALLBACK_I_S: FALLBACK_I_S, FALLBACK_N_S: FALLBACK_N_S, FALLBACK_KNOBS: FALLBACK_KNOBS,
    fetchJSON: fetchJSON, safeDiv: safeDiv, sanitize: sanitize, clamp: clamp, lerp: lerp, sample: sample,
    buildTimeline: buildTimeline, derivedFlows: derivedFlows, topSectors: topSectors,
    buildRunPayload: buildRunPayload,
    fmtBn: fmtBn, fmtSignedBn: fmtSignedBn, fmtPct: fmtPct, fmtSignedPct: fmtSignedPct
  };
})();
