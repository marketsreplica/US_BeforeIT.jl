/* ── app.js — Twin Lab orchestrator ──────────────────────────────────────
 * Universe A (control) vs Universe B (treatment): two runs of the same
 * agent-based economy, aligned by quarter labels and diffed everywhere.
 *
 * Economics notes for the derived series:
 *  • Inflation is DERIVED from the GDP deflator: year-on-year where four
 *    lagged quarters exist, annualized quarter-on-quarter for the first
 *    three forecast quarters (marked "derived" in the UI).
 *  • Trade balance = real_exports − real_imports (both model series);
 *    its ±1σ band combines the two stds in quadrature (independence
 *    approximation) — also marked "derived".
 */
(function () {
  'use strict';

  var API = '/api';                       // absolute per contract
  var PREFERRED_DATASET = 'AUSTRIA2026Q1';
  var META_KEY = 'twinlab_run_meta';      // fallback provenance for runs this page created

  // 62 sectors → 12 lab groups (1-based inclusive ranges)
  var GROUPS = [
    { code: 'AGRI',  name: 'Agriculture & Resources',        from: 1,  to: 4 },
    { code: 'MANU',  name: 'Manufacturing',                  from: 5,  to: 23 },
    { code: 'UTIL',  name: 'Energy & Utilities',             from: 24, to: 26 },
    { code: 'CONS',  name: 'Construction',                   from: 27, to: 27 },
    { code: 'TRADE', name: 'Trade & Retail',                 from: 28, to: 30 },
    { code: 'TRANS', name: 'Transport & Logistics',          from: 31, to: 35 },
    { code: 'HOSP',  name: 'Hotels & Restaurants',           from: 36, to: 36 },
    { code: 'ICT',   name: 'Information & Media',            from: 37, to: 40 },
    { code: 'FIN',   name: 'Finance & Real Estate',          from: 41, to: 44 },
    { code: 'PROF',  name: 'Professional & Business Svcs',   from: 45, to: 53 },
    { code: 'PUB',   name: 'Public, Health & Education',     from: 54, to: 57 },
    { code: 'ARTS',  name: 'Arts & Other Services',          from: 58, to: 62 }
  ];

  var C = window.Charts;

  var S = {
    runs: [],            // done runs from /api/runs
    sectors: [],         // sector-metadata.json
    knobsCache: {},      // dataset_id → knobs array
    specCache: {},       // run_id → normalized run spec; populated lazily on fork
    A: null,             // {run, summary}
    B: null,             // {run, summary} | null
    ov: null,            // overlap {labels, ia0, ib0, n, partial}
    rows: [],            // row configs + handles
    spineHandle: null,
    hmHandle: null,
    cursor: 0,
    playing: false,
    pollTimer: null
  };

  /* ── tiny helpers ── */
  function $(id) { return document.getElementById(id); }
  function slice(arr, i0, n) {
    if (!arr) return null;
    var out = [];
    for (var i = 0; i < n; i++) out.push(arr[i0 + i] != null && isFinite(arr[i0 + i]) ? arr[i0 + i] : null);
    return out;
  }
  function loadMeta() { try { return JSON.parse(localStorage.getItem(META_KEY) || '{}'); } catch (e) { return {}; } }
  function saveMeta(m) { try { localStorage.setItem(META_KEY, JSON.stringify(m)); } catch (e) { /* quota — ignore */ } }

  function showError(msg, retryFn) {
    var b = $('err-banner');
    b.innerHTML = '⚠ ' + msg;
    if (retryFn) {
      var btn = document.createElement('button');
      btn.textContent = 'RETRY';
      btn.addEventListener('click', function () { b.classList.add('hidden'); retryFn(); });
      b.appendChild(btn);
    }
    b.classList.remove('hidden');
  }
  function clearError() { $('err-banner').classList.add('hidden'); }

  function apiGet(path) {
    return fetch(API + path).then(function (r) {
      if (!r.ok) throw new Error('GET ' + path + ' → HTTP ' + r.status);
      return r.json();
    });
  }

  /* ── run labels ── */
  function shortDataset(id) { return id.replace('AUSTRIA', '').replace('STEADY_STATE', 'SS').replace('ITALY', 'IT'); }
  function shortShock(type) {
    if (type === 'interest_rate') return 'rate';
    return String(type || '').replace(/_/g, ' ');
  }
  function runLabel(run) {
    var meta = loadMeta()[run.run_id];
    var d = new Date(run.created_at);
    var pad = function (x) { return String(x).padStart(2, '0'); };
    var when = pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    var hasApiCount = run.override_count != null && isFinite(Number(run.override_count));
    var hasApiShock = typeof run.shock_type === 'string';
    var ovr;
    if (hasApiCount || hasApiShock) {
      var count = hasApiCount ? Math.max(0, Math.round(Number(run.override_count))) : '?';
      var shockType = hasApiShock ? run.shock_type : 'none';
      ovr = 'Δ' + count + (shockType && shockType !== 'none' ? '+' + shortShock(shockType) : '');
    } else {
      ovr = meta ? ('Δ' + meta.count + (meta.shock && meta.shock.type !== 'none' ? '+' + shortShock(meta.shock.type) : '')) : 'Δ?';
    }
    return shortDataset(run.dataset_id) + ' ' + run.scenario + ' · ' + when + ' · ' + ovr;
  }

  /* ── boot ── */
  function init() {
    ForkBoard.setup();
    ForkBoard.onRun = launchUniverseB;
    wireControls();
    Promise.all([
      fetch('sector-metadata.json').then(function (r) { if (!r.ok) throw new Error('sector-metadata.json HTTP ' + r.status); return r.json(); }),
      apiGet('/runs')
    ]).then(function (res) {
      S.sectors = res[0];
      S.runs = (res[1] || []).filter(function (r) { return r.state === 'done'; });
      if (!S.runs.length) {
        showError('No completed runs on the backend yet — start one from the main app, then reload.', init);
        return;
      }
      pickInitialUniverses();
      populateSelectors();
      return loadBoth();
    }).catch(function (e) {
      showError('Backend unreachable (' + e.message + '). Is the Julia API on 8080 up?', init);
    });
  }

  function pickInitialUniverses() {
    // newest done run, preferring the nowcast dataset; B = newest OTHER run on the same dataset
    var a = S.runs.find(function (r) { return r.dataset_id === PREFERRED_DATASET; }) || S.runs[0];
    var b = S.runs.find(function (r) { return r.run_id !== a.run_id && r.dataset_id === a.dataset_id; }) ||
            S.runs.find(function (r) { return r.run_id !== a.run_id; }) || null;
    S.A = { run: a, summary: null };
    S.B = b ? { run: b, summary: null } : null;
  }

  function populateSelectors() {
    var selA = $('selA'), selB = $('selB');
    selA.innerHTML = ''; selB.innerHTML = '';
    var fork = document.createElement('option');
    fork.value = '__fork__';
    fork.textContent = '⑂ FORK OF A — open delta board';
    selB.appendChild(fork);
    S.runs.forEach(function (r) {
      var oa = document.createElement('option');
      oa.value = r.run_id; oa.textContent = runLabel(r);
      selA.appendChild(oa);
      var ob = document.createElement('option');
      ob.value = r.run_id; ob.textContent = runLabel(r);
      selB.appendChild(ob);
    });
    if (S.A) selA.value = S.A.run.run_id;
    if (S.B) selB.value = S.B.run.run_id;
  }

  function wireControls() {
    $('selA').addEventListener('change', function () {
      var run = S.runs.find(function (r) { return r.run_id === $('selA').value; });
      if (!run) return;
      S.A = { run: run, summary: null };
      if (ForkBoard.isOpen()) openForkBoard();   // re-seed the board from the new A
      loadBoth();
    });
    $('selB').addEventListener('change', function () {
      var v = $('selB').value;
      if (v === '__fork__') { openForkBoard(); return; }
      ForkBoard.close();
      var run = S.runs.find(function (r) { return r.run_id === v; });
      if (!run) return;
      S.B = { run: run, summary: null };
      loadBoth();
    });
    $('btn-play').addEventListener('click', togglePlay);
    $('scrub').addEventListener('input', function () {
      stopPlay();
      setCursor(parseFloat($('scrub').value));
    });
    $('hm-toggle').addEventListener('click', function () {
      $('heatmap-sec').classList.toggle('collapsed');
      if (!$('heatmap-sec').classList.contains('collapsed')) renderHeatmap();
    });
    var rsz;
    window.addEventListener('resize', function () {
      clearTimeout(rsz);
      rsz = setTimeout(function () { renderAll(); }, 160);
    });
  }

  function loadBoth() {
    clearError();
    var jobs = [apiGet('/runs/' + S.A.run.run_id + '/summary')];
    if (S.B) jobs.push(apiGet('/runs/' + S.B.run.run_id + '/summary'));
    return Promise.all(jobs).then(function (res) {
      S.A.summary = res[0];
      if (S.B) S.B.summary = res[1];
      renderAll();
    }).catch(function (e) {
      showError('Could not load run summaries (' + e.message + ')', loadBoth);
    });
  }

  /* ── derived series ─────────────────────────────────────────────── */

  /* inflation %/yr from deflator level: YoY when 4 lags exist, else annualized q/q (both derived) */
  function inflationFrom(defl) {
    var out = [];
    for (var t = 0; t < defl.length; t++) {
      var d = defl[t];
      if (d == null || !isFinite(d)) { out.push(null); continue; }
      if (t >= 4 && defl[t - 4] != null && defl[t - 4] !== 0) out.push((d / defl[t - 4] - 1) * 100);
      else if (t >= 1 && defl[t - 1] != null && defl[t - 1] !== 0) out.push((Math.pow(d / defl[t - 1], 4) - 1) * 100);
      else out.push(null);
    }
    return out;
  }

  function seriesPack(sum, ov, side) {
    // side offsets into the FULL summary arrays, then slice to the shared window
    var i0 = side === 'A' ? ov.ia0 : ov.ib0;
    var n = ov.n;
    function pick(key) {
      return {
        mean: slice(sum[key].mean, i0, n),
        std: sum[key].std ? slice(sum[key].std, i0, n) : null
      };
    }
    var gdp = pick('real_gdp');
    var wages = pick('wages');
    var rate = {   // % annual
      mean: slice(sum.euribor_annual.mean, i0, n).map(function (v) { return v == null ? null : v * 100; }),
      std: sum.euribor_annual.std ? slice(sum.euribor_annual.std, i0, n).map(function (v) { return v == null ? null : v * 100; }) : null
    };
    var infl = { mean: slice(inflationFrom(sum.gdp_deflator.mean), i0, n), std: null }; // derived → no honest std
    // trade balance X − M; std via quadrature (independence approx) — derived
    var xm = slice(sum.real_exports.mean, i0, n), mm = slice(sum.real_imports.mean, i0, n);
    var xs = sum.real_exports.std ? slice(sum.real_exports.std, i0, n) : null;
    var ms = sum.real_imports.std ? slice(sum.real_imports.std, i0, n) : null;
    var trade = {
      mean: xm.map(function (x, i) { return (x == null || mm[i] == null) ? null : x - mm[i]; }),
      std: xm.map(function (_, i) {
        var a = xs && xs[i] != null && isFinite(xs[i]) ? xs[i] : 0;
        var b = ms && ms[i] != null && isFinite(ms[i]) ? ms[i] : 0;
        return Math.sqrt(a * a + b * b);
      })
    };
    return { gdp: gdp, infl: infl, wages: wages, rate: rate, trade: trade };
  }

  function computeOverlap(sa, sb) {
    if (!sb) return { labels: sa.periods.slice(), ia0: 0, ib0: 0, n: sa.periods.length, partial: false };
    var idxB = {};
    sb.periods.forEach(function (p, i) { idxB[p] = i; });
    var ia0 = -1, ib0 = -1;
    for (var i = 0; i < sa.periods.length; i++) {
      if (idxB[sa.periods[i]] != null) { ia0 = i; ib0 = idxB[sa.periods[i]]; break; }
    }
    if (ia0 < 0) return null;
    var n = 0;
    while (ia0 + n < sa.periods.length && ib0 + n < sb.periods.length &&
           sa.periods[ia0 + n] === sb.periods[ib0 + n]) n++;
    return {
      labels: sa.periods.slice(ia0, ia0 + n), ia0: ia0, ib0: ib0, n: n,
      partial: n < sa.periods.length || n < sb.periods.length
    };
  }

  function diffOf(a, b, mode) {
    // per-quarter B−A in the requested unit; null-safe, divide-by-zero guarded
    return a.map(function (va, i) {
      var vb = b ? b[i] : null;
      if (va == null || vb == null || !isFinite(va) || !isFinite(vb)) return null;
      if (mode === 'pct') return Math.abs(va) < 1e-9 ? null : (vb - va) / Math.abs(va) * 100;
      if (mode === 'pp') return vb - va;
      if (mode === 'bp') return (vb - va) * 100;   // series already in %, ×100 → basis points
      return vb - va;                              // abs (model units)
    });
  }

  /* ── master render ──────────────────────────────────────────────── */
  var packA = null, packB = null, diffs = null;

  function renderAll() {
    if (!S.A || !S.A.summary) return;
    var sa = S.A.summary, sb = S.B && S.B.summary;
    S.ov = computeOverlap(sa, sb);
    if (!S.ov) {
      showError('Universes A and B share no quarters (different eras: ' + sa.periods[0] + ' vs ' + sb.periods[0] + ') — pick runs from the same dataset.');
      S.ov = computeOverlap(sa, null);
      sb = null;
    }
    var ov = S.ov;
    packA = seriesPack(sa, ov, 'A');
    packB = sb ? seriesPack(sb, ov, 'B') : null;
    diffs = {
      gdp: diffOf(packA.gdp.mean, packB && packB.gdp.mean, 'pct'),
      infl: diffOf(packA.infl.mean, packB && packB.infl.mean, 'pp'),
      wages: diffOf(packA.wages.mean, packB && packB.wages.mean, 'pct'),
      rate: diffOf(packA.rate.mean, packB && packB.rate.mean, 'bp'),
      trade: diffOf(packA.trade.mean, packB && packB.trade.mean, 'abs')
    };

    // overlap / legend note
    var note = 'SHARED WINDOW ' + ov.labels[0] + ' → ' + ov.labels[ov.n - 1] + ' · ' + ov.n + 'Q' +
      ' · A: ' + S.A.run.scenario + ' ×' + sa.n_sims + (sb ? ' · B: ' + S.B.run.scenario + ' ×' + sb.n_sims : ' · B: —');
    if (ov.partial) note += ' · horizons differ — comparing the overlap only';
    $('overlap-note').textContent = note;

    renderRows();
    renderSpine();
    renderImpactCards();
    renderHeatmap();

    $('scrub').max = String(Math.max(1, ov.n - 1));
    setCursor(Math.min(S.cursor, ov.n - 1));
  }

  function renderRows() {
    var host = $('rows');
    host.innerHTML = '';
    S.rows = [];
    var defs = [
      { id: 'gdp', title: 'REAL GDP', unit: 'M€ / quarter', fmt: C.fmt0, diffMode: 'pct' },
      { id: 'infl', title: 'INFLATION YoY', unit: '% / year', fmt: C.fmt2, diffMode: 'pp', derived: true, derivedTip: 'derived from the GDP deflator: year-on-year where 4 lags exist, annualized q/q for the first forecast quarters; no honest std → no band' },
      { id: 'wages', title: 'WAGE BILL (nominal)', unit: 'M€ / quarter', fmt: C.fmt0, diffMode: 'pct' },
      { id: 'rate', title: 'POLICY RATE', unit: '% annual', fmt: C.fmt2, diffMode: 'bp' },
      { id: 'trade', title: 'TRADE BALANCE (X − M)', unit: 'M€ / quarter', fmt: C.fmt0, diffMode: 'abs', derived: true, derivedTip: 'derived: real_exports − real_imports; band = ±1σ with stds combined in quadrature (independence approximation)' }
    ];
    defs.forEach(function (d, i) {
      var cont = document.createElement('div');
      host.appendChild(cont);
      var h = C.renderRow(cont, {
        title: d.title, unit: d.unit, derived: d.derived, derivedTip: d.derivedTip,
        labels: S.ov.labels,
        A: packA[d.id], B: packB ? packB[d.id] : null,
        diff: diffs[d.id], diffMode: d.diffMode, fmt: d.fmt,
        showXAxis: i === defs.length - 1
      });
      S.rows.push(h);
    });
  }

  /* normalized aggregate |B−A| across the five series → pulse strip */
  function renderSpine() {
    var keys = ['gdp', 'infl', 'wages', 'rate', 'trade'];
    var n = S.ov.n;
    var norm = keys.map(function (k) {
      var d = diffs[k], m = 0;
      d.forEach(function (v) { if (v != null && isFinite(v) && Math.abs(v) > m) m = Math.abs(v); });
      return m;
    });
    var agg = [];
    for (var t = 0; t < n; t++) {
      var s = 0, c2 = 0;
      keys.forEach(function (k, ki) {
        var v = diffs[k][t];
        if (v == null || !isFinite(v) || norm[ki] === 0) return;
        s += Math.abs(v) / norm[ki]; c2++;
      });
      agg.push(c2 ? s / c2 : null);
    }
    var maxI = -1, maxV = -Infinity;
    agg.forEach(function (v, i) { if (v != null && v > maxV) { maxV = v; maxI = i; } });
    // renormalize so the strongest split hits 1.0 — the strip reads as contrast, not absolute level
    if (maxV > 0) agg = agg.map(function (v) { return v == null ? null : v / maxV; });
    S.spineHandle = C.renderSpine($('spine'), { labels: S.ov.labels, values: agg, annotIdx: maxI >= 0 ? maxI : null });
  }

  /* ── impact cards + winners/losers ── */
  function card(host, metric, label, tone) {
    var d = document.createElement('div');
    d.className = 'card' + (tone ? ' ' + tone : '');
    d.innerHTML = '<div class="card-metric">' + metric + '</div><div class="card-label">' + label + '</div>';
    host.appendChild(d);
  }

  function renderImpactCards() {
    var host = $('cards');
    host.innerHTML = '';
    if (!packB) {
      card(host, '—', 'Load or run a Universe B to see treated-vs-control impacts.');
      C.renderWinnersLosers($('wl'), null);
      return;
    }
    var n = S.ov.n;

    // GDP after 8 quarters (or at the window end if shorter)
    var q8 = Math.min(8, n - 1);
    var d8 = diffs.gdp[q8];
    card(host, 'B ' + C.fmtSigned(d8, 2, '%') + ' vs A',
      'REAL GDP after ' + q8 + ' quarters (' + S.ov.labels[q8] + ')',
      d8 != null && d8 >= 0 ? 'warm' : 'cool');

    // peak inflation in each universe
    function peak(arr) {
      var m = -Infinity, mi = -1;
      arr.forEach(function (v, i) { if (v != null && isFinite(v) && v > m) { m = v; mi = i; } });
      return mi < 0 ? null : { v: m, i: mi };
    }
    var pb = peak(packB.infl.mean), pa = peak(packA.infl.mean);
    if (pa && pb) {
      card(host, 'B ' + pb.v.toFixed(2) + '% <b>(A ' + pa.v.toFixed(2) + '%)</b>',
        'Peak inflation — B at ' + S.ov.labels[pb.i] + ', A at ' + S.ov.labels[pa.i] +
        ' <em class="derived-badge" title="inflation derived from the GDP deflator">derived</em>',
        pb.v >= pa.v ? 'warm' : 'cool');
    }

    // rate path peak difference in bp
    var rb = peak(packB.rate.mean), ra = peak(packA.rate.mean);
    if (ra && rb) {
      var bp = (rb.v - ra.v) * 100;
      card(host, Math.abs(bp) < 0.5 ? 'peaks level with A' : ('peaks ' + Math.abs(bp).toFixed(0) + 'bp ' + (bp >= 0 ? 'higher' : 'lower')),
        'Policy-rate path — Taylor rule response (B peak ' + rb.v.toFixed(2) + '%, A peak ' + ra.v.toFixed(2) + '%)',
        bp >= 0 ? 'warm' : 'cool');
    }

    // cumulative extra real output over the shared window
    var cum = 0, any = false;
    for (var t = 0; t < n; t++) {
      var a = packA.gdp.mean[t], b = packB.gdp.mean[t];
      if (a == null || b == null) continue;
      cum += b - a; any = true;
    }
    if (any) {
      card(host, C.fmtSigned(cum, 0, ' M€'),
        'Cumulative extra real output over ' + n + ' quarters (model units ≈ millions €)',
        cum >= 0 ? 'warm' : 'cool');
    }

    renderWinnersLosersCards();
  }

  function sectorDiffAt(q) {
    // per-sector GVA % difference at overlap quarter q; guard tiny denominators
    var sa = S.A.summary, sb = S.B.summary;
    var rowA = sa.real_sector_gva.mean[S.ov.ia0 + q];
    var rowB = sb.real_sector_gva.mean[S.ov.ib0 + q];
    return S.sectors.map(function (sec, s) {
      var a = rowA ? rowA[s] : null, b = rowB ? rowB[s] : null;
      if (a == null || b == null || !isFinite(a) || !isFinite(b) || Math.abs(a) < 0.5) return null;
      return { code: sec.code, label: sec.label, pct: (b - a) / Math.abs(a) * 100 };
    });
  }

  function renderWinnersLosersCards() {
    var list = sectorDiffAt(S.ov.n - 1).filter(Boolean);
    list.sort(function (a, b) { return b.pct - a.pct; });
    if (list.length < 3) { C.renderWinnersLosers($('wl'), null); return; }
    var top = list.slice(0, 5);
    var bot = list.slice(-5);
    var items = top.concat(['sep']).concat(bot);
    C.renderWinnersLosers($('wl'), items);
  }

  /* ── sector heatmap ── */
  function renderHeatmap() {
    var host = $('heatmap');
    if ($('heatmap-sec').classList.contains('collapsed')) return;
    if (!packB) { host.innerHTML = '<div class="wl-empty">needs both universes loaded</div>'; return; }
    var n = S.ov.n;
    var matrix = S.sectors.map(function () { return new Array(n).fill(null); });
    for (var q = 0; q < n; q++) {
      var col = sectorDiffAt(q);
      for (var s = 0; s < S.sectors.length; s++) matrix[s][q] = col[s] ? col[s].pct : null;
    }
    S.hmHandle = C.renderHeatmap(host, {
      labels: S.ov.labels, sectors: S.sectors, matrix: matrix,
      groups: GROUPS, tipEl: $('hm-tip')
    });
    S.hmHandle.setCursor(S.cursor);
  }

  /* ── time cursor / play ─────────────────────────────────────────── */
  function setCursor(c) {
    if (!S.ov) return;
    S.cursor = Math.max(0, Math.min(S.ov.n - 1, c));
    $('scrub').value = String(S.cursor);
    $('period-readout').textContent = S.ov.labels[Math.round(S.cursor)] || '—';
    S.rows.forEach(function (h) { h.setCursor(S.cursor); });
    if (S.spineHandle) S.spineHandle.setCursor(S.cursor);
    if (S.hmHandle && !$('heatmap-sec').classList.contains('collapsed')) S.hmHandle.setCursor(S.cursor);
    updateKPIs();
  }

  function kpiSet(id, va, vb, vd) {
    var el = $(id);
    el.querySelector('.va').textContent = va;
    el.querySelector('.vb').textContent = vb;
    el.querySelector('.vd').textContent = vd;
  }
  function updateKPIs() {
    var c = S.cursor;
    var gA = C.interp(packA.gdp.mean, c), gB = packB ? C.interp(packB.gdp.mean, c) : null;
    kpiSet('kpi-gdp', C.fmt0(gA), C.fmt0(gB), C.fmtSigned(C.interp(diffs.gdp, c), 2, '%'));
    var iA = C.interp(packA.infl.mean, c), iB = packB ? C.interp(packB.infl.mean, c) : null;
    kpiSet('kpi-infl', iA == null ? '—' : iA.toFixed(2) + '%', iB == null ? '—' : iB.toFixed(2) + '%',
      C.fmtSigned(C.interp(diffs.infl, c), 2, 'pp'));
    var rA = C.interp(packA.rate.mean, c), rB = packB ? C.interp(packB.rate.mean, c) : null;
    kpiSet('kpi-rate', rA == null ? '—' : rA.toFixed(2) + '%', rB == null ? '—' : rB.toFixed(2) + '%',
      C.fmtSigned(C.interp(diffs.rate, c), 0, 'bp'));
  }

  var lastTs = null;
  function frame(ts) {
    if (!S.playing) return;
    if (lastTs != null) {
      var speed = Math.max(1.4, (S.ov.n - 1) / 11);   // quarters per second → ~11s sweep
      var next = S.cursor + (ts - lastTs) / 1000 * speed;
      if (next >= S.ov.n - 1) { setCursor(S.ov.n - 1); stopPlay(); return; }
      setCursor(next);
    }
    lastTs = ts;
    requestAnimationFrame(frame);
  }
  function togglePlay() {
    if (S.playing) { stopPlay(); return; }
    if (S.cursor >= S.ov.n - 1 - 1e-6) S.cursor = 0;
    S.playing = true; lastTs = null;
    $('btn-play').textContent = '❚❚';
    requestAnimationFrame(frame);
  }
  function stopPlay() {
    S.playing = false;
    $('btn-play').textContent = '▶';
  }

  /* ── fork board wiring ──────────────────────────────────────────── */
  function knobsFor(datasetId) {
    if (S.knobsCache[datasetId]) return Promise.resolve(S.knobsCache[datasetId]);
    return apiGet('/knobs?dataset_id=' + encodeURIComponent(datasetId)).then(function (ks) {
      S.knobsCache[datasetId] = ks;
      return ks;
    });
  }

  function specFor(runId) {
    if (S.specCache[runId]) return Promise.resolve(S.specCache[runId]);
    return apiGet('/runs/' + encodeURIComponent(runId) + '/spec').then(function (spec) {
      S.specCache[runId] = spec;
      return spec;
    });
  }

  function flattenOverrides(overrides) {
    var seed = {};
    ['parameters', 'initial_conditions'].forEach(function (group) {
      var values = overrides && overrides[group];
      if (!values || typeof values !== 'object') return;
      Object.keys(values).forEach(function (key) {
        var value = Number(values[key]);
        if (isFinite(value)) seed[key] = value;
      });
    });
    return seed;
  }

  function overrideCount(overrides) {
    return ['parameters', 'initial_conditions'].reduce(function (total, group) {
      var values = overrides && overrides[group];
      return total + (values && typeof values === 'object' ? Object.keys(values).length : 0);
    }, 0);
  }

  function openForkBoard() {
    var a = S.A;
    var specJob = specFor(a.run.run_id).catch(function () { return null; });
    Promise.all([knobsFor(a.run.dataset_id), specJob]).then(function (res) {
      var knobs = res[0];
      var spec = res[1];
      var meta = loadMeta()[a.run.run_id];
      var seed = {};
      var provenance;
      if (spec) {
        seed = flattenOverrides(spec.overrides);
        var count = overrideCount(spec.overrides);
        provenance = 'A’s run spec loaded · ' + count + ' override' + (count === 1 ? '' : 's') + ' seeded';
        if (spec.shock && spec.shock.type && spec.shock.type !== 'none') {
          provenance += ' · A shock: ' + shortShock(spec.shock.type);
        }
      } else if (meta && meta.overrides) {
        seed = flattenOverrides(meta.overrides);
        provenance = 'run spec unavailable · A’s locally recorded overrides seeded';
      } else {
        provenance = 'run spec unavailable · dataset defaults assumed';
      }
      var specT = spec && spec.sim ? Number(spec.sim.T) : NaN;
      var T = Math.min(a.summary ? a.summary.T : (isFinite(specT) ? specT : 12), 23);   // match A's horizon, capped at 23
      var basis = 'basis: A = ' + runLabel(a.run) + ' (' + provenance + ')';
      ForkBoard.open(knobs, seed, T, basis);
    }).catch(function (e) {
      showError('Could not load knobs (' + e.message + ')');
    });
  }

  /* POST /api/runs and poll to completion.
   * Envelope per contract: same dataset+scenario as A, T = min(A.T, 23),
   * n_sims = 4, overrides in UI units with changed keys only. */
  function launchUniverseB(payload) {
    var a = S.A;
    var T = Math.min(a.summary ? a.summary.T : 12, 23);
    var body = {
      dataset_id: a.run.dataset_id,
      scenario: a.run.scenario,
      sim: { T: T, n_sims: 4, base_seed: 1000 + Math.floor(Math.random() * 90000) },
      overrides: payload.overrides,
      shock: payload.shock
    };
    var capsule = $('capsule'), fill = $('capsule-fill'), msg = $('capsule-msg');
    capsule.classList.remove('hidden', 'err');
    fill.style.width = '2%';
    msg.textContent = 'submitting…';
    $('btn-run').disabled = true;

    fetch(API + '/runs', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error('HTTP ' + r.status + ' ' + t.slice(0, 140)); });
      return r.json();
    }).then(function (res) {
      var runId = res.run_id;
      // remember this run's overrides so its dropdown label shows Δn and future forks seed correctly
      var meta = loadMeta();
      meta[runId] = { count: payload.changedCount, overrides: payload.overrides, shock: payload.shock };
      saveMeta(meta);
      pollRun(runId, capsule, fill, msg);
    }).catch(function (e) {
      capsule.classList.add('err');
      msg.textContent = e.message;
      $('btn-run').disabled = false;
    });
  }

  function pollRun(runId, capsule, fill, msg) {
    if (S.pollTimer) clearInterval(S.pollTimer);
    S.pollTimer = setInterval(function () {
      apiGet('/runs/' + runId + '/status').then(function (st) {
        fill.style.width = Math.max(2, Math.round((st.progress || 0) * 100)) + '%';
        msg.textContent = st.state + ' — ' + (st.message || '');
        if (st.state === 'done') {
          clearInterval(S.pollTimer); S.pollTimer = null;
          msg.textContent = 'done — loading Universe B';
          adoptNewRun(runId, capsule);
        } else if (st.state === 'error') {
          clearInterval(S.pollTimer); S.pollTimer = null;
          capsule.classList.add('err');
          msg.textContent = 'simulation error — ' + (st.message || 'unknown');
          $('btn-run').disabled = false;
        }
      }).catch(function (e) {
        clearInterval(S.pollTimer); S.pollTimer = null;
        capsule.classList.add('err');
        msg.textContent = 'lost contact: ' + e.message;
        $('btn-run').disabled = false;
      });
    }, 1500);
  }

  function adoptNewRun(runId, capsule) {
    apiGet('/runs').then(function (runs) {
      S.runs = (runs || []).filter(function (r) { return r.state === 'done'; });
      var run = S.runs.find(function (r) { return r.run_id === runId; });
      populateSelectors();
      $('selA').value = S.A.run.run_id;
      if (run) {
        S.B = { run: run, summary: null };
        $('selB').value = runId;
        ForkBoard.close();
        loadBoth();
      }
      $('btn-run').disabled = false;
      setTimeout(function () { capsule.classList.add('hidden'); }, 2500);
    }).catch(function (e) {
      showError('Run finished but the run list refresh failed (' + e.message + ')');
      $('btn-run').disabled = false;
    });
  }

  init();
})();
