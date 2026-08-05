/* ── charts.js — hand-rolled SVG rendering for Twin Lab ──────────────────
 * No chart library. Every visual (line rows, diff ribbons, divergence
 * spine, sector heatmap, winner/loser bars) is built here from plain SVG.
 * All row charts share the same left/right margins so one time cursor
 * lines up across every panel.
 */
(function () {
  'use strict';

  var NS = 'http://www.w3.org/2000/svg';

  var COL = {
    A: '#3fe0ff', B: '#ff5fd2', amber: '#ffb454', neg: '#3f8dff',
    grid: '#152028', dim: '#5d7181', faint: '#3a4a58', cursor: '#eaf6ff'
  };
  // shared horizontal margins → cursor alignment across rows + spine
  var MX = { l: 56, r: 10 };

  function el(tag, attrs, parent) {
    var n = document.createElementNS(NS, tag);
    if (attrs) for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }
  function div(cls, parent, html) {
    var d = document.createElement('div');
    if (cls) d.className = cls;
    if (html != null) d.innerHTML = html;
    if (parent) parent.appendChild(d);
    return d;
  }

  /* ── number formatting (monospace-friendly) ── */
  var nf0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
  function fmt0(v) { return (v == null || !isFinite(v)) ? '—' : nf0.format(v); }
  function fmt2(v) { return (v == null || !isFinite(v)) ? '—' : v.toFixed(2); }
  function fmtSigned(v, dec, suffix) {
    if (v == null || !isFinite(v)) return '—';
    var s = v >= 0 ? '+' : '−';
    return s + Math.abs(v).toFixed(dec) + (suffix || '');
  }

  /* linear interpolation into a (possibly null-holed) series at float index */
  function interp(arr, c) {
    if (!arr || !arr.length) return null;
    var i = Math.max(0, Math.min(arr.length - 1, Math.floor(c)));
    var j = Math.min(arr.length - 1, i + 1);
    var f = c - i;
    var a = arr[i], b = arr[j];
    if (a == null || !isFinite(a)) return (b != null && isFinite(b)) ? b : null;
    if (b == null || !isFinite(b)) return a;
    return a + (b - a) * f;
  }

  /* nice-ish tick values (3 ticks: lo / mid / hi) */
  function ticks3(lo, hi) {
    if (!(isFinite(lo) && isFinite(hi)) || lo === hi) { hi = (lo || 0) + 1; }
    return [lo, (lo + hi) / 2, hi];
  }

  function extent(arrs) {
    var lo = Infinity, hi = -Infinity;
    arrs.forEach(function (a) {
      if (!a) return;
      a.forEach(function (v) {
        if (v == null || !isFinite(v)) return;
        if (v < lo) lo = v; if (v > hi) hi = v;
      });
    });
    if (lo === Infinity) { lo = 0; hi = 1; }
    if (lo === hi) { lo -= 1; hi += 1; }
    var pad = (hi - lo) * 0.08;
    return [lo - pad, hi + pad];
  }

  /* path across points, skipping nulls (gap = new subpath) */
  function linePath(xs, ys) {
    var d = '', pen = false;
    for (var i = 0; i < xs.length; i++) {
      var y = ys[i];
      if (y == null || !isFinite(y)) { pen = false; continue; }
      d += (pen ? 'L' : 'M') + xs[i].toFixed(1) + ',' + y.toFixed(1);
      pen = true;
    }
    return d;
  }
  /* closed band between upper and lower series (contiguous segments) */
  function bandPath(xs, up, lo) {
    var d = '', seg = [];
    function flush() {
      if (seg.length < 2) { seg = []; return; }
      d += 'M' + seg.map(function (p) { return p[0].toFixed(1) + ',' + p[1].toFixed(1); }).join('L');
      for (var i = seg.length - 1; i >= 0; i--) d += 'L' + seg[i][0].toFixed(1) + ',' + seg[i][2].toFixed(1);
      d += 'Z';
      seg = [];
    }
    for (var i = 0; i < xs.length; i++) {
      if (up[i] == null || lo[i] == null || !isFinite(up[i]) || !isFinite(lo[i])) { flush(); continue; }
      seg.push([xs[i], up[i], lo[i]]);
    }
    flush();
    return d;
  }

  /* ──────────────────────────────────────────────────────────────────
   * renderRow(container, cfg)
   * cfg: { title, unit, derived, labels[], A:{mean,std}, B:{mean,std},
   *        diff[], diffMode('pct'|'pp'|'bp'|'abs'), fmt, showXAxis }
   * returns { setCursor(cFloat) }
   * ────────────────────────────────────────────────────────────────── */
  function renderRow(container, cfg) {
    container.innerHTML = '';
    container.className = 'crow';

    var head = div('row-head', container);
    div('row-title', head, cfg.title);
    if (cfg.derived) {
      var b = div(null, head); b.outerHTML =
        '<em class="derived-tag" title="' + (cfg.derivedTip || 'derived from aggregate summary series') + '">derived</em>';
    }
    div('row-unit', head, cfg.unit || '');
    var readout = div('row-readout', head, '—');

    var W = Math.max(420, container.clientWidth || 800);
    var H = cfg.chartH || 92;
    var RH = 26 + (cfg.showXAxis ? 14 : 0);
    var MT = 6, MB = 4;

    var n = cfg.labels.length;
    var xs = [];
    var innerW = W - MX.l - MX.r;
    for (var i = 0; i < n; i++) xs.push(MX.l + (n === 1 ? 0 : i / (n - 1) * innerW));

    /* ---- main chart svg ---- */
    var svg = el('svg', { width: W, height: H }, container);

    var mA = cfg.A ? cfg.A.mean : null, sA = cfg.A ? cfg.A.std : null;
    var mB = cfg.B ? cfg.B.mean : null, sB = cfg.B ? cfg.B.std : null;

    function bands(mean, std, sign) {
      if (!mean || !std) return null;
      return mean.map(function (m, i) {
        if (m == null || !isFinite(m)) return null;
        var s = (std[i] == null || !isFinite(std[i])) ? 0 : std[i];   // null-std guard
        return m + sign * s;
      });
    }

    var ext = extent([mA, mB, bands(mA, sA, 1), bands(mA, sA, -1), bands(mB, sB, 1), bands(mB, sB, -1)]);
    var y0 = ext[0], y1 = ext[1];
    function Y(v) { return MT + (1 - (v - y0) / (y1 - y0)) * (H - MT - MB); }

    // horizontal grid + y tick labels
    ticks3(y0, y1).forEach(function (tv) {
      var y = Y(tv);
      el('line', { x1: MX.l, x2: W - MX.r, y1: y, y2: y, stroke: COL.grid, 'stroke-width': 1 }, svg);
      el('text', {
        x: MX.l - 6, y: y + 3, 'text-anchor': 'end', fill: COL.faint,
        'font-size': 8.5, 'font-family': 'ui-monospace,Menlo,monospace'
      }, svg).textContent = (cfg.fmt || fmt0)(tv);
    });
    // vertical year gridlines (Q1s)
    cfg.labels.forEach(function (lb, i) {
      if (/Q1$/.test(lb) && i > 0) {
        el('line', { x1: xs[i], x2: xs[i], y1: MT, y2: H - MB, stroke: COL.grid, 'stroke-width': 1, 'stroke-dasharray': '2,3' }, svg);
      }
    });

    // ±1σ bands (low opacity, null-guarded)
    if (mA && sA) el('path', { d: bandPath(xs, bands(mA, sA, 1), bands(mA, sA, -1)), fill: COL.A, opacity: 0.08 }, svg);
    if (mB && sB) el('path', { d: bandPath(xs, bands(mB, sB, 1), bands(mB, sB, -1)), fill: COL.B, opacity: 0.08 }, svg);

    // mean lines: A solid, B dashed
    if (mA) el('path', { d: linePath(xs, mA.map(function (v) { return v == null ? null : Y(v); })), fill: 'none', stroke: COL.A, 'stroke-width': 1.6 }, svg);
    if (mB) el('path', { d: linePath(xs, mB.map(function (v) { return v == null ? null : Y(v); })), fill: 'none', stroke: COL.B, 'stroke-width': 1.6, 'stroke-dasharray': '5,3' }, svg);

    var cursor1 = el('line', { x1: xs[0], x2: xs[0], y1: MT, y2: H - MB, stroke: COL.cursor, 'stroke-width': 1, opacity: 0.55 }, svg);
    var dotA = el('circle', { r: 2.6, fill: COL.A, opacity: 0 }, svg);
    var dotB = el('circle', { r: 2.6, fill: COL.B, opacity: 0 }, svg);

    /* ---- diff ribbon svg ---- */
    var rsvg = el('svg', { width: W, height: RH }, container);
    var rTop = 2, rBot = RH - (cfg.showXAxis ? 16 : 2);
    var mid = (rTop + rBot) / 2;
    var diff = cfg.diff || [];
    var maxAbs = 0;
    diff.forEach(function (v) { if (v != null && isFinite(v) && Math.abs(v) > maxAbs) maxAbs = Math.abs(v); });
    if (maxAbs === 0) maxAbs = 1;
    function RY(v) { return mid - (v / maxAbs) * (mid - rTop); }

    el('line', { x1: MX.l, x2: W - MX.r, y1: mid, y2: mid, stroke: COL.grid, 'stroke-width': 1 }, rsvg);
    // ribbon axis label
    el('text', {
      x: MX.l - 6, y: mid + 3, 'text-anchor': 'end', fill: COL.faint,
      'font-size': 8, 'font-family': 'ui-monospace,Menlo,monospace'
    }, rsvg).textContent = 'B−A ' + ({ pct: '%', pp: 'pp', bp: 'bp', abs: 'M€' }[cfg.diffMode] || '');

    // split filled area into positive (amber) and negative (blue) lobes
    var posY = diff.map(function (v) { return (v == null || !isFinite(v)) ? null : RY(Math.max(0, v)); });
    var negY = diff.map(function (v) { return (v == null || !isFinite(v)) ? null : RY(Math.min(0, v)); });
    var base = diff.map(function (v) { return (v == null || !isFinite(v)) ? null : mid; });
    el('path', { d: bandPath(xs, posY, base), fill: COL.amber, opacity: 0.5 }, rsvg);
    el('path', { d: bandPath(xs, base, negY), fill: COL.neg, opacity: 0.5 }, rsvg);
    el('path', { d: linePath(xs, diff.map(function (v) { return (v == null || !isFinite(v)) ? null : RY(v); })), fill: 'none', stroke: '#dbe7f0', 'stroke-width': 0.7, opacity: 0.5 }, rsvg);

    var cursor2 = el('line', { x1: xs[0], x2: xs[0], y1: rTop, y2: rBot, stroke: COL.cursor, 'stroke-width': 1, opacity: 0.4 }, rsvg);

    if (cfg.showXAxis) {
      var stepLbl = Math.max(1, Math.ceil(n / 12));
      cfg.labels.forEach(function (lb, i) {
        if (i % stepLbl !== 0 && i !== n - 1) return;
        el('text', {
          x: xs[i], y: RH - 4, 'text-anchor': 'middle', fill: COL.dim,
          'font-size': 8.5, 'font-family': 'ui-monospace,Menlo,monospace'
        }, rsvg).textContent = lb;
      });
    }

    var fmt = cfg.fmt || fmt0;
    var diffDec = { pct: 2, pp: 2, bp: 0, abs: 0 }[cfg.diffMode];
    var diffSuf = { pct: '%', pp: 'pp', bp: 'bp', abs: '' }[cfg.diffMode];

    function setCursor(c) {
      c = Math.max(0, Math.min(n - 1, c));
      var x = interp(xs, c);
      cursor1.setAttribute('x1', x); cursor1.setAttribute('x2', x);
      cursor2.setAttribute('x1', x); cursor2.setAttribute('x2', x);
      var va = mA ? interp(mA, c) : null;
      var vb = mB ? interp(mB, c) : null;
      var vd = interp(diff, c);
      if (va != null) { dotA.setAttribute('cx', x); dotA.setAttribute('cy', Y(va)); dotA.setAttribute('opacity', 0.95); }
      else dotA.setAttribute('opacity', 0);
      if (vb != null) { dotB.setAttribute('cx', x); dotB.setAttribute('cy', Y(vb)); dotB.setAttribute('opacity', 0.95); }
      else dotB.setAttribute('opacity', 0);
      readout.innerHTML =
        'A <span class="ra">' + fmt(va) + '</span>  B <span class="rb">' + fmt(vb) + '</span>  Δ <span class="rd">' +
        fmtSigned(vd, diffDec, diffSuf) + '</span>';
    }
    setCursor(0);
    return { setCursor: setCursor };
  }

  /* ──────────────────────────────────────────────────────────────────
   * renderSpine(container, {labels, values(0..1|null), annotIdx})
   * pulse strip sharing the row x-scale; glows where universes split.
   * ────────────────────────────────────────────────────────────────── */
  function renderSpine(container, cfg) {
    container.innerHTML = '';
    var W = Math.max(420, container.clientWidth || 800);
    var H = 46;
    var n = cfg.labels.length;
    var innerW = W - MX.l - MX.r;
    var xs = [];
    for (var i = 0; i < n; i++) xs.push(MX.l + (n === 1 ? 0 : i / (n - 1) * innerW));
    var svg = el('svg', { width: W, height: H }, container);

    var lab = el('text', {
      x: MX.l - 6, y: 22, 'text-anchor': 'end', fill: COL.dim,
      'font-size': 8, 'font-family': 'ui-monospace,Menlo,monospace', 'letter-spacing': '.06em'
    }, svg);
    el('tspan', { x: MX.l - 6, dy: 0 }, lab).textContent = 'SPLIT';
    el('tspan', { x: MX.l - 6, dy: 9 }, lab).textContent = '|B−A|';

    var defs = el('defs', null, svg);
    var filt = el('filter', { id: 'spine-glow', x: '-60%', y: '-60%', width: '220%', height: '220%' }, defs);
    el('feGaussianBlur', { stdDeviation: 2.4 }, filt);

    var step = n > 1 ? (xs[1] - xs[0]) : innerW;
    var bw = Math.max(2, step * 0.72);
    var track = el('g', null, svg);
    el('line', { x1: MX.l, x2: W - MX.r, y1: 34, y2: 34, stroke: COL.grid, 'stroke-width': 1 }, track);

    (cfg.values || []).forEach(function (v, i) {
      if (v == null || !isFinite(v)) return;
      var h = 3 + v * 20;
      // hot color ramp: cyan-dim → amber → near-white
      var col = v < 0.35 ? COL.neg : (v < 0.75 ? COL.amber : '#ffe9c9');
      var r = el('rect', {
        x: xs[i] - bw / 2, y: 34 - h, width: bw, height: h, rx: 1,
        fill: col, opacity: 0.28 + v * 0.7
      }, track);
      if (v > 0.6) r.setAttribute('filter', 'url(#spine-glow)');
      // crisp core over the glow
      el('rect', { x: xs[i] - bw / 2, y: 34 - h, width: bw, height: h, rx: 1, fill: col, opacity: 0.35 + v * 0.5 }, track);
    });

    // annotation at max divergence quarter
    if (cfg.annotIdx != null && cfg.annotIdx >= 0 && n > 1) {
      var ax = xs[cfg.annotIdx];
      el('line', { x1: ax, x2: ax, y1: 6, y2: 36, stroke: COL.amber, 'stroke-width': 1, 'stroke-dasharray': '2,2', opacity: 0.8 }, svg);
      var anchor = cfg.annotIdx > n * 0.7 ? 'end' : 'start';
      var tx = el('text', {
        x: ax + (anchor === 'end' ? -5 : 5), y: 12, 'text-anchor': anchor, fill: COL.amber,
        'font-size': 8.5, 'font-family': 'ui-monospace,Menlo,monospace', 'letter-spacing': '.08em'
      }, svg);
      tx.textContent = '▲ MAX SPLIT ' + cfg.labels[cfg.annotIdx];
    }

    var cursor = el('line', { x1: xs[0], x2: xs[0], y1: 6, y2: 40, stroke: COL.cursor, 'stroke-width': 1, opacity: 0.45 }, svg);
    return {
      setCursor: function (c) {
        var x = interp(xs, Math.max(0, Math.min(n - 1, c)));
        cursor.setAttribute('x1', x); cursor.setAttribute('x2', x);
      }
    };
  }

  /* diverging heat color: t in [-1,1] → blue…panel…red */
  function heatColor(t) {
    t = Math.max(-1, Math.min(1, t));
    var a = Math.abs(t);
    // ease so small differences stay visible
    a = Math.pow(a, 0.65);
    var r0 = 13, g0 = 18, b0 = 24;                 // near-panel midpoint
    var r1, g1, b1;
    if (t >= 0) { r1 = 255; g1 = 75;  b1 = 75; }    // red = B above A
    else        { r1 = 63;  g1 = 141; b1 = 255; }   // blue = B below A
    var r = Math.round(r0 + (r1 - r0) * a);
    var g = Math.round(g0 + (g1 - g0) * a);
    var b = Math.round(b0 + (b1 - b0) * a);
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  /* ──────────────────────────────────────────────────────────────────
   * renderHeatmap(container, {labels, sectors, matrix[62][n] (pct|null),
   *                           groups:[{code,name,from,to}], tipEl})
   * ────────────────────────────────────────────────────────────────── */
  function renderHeatmap(container, cfg) {
    container.innerHTML = '';
    var n = cfg.labels.length;
    var S = cfg.sectors.length;
    var ML = 108, MR = 14, MT = 18, MBOT = 6;
    var W = Math.max(760, (container.clientWidth || 1000) - 4);
    var rh = 9.5;
    var H = MT + S * rh + MBOT;
    var innerW = W - ML - MR;
    var cw = innerW / n;

    // robust symmetric color scale: 95th percentile of |v|, floor 0.5%
    var absVals = [];
    cfg.matrix.forEach(function (row) {
      row.forEach(function (v) { if (v != null && isFinite(v)) absVals.push(Math.abs(v)); });
    });
    absVals.sort(function (a, b) { return a - b; });
    var scale = absVals.length ? Math.max(0.5, absVals[Math.floor(absVals.length * 0.95)]) : 1;

    var svg = el('svg', { width: W, height: H }, container);

    // column labels (sparse)
    var stepLbl = Math.max(1, Math.ceil(n / 14));
    for (var j = 0; j < n; j++) {
      if (j % stepLbl !== 0 && j !== n - 1) continue;
      el('text', {
        x: ML + (j + 0.5) * cw, y: 12, 'text-anchor': 'middle', fill: COL.dim,
        'font-size': 8, 'font-family': 'ui-monospace,Menlo,monospace'
      }, svg).textContent = cfg.labels[j];
    }

    // cells
    var cells = el('g', { 'shape-rendering': 'crispEdges' }, svg);
    for (var s = 0; s < S; s++) {
      for (var q = 0; q < n; q++) {
        var v = cfg.matrix[s][q];
        el('rect', {
          x: ML + q * cw, y: MT + s * rh, width: Math.max(1, cw - 0.6), height: rh - 0.8,
          fill: (v == null || !isFinite(v)) ? '#0a0e13' : heatColor(v / scale)
        }, cells);
      }
    }

    // row labels: sector codes
    cfg.sectors.forEach(function (sec, s) {
      el('text', {
        x: ML - 5, y: MT + s * rh + rh - 2.5, 'text-anchor': 'end', fill: COL.dim,
        'font-size': 7.5, 'font-family': 'ui-monospace,Menlo,monospace'
      }, svg).textContent = sec.code;
    });

    // group separators + gutter labels
    (cfg.groups || []).forEach(function (g) {
      var yTop = MT + (g.from - 1) * rh;
      var yBot = MT + g.to * rh;
      if (g.from > 1) el('line', { x1: 4, x2: W - MR, y1: yTop, y2: yTop, stroke: COL.grid, 'stroke-width': 1 }, svg);
      el('text', {
        x: 4, y: (yTop + yBot) / 2 + 2.5, fill: COL.faint,
        'font-size': 7.5, 'font-family': 'ui-monospace,Menlo,monospace', 'letter-spacing': '.05em'
      }, svg).textContent = g.code;
    });

    // legend
    var lg = el('g', null, svg);
    var lgx = W - MR - 150, lgy = 8;
    [-1, -0.5, 0, 0.5, 1].forEach(function (t, i) {
      el('rect', { x: lgx + i * 22, y: lgy - 6, width: 22, height: 8, fill: heatColor(t) }, lg);
    });
    el('text', { x: lgx - 5, y: lgy + 1, 'text-anchor': 'end', fill: COL.faint, 'font-size': 7.5, 'font-family': 'ui-monospace,Menlo,monospace' }, lg)
      .textContent = '−' + scale.toFixed(1) + '%';
    el('text', { x: lgx + 5 * 22 + 5, y: lgy + 1, fill: COL.faint, 'font-size': 7.5, 'font-family': 'ui-monospace,Menlo,monospace' }, lg)
      .textContent = '+' + scale.toFixed(1) + '%';

    // cursor column highlight
    var colHl = el('rect', {
      x: ML, y: MT, width: Math.max(1, cw), height: S * rh,
      fill: 'none', stroke: COL.cursor, 'stroke-width': 1, opacity: 0.55, 'pointer-events': 'none'
    }, svg);

    // hover tooltip (single delegated handler — 1,488 cells, one listener)
    var tip = cfg.tipEl;
    if (tip) {
      svg.addEventListener('mousemove', function (ev) {
        var rect = svg.getBoundingClientRect();
        var mx = ev.clientX - rect.left, my = ev.clientY - rect.top;
        var q = Math.floor((mx - ML) / cw), s2 = Math.floor((my - MT) / rh);
        if (q < 0 || q >= n || s2 < 0 || s2 >= S) { tip.classList.add('hidden'); return; }
        var sec = cfg.sectors[s2];
        var v = cfg.matrix[s2][q];
        tip.innerHTML = '<b>' + sec.code + '</b> ' + sec.label + '<br>' + cfg.labels[q] +
          ' · ΔGVA <span class="tv">' + fmtSigned(v, 2, '%') + '</span>';
        tip.classList.remove('hidden');
        var tx = ev.clientX + 14, ty = ev.clientY + 12;
        if (tx + 350 > window.innerWidth) tx = ev.clientX - 354;
        tip.style.left = tx + 'px'; tip.style.top = ty + 'px';
      });
      svg.addEventListener('mouseleave', function () { tip.classList.add('hidden'); });
    }

    return {
      setCursor: function (c) {
        var q = Math.round(Math.max(0, Math.min(n - 1, c)));
        colHl.setAttribute('x', ML + q * cw);
      }
    };
  }

  /* winners & losers horizontal bars (div-based) */
  function renderWinnersLosers(container, items) {
    container.innerHTML = '';
    if (!items || !items.length) {
      div('wl-empty', container, 'no comparable sector data');
      return;
    }
    var maxAbs = 0;
    items.forEach(function (it) { if (it && Math.abs(it.pct) > maxAbs) maxAbs = Math.abs(it.pct); });
    if (maxAbs === 0) maxAbs = 1;
    items.forEach(function (it) {
      if (it === 'sep') { div('wl-sep', container, '· · ·'); return; }
      var row = div('wl-row', container);
      var code = div('wl-code', row, it.code);
      code.title = it.label;
      var track = div('wl-track', row);
      div('wl-mid', track);
      var fill = div('wl-fill ' + (it.pct >= 0 ? 'pos' : 'neg'), track);
      fill.style.width = (Math.abs(it.pct) / maxAbs * 50).toFixed(1) + '%';
      div('wl-val ' + (it.pct >= 0 ? 'pos' : 'neg'), row, fmtSigned(it.pct, 1, '%'));
    });
  }

  window.Charts = {
    renderRow: renderRow,
    renderSpine: renderSpine,
    renderHeatmap: renderHeatmap,
    renderWinnersLosers: renderWinnersLosers,
    interp: interp,
    fmt0: fmt0, fmt2: fmt2, fmtSigned: fmtSigned,
    COL: COL
  };
})();
