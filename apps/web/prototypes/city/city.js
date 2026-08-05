/* city.js — Econopolis city model: authored map, buildings, landmarks,
   harbor & ships, ground cache, and the per-frame painter's-order renderer. */
window.City = (function () {
  'use strict';
  var I = window.Iso, E = window.Econ;

  /* ---------- deterministic randomness (layout must be stable across frames) ---------- */
  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      var t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  function hash1(n) { var x = Math.sin(n * 127.1) * 43758.5453; return x - Math.floor(x); }

  /* ---------- authored map (grid coordinates) ---------- */
  var ANCHORS = {  // top-left tile of each district plot
    PUB: [1, 1], PROF: [12, 1], ICT: [23, 1], TRANS: [29, 1],
    MANU: [23, 6], FIN: [29, 5], UTIL: [1, 9], AGRI: [1, 13],
    TRADE: [6, 14], CONS: [16, 14], HOSP: [23, 11], ARTS: [23, 17]
  };
  /* characteristic base height per district (px) — FIN/ICT are towers, AGRI is barns */
  var HFACT = { AGRI: 10, MANU: 20, UTIL: 26, CONS: 18, TRADE: 22, TRANS: 16,
                HOSP: 26, ICT: 52, FIN: 58, PROF: 44, PUB: 30, ARTS: 18 };

  var LAND    = { x: 0.5, y: 0.3, w: 35.0, h: 26.4 };
  var PLAZA   = { x: 11, y: 8, w: 11, h: 5 };
  var CAPITOL = { x: 12.1, y: 9.2, w: 2.9, h: 2.7 };
  var CBANK   = { x: 16.3, y: 9.3, w: 1.8, h: 1.8 };
  var BANK    = { x: 19.3, y: 9.3, w: 1.8, h: 1.8 };
  var RESID   = { x: 5, y: 21, w: 11, h: 5 };
  var DOCK    = { x: 34.2, y: 2, w: 1.5, h: 22 };
  var WATER   = { x: 35.7, y: -2.5, w: 12.5, h: 32 };
  var CRANES  = [5.5, 12, 18.5];       // gy positions along the dock
  var SHIP_LANES = [37.6, 39.2, 40.8, 42.4];

  var NIGHT_BG = '#0b1024';
  var WARM = '#ffd28a';                 // lit window color

  /* ================= build ================= */
  function buildCity(iS, nS) {
    var city = {
      plots: [], drawables: [], ships: [], anchors: {},
      firmsByGroup: [], workersByGroup: [],
      groundDirty: true, _ground: null
    };

    // per-group firm & worker totals from the live vectors
    E.GROUPS.forEach(function (g, gi) {
      var f = 0, w = 0;
      for (var i = g.a - 1; i < g.b; i++) { f += (iS[i] || 0); w += (nS[i] || 0); }
      city.firmsByGroup.push(f);
      city.workersByGroup.push(w);
    });

    // districts: ~1 building per 2.5 firms, min 1
    E.GROUPS.forEach(function (g, gi) {
      var n = Math.max(1, Math.ceil(city.firmsByGroup[gi] / 2.5));
      var cols = Math.max(2, Math.ceil(Math.sqrt(n * 1.55)));
      var rows = Math.max(1, Math.ceil(n / cols));
      var ax = ANCHORS[g.id][0], ay = ANCHORS[g.id][1];
      var color = E.COLORS[g.id];
      city.plots.push({ id: g.id, kind: 'district', g: gi, name: g.name,
                        x: ax, y: ay, w: cols, h: rows, color: color });

      // shuffle plot tiles deterministically, take n
      var rng = mulberry32(gi * 7919 + 13);
      var tiles = [];
      for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) tiles.push([c, r]);
      for (var s = tiles.length - 1; s > 0; s--) {
        var j = Math.floor(rng() * (s + 1)), tmp = tiles[s]; tiles[s] = tiles[j]; tiles[j] = tmp;
      }
      var heroTile = Math.floor(rng() * Math.min(n, tiles.length));
      for (var b = 0; b < n && b < tiles.length; b++) {
        var inset = 0.13 + rng() * 0.12;
        var hero = (b === heroTile);
        var baseH = HFACT[g.id] * (0.6 + Math.pow(rng(), 1.4) * 0.9) * (hero ? 1.55 : 1);
        city.drawables.push({
          kind: 'bldg', g: gi, color: color,
          gx: ax + tiles[b][0] + inset, gy: ay + tiles[b][1] + inset,
          fw: 1 - 2 * inset, fh: 1 - 2 * inset,
          baseH: baseH, h: baseH * 0.2, seed: gi * 100 + b,
          faces: {
            left:  I.mix(color, '#10162c', 0.76),
            right: I.mix(color, '#070b18', 0.83),
            top:   I.mix(color, '#232c4e', 0.55)
          }
        });
      }
    });

    // residential quarter: 9,215 households as a field of small warm houses
    (function () {
      var rng = mulberry32(4242);
      var tiles = [];
      for (var r = 0; r < RESID.h; r++) for (var c = 0; c < RESID.w; c++) tiles.push([c, r]);
      for (var s = tiles.length - 1; s > 0; s--) {
        var j = Math.floor(rng() * (s + 1)), tmp = tiles[s]; tiles[s] = tiles[j]; tiles[j] = tmp;
      }
      var color = '#c8a06e';
      for (var b = 0; b < 44; b++) {
        var inset = 0.2 + rng() * 0.14;
        city.drawables.push({
          kind: 'house', color: color,
          gx: RESID.x + tiles[b][0] + inset, gy: RESID.y + tiles[b][1] + inset,
          fw: 1 - 2 * inset, fh: 1 - 2 * inset,
          baseH: 6 + rng() * 7, h: 4, seed: 9000 + b,
          faces: {
            left:  I.mix(color, '#141a30', 0.72),
            right: I.mix(color, '#0a0e1c', 0.80),
            top:   I.mix(color, '#2a3252', 0.58)
          }
        });
      }
      city.plots.push({ id: 'RESID', kind: 'resid', name: 'Residential Quarter',
                        x: RESID.x, y: RESID.y, w: RESID.w, h: RESID.h, color: color });
    })();

    // landmarks (drawn by custom painters, sorted with everything else)
    city.drawables.push({ kind: 'capitol', gx: CAPITOL.x, gy: CAPITOL.y, fw: CAPITOL.w, fh: CAPITOL.h });
    city.drawables.push({ kind: 'cbank',   gx: CBANK.x,   gy: CBANK.y,   fw: CBANK.w,   fh: CBANK.h });
    city.drawables.push({ kind: 'bank',    gx: BANK.x,    gy: BANK.y,    fw: BANK.w,    fh: BANK.h });
    city.plots.push({ id: 'CAPITOL', kind: 'capitol', name: 'The Capitol', x: CAPITOL.x, y: CAPITOL.y, w: CAPITOL.w, h: CAPITOL.h, color: '#e8d9a0' });
    city.plots.push({ id: 'CBANK', kind: 'cbank', name: 'Central Bank', x: CBANK.x, y: CBANK.y, w: CBANK.w, h: CBANK.h, color: '#7de8c8' });
    city.plots.push({ id: 'BANK', kind: 'bank', name: 'Commercial Bank', x: BANK.x, y: BANK.y, w: BANK.w, h: BANK.h, color: '#ffd166' });
    city.plots.push({ id: 'HARBOR', kind: 'harbor', name: 'The Harbor', x: DOCK.x - 0.3, y: DOCK.y - 1, w: WATER.x + 6 - DOCK.x, h: DOCK.h + 2, color: '#63b3ff' });

    // painter's order: ascending (gx+gy)
    city.drawables.sort(function (a, b) { return (a.gx + a.gy) - (b.gx + b.gy) || a.gx - b.gx; });

    // ship pool (activation count & speed driven by trade volume each frame)
    for (var sh = 0; sh < 9; sh++) {
      var rng2 = mulberry32(700 + sh);
      city.ships.push({
        lane: SHIP_LANES[sh % SHIP_LANES.length] + (sh > 3 ? 0.35 : 0),
        gy: -2 + rng2() * 28, dir: (sh % 2 === 0) ? 1 : -1,
        baseSpeed: 0.22 + rng2() * 0.2, phase: rng2() * 6.28, alpha: 0,
        tint: ['#3a7bd5', '#b0533a', '#3aa06b', '#96603f'][sh % 4]
      });
    }
    return city;
  }

  /* ================= camera fit ================= */
  function fitView(city, cssW, cssH, dpr) {
    var minX = I.wx(LAND.x, LAND.y + LAND.h + 1.5);
    var maxX = I.wx(WATER.x + WATER.w, WATER.y);
    var minY = I.wy(LAND.x, -0.7);
    var maxY = I.wy(WATER.x + WATER.w, WATER.y + WATER.h);
    var wW = maxX - minX, wH = maxY - minY;
    var scale = Math.min(cssW / (wW * 0.88), (cssH - 20) / (wH * 0.97));
    scale = Math.max(0.4, Math.min(1.6, scale));
    return {
      scale: scale, dpr: dpr, cssW: cssW, cssH: cssH,
      camX: cssW / 2 - (minX + wW / 2) * scale,
      camY: 12 - minY * scale + (cssH - 20 - wH * scale) / 2
    };
  }
  function project(view, gx, gy, hpx) {
    return [view.camX + I.wx(gx, gy) * view.scale,
            view.camY + (I.wy(gx, gy) - (hpx || 0)) * view.scale];
  }
  /* screen css px -> grid coords (for hover hit-testing) */
  function unproject(view, mx, my) {
    var sx = (mx - view.camX) / view.scale, sy = (my - view.camY) / view.scale;
    return [(sx / I.TW2 + sy / I.TH2) / 2, (sy / I.TH2 - sx / I.TW2) / 2];
  }

  /* ================= static ground cache ================= */
  function buildGround(city, view) {
    var cv = document.createElement('canvas');
    cv.width = Math.max(2, Math.round(view.cssW * view.dpr));
    cv.height = Math.max(2, Math.round(view.cssH * view.dpr));
    var ctx = cv.getContext('2d');
    ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);

    // night sky wash + stars
    var sky = ctx.createLinearGradient(0, 0, 0, view.cssH);
    sky.addColorStop(0, '#070a18'); sky.addColorStop(0.55, NIGHT_BG); sky.addColorStop(1, '#0d1330');
    ctx.fillStyle = sky; ctx.fillRect(0, 0, view.cssW, view.cssH);
    for (var st = 0; st < 90; st++) {
      var sxs = hash1(st * 3.1) * view.cssW, sys = hash1(st * 7.7) * view.cssH * 0.5;
      ctx.fillStyle = 'rgba(190,210,255,' + (0.05 + hash1(st * 11.3) * 0.22) + ')';
      ctx.fillRect(sxs, sys, hash1(st * 5.9) > 0.85 ? 1.6 : 1, 1);
    }

    ctx.translate(view.camX, view.camY);
    ctx.scale(view.scale, view.scale);

    // water
    I.diamond(ctx, WATER.x, WATER.y, WATER.w, WATER.h);
    var wat = ctx.createLinearGradient(I.wx(WATER.x, WATER.y), I.wy(WATER.x, WATER.y),
                                       I.wx(WATER.x, WATER.y + WATER.h), I.wy(WATER.x + WATER.w, WATER.y + WATER.h));
    wat.addColorStop(0, '#0a2140'); wat.addColorStop(1, '#061428');
    ctx.fillStyle = wat; ctx.fill();

    // land slab
    I.diamond(ctx, LAND.x, LAND.y, LAND.w, LAND.h);
    ctx.fillStyle = '#121834'; ctx.fill();
    ctx.strokeStyle = 'rgba(120,150,255,0.10)'; ctx.lineWidth = 1.4; ctx.stroke();
    // coast glow
    ctx.beginPath();
    ctx.moveTo(I.wx(LAND.x + LAND.w, LAND.y), I.wy(LAND.x + LAND.w, LAND.y));
    ctx.lineTo(I.wx(LAND.x + LAND.w, LAND.y + LAND.h), I.wy(LAND.x + LAND.w, LAND.y + LAND.h));
    ctx.strokeStyle = 'rgba(110,190,255,0.25)'; ctx.lineWidth = 2; ctx.stroke();

    // plaza
    I.diamond(ctx, PLAZA.x, PLAZA.y, PLAZA.w, PLAZA.h);
    ctx.fillStyle = '#1a2140'; ctx.fill();
    ctx.strokeStyle = 'rgba(232,217,160,0.18)'; ctx.lineWidth = 1; ctx.stroke();

    // district slabs + faint tile grid
    city.plots.forEach(function (p) {
      if (p.kind !== 'district' && p.kind !== 'resid') return;
      I.diamond(ctx, p.x - 0.25, p.y - 0.25, p.w + 0.5, p.h + 0.5);
      ctx.fillStyle = I.mix(p.color, '#101632', 0.88);
      ctx.fill();
      ctx.strokeStyle = I.rgba(p.color, 0.28); ctx.lineWidth = 1; ctx.stroke();
      ctx.strokeStyle = 'rgba(255,255,255,0.035)'; ctx.lineWidth = 0.7;
      ctx.beginPath();
      for (var c = 1; c < p.w; c++) {
        ctx.moveTo(I.wx(p.x + c, p.y), I.wy(p.x + c, p.y));
        ctx.lineTo(I.wx(p.x + c, p.y + p.h), I.wy(p.x + c, p.y + p.h));
      }
      for (var r = 1; r < p.h; r++) {
        ctx.moveTo(I.wx(p.x, p.y + r), I.wy(p.x, p.y + r));
        ctx.lineTo(I.wx(p.x + p.w, p.y + r), I.wy(p.x + p.w, p.y + r));
      }
      ctx.stroke();
    });

    // dock slab + edge
    I.diamond(ctx, DOCK.x, DOCK.y, DOCK.w, DOCK.h);
    ctx.fillStyle = '#232941'; ctx.fill();
    ctx.strokeStyle = 'rgba(160,180,220,0.22)'; ctx.lineWidth = 1; ctx.stroke();

    return cv;
  }

  /* ================= landmark painters ================= */
  function drawCapitol(ctx, d, time) {
    var g = d.gx, gy = d.gy, w = d.fw, h = d.fh;
    // stepped base
    I.box(ctx, g, gy, w, h, 10, { left: '#232a48', right: '#1a2038', top: '#333c60' });
    // main hall with colonnade
    var m = 0.32;
    var c = I.box(ctx, g + m, gy + m, w - 2 * m, h - 2 * m, 30,
                  { left: '#2e3658', right: '#242b46', top: '#3d4670' });
    // columns: light bars on both visible faces
    ctx.fillStyle = 'rgba(196,206,240,0.5)';
    for (var i = 0; i < 5; i++) {
      var t = (i + 0.5) / 5;
      var lx = c.w[0] + (c.s[0] - c.w[0]) * t, ly = c.w[1] + (c.s[1] - c.w[1]) * t;
      ctx.fillRect(lx - 0.8, ly - 26, 1.6, 22);
      var rx = c.s[0] + (c.e[0] - c.s[0]) * t, ry = c.s[1] + (c.e[1] - c.s[1]) * t;
      ctx.fillRect(rx - 0.8, ry - 26, 1.6, 22);
    }
    // drum + dome
    var cx = (c.n[0] + c.s[0]) / 2, cyTop = (c.n[1] + c.s[1]) / 2 - 30;
    I.box(ctx, g + w / 2 - 0.42, gy + h / 2 - 0.42, 0.84, 0.84, 42,
          { left: '#39406a', right: '#2c3254', top: '#474f80' });
    var dg = ctx.createLinearGradient(cx - 16, cyTop - 58, cx + 16, cyTop - 40);
    dg.addColorStop(0, '#8d9ad0'); dg.addColorStop(1, '#3c4470');
    ctx.fillStyle = dg;
    ctx.beginPath(); ctx.ellipse(cx, cyTop - 42, 15, 13, 0, Math.PI, 2 * Math.PI); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#2f365c';
    ctx.beginPath(); ctx.ellipse(cx, cyTop - 42, 15, 4.5, 0, 0, 2 * Math.PI); ctx.fill();
    // cupola beacon
    var pulse = 0.65 + 0.35 * Math.sin(time * 1.8);
    ctx.fillStyle = 'rgba(255,214,140,' + (0.5 * pulse) + ')';
    ctx.beginPath(); ctx.arc(cx, cyTop - 57, 3.4, 0, 6.284); ctx.fill();
    ctx.fillStyle = '#ffe9c0';
    ctx.fillRect(cx - 0.8, cyTop - 60, 1.6, 5);
  }

  function windowsForBox(ctx, corners, hpx, seed, litFrac, time) {
    ctx.beginPath();
    I.faceWindows(ctx, corners.w, corners.s, hpx, function (c, r) {
      var h0 = hash1(seed * 13.7 + c * 3.13 + r * 7.77 + 11.1);
      var lit = h0 < litFrac;
      // subtle flicker: a few windows toggle every so often
      if (hash1(seed * 3.3 + c * 11.9 + r * 5.1 + Math.floor(time * 1.6 + h0 * 9)) < 0.05) lit = !lit;
      return lit;
    });
    I.faceWindows(ctx, corners.s, corners.e, hpx, function (c, r) {
      var h0 = hash1(seed * 17.3 + c * 5.7 + r * 3.9 + 29.7);
      var lit = h0 < litFrac;
      if (hash1(seed * 7.1 + c * 9.3 + r * 6.7 + Math.floor(time * 1.6 + h0 * 9)) < 0.05) lit = !lit;
      return lit;
    });
  }

  function drawCBank(ctx, d, view, city, time) {
    var hpx = 100;
    var c = I.box(ctx, d.gx, d.gy, d.fw, d.fh, hpx,
                  { left: '#252e52', right: '#1b2340', top: '#324066' });
    // cool white windows
    windowsForBox(ctx, c, hpx, 555, 0.5, time);
    ctx.fillStyle = 'rgba(190,240,255,0.75)'; ctx.fill();
    // rooftop beacon
    var top = [(c.n[0] + c.s[0]) / 2, (c.n[1] + c.s[1]) / 2 - hpx];
    var pulse = 0.5 + 0.5 * Math.sin(time * 2.4);
    ctx.fillStyle = 'rgba(125,232,200,' + (0.25 + 0.45 * pulse) + ')';
    ctx.beginPath(); ctx.arc(top[0], top[1] - 6, 3 + pulse * 1.5, 0, 6.284); ctx.fill();
    // remember SE-face center (screen space) for the glowing rate readout
    var fx = (c.s[0] + c.e[0]) / 2, fy = (c.s[1] + c.e[1]) / 2 - hpx * 0.62;
    city.anchors.rate = [view.camX + fx * view.scale, view.camY + fy * view.scale];
  }

  function drawBank(ctx, d, view, city, time) {
    var hpx = 62;
    var c = I.box(ctx, d.gx, d.gy, d.fw, d.fh, hpx,
                  { left: '#3a3050', right: '#2b2340', top: '#57496e' });
    windowsForBox(ctx, c, hpx, 777, 0.55, time);
    ctx.fillStyle = 'rgba(255,209,102,0.8)'; ctx.fill();
    var fx = (c.s[0] + c.e[0]) / 2, fy = (c.s[1] + c.e[1]) / 2 - hpx - 12;
    city.anchors.bank = [view.camX + fx * view.scale, view.camY + fy * view.scale];
  }

  function drawCranes(ctx, time) {
    CRANES.forEach(function (cy, i) {
      var bx = I.wx(DOCK.x + 0.9, cy), by = I.wy(DOCK.x + 0.9, cy);
      ctx.strokeStyle = '#4a5578'; ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(bx, by); ctx.lineTo(bx, by - 36);                    // mast
      ctx.lineTo(bx + 22, by - 36 + 11 * 0.8);                        // jib toward water
      ctx.moveTo(bx, by - 36); ctx.lineTo(bx - 8, by - 36 - 4);       // counter-jib
      ctx.stroke();
      ctx.strokeStyle = 'rgba(160,180,220,0.35)'; ctx.lineWidth = 0.8;
      ctx.beginPath(); ctx.moveTo(bx, by - 44); ctx.lineTo(bx + 22, by - 36 + 8.8); ctx.stroke();
      var blink = Math.sin(time * 2 + i * 2.1) > 0.4;
      if (blink) {
        ctx.fillStyle = 'rgba(255,90,90,0.9)';
        ctx.beginPath(); ctx.arc(bx + 22, by - 36 + 8.8, 1.8, 0, 6.284); ctx.fill();
      }
    });
  }

  function drawShip(ctx, sh, time) {
    if (sh.alpha <= 0.02) return;
    var p = [I.wx(sh.lane, sh.gy), I.wy(sh.lane, sh.gy) + Math.sin(time * 1.3 + sh.phase) * 1.3];
    // unit vector along +gy (sailing direction axis)
    var ux = -I.TW2, uy = I.TH2, ul = Math.sqrt(ux * ux + uy * uy);
    ux /= ul; uy /= ul;
    var px = -uy, py = ux;                       // perpendicular
    var L = 17, Wd = 5;
    var d = sh.dir;
    ctx.globalAlpha = sh.alpha;
    // wake
    ctx.strokeStyle = 'rgba(140,190,255,0.28)'; ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(p[0] - ux * d * (L + 4) - px * 2, p[1] - uy * d * (L + 4) - py * 2);
    ctx.lineTo(p[0] - ux * d * (L + 16), p[1] - uy * d * (L + 16));
    ctx.moveTo(p[0] - ux * d * (L + 4) + px * 2, p[1] - uy * d * (L + 4) + py * 2);
    ctx.lineTo(p[0] - ux * d * (L + 13), p[1] - uy * d * (L + 13));
    ctx.stroke();
    // hull
    ctx.fillStyle = '#1d2742';
    ctx.beginPath();
    ctx.moveTo(p[0] + ux * d * (L + 7), p[1] + uy * d * (L + 7));                 // bow tip
    ctx.lineTo(p[0] + ux * d * L + px * Wd, p[1] + uy * d * L + py * Wd);
    ctx.lineTo(p[0] - ux * d * L + px * Wd, p[1] - uy * d * L + py * Wd);
    ctx.lineTo(p[0] - ux * d * L - px * Wd, p[1] - uy * d * L - py * Wd);
    ctx.lineTo(p[0] + ux * d * L - px * Wd, p[1] + uy * d * L - py * Wd);
    ctx.closePath(); ctx.fill();
    ctx.strokeStyle = 'rgba(150,180,230,0.35)'; ctx.lineWidth = 0.7; ctx.stroke();
    // containers
    ctx.fillStyle = sh.tint;
    ctx.fillRect(p[0] - ux * d * 6 - 4, p[1] - uy * d * 6 - 6, 8, 4);
    ctx.fillStyle = I.shade(sh.tint, -0.25);
    ctx.fillRect(p[0] + ux * d * 3 - 3.5, p[1] + uy * d * 3 - 6, 7, 4);
    // bridge + lights
    ctx.fillStyle = '#c9d4ec';
    ctx.fillRect(p[0] - ux * d * (L - 3) - 2.5, p[1] - uy * d * (L - 3) - 9, 5, 6);
    ctx.fillStyle = 'rgba(255,220,150,0.95)';
    ctx.fillRect(p[0] - ux * d * (L - 3) - 1.5, p[1] - uy * d * (L - 3) - 8, 3, 1.6);
    ctx.fillStyle = d > 0 ? 'rgba(120,255,140,0.9)' : 'rgba(255,110,110,0.9)';
    ctx.beginPath(); ctx.arc(p[0] + ux * d * (L + 6), p[1] + uy * d * (L + 6) - 2, 1.2, 0, 6.284); ctx.fill();
    ctx.globalAlpha = 1;
  }

  /* ================= per-frame render =================
     S: { time, dt, idx[12], ghost[12]|null, lit[12], residLit,
          shipCount, shipSpeedMul, hoverId, rateText } */
  function render(ctx, city, view, S) {
    if (city.groundDirty || !city._ground) {
      city._ground = buildGround(city, view);
      city.groundDirty = false;
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, view.cssW * view.dpr, view.cssH * view.dpr);
    ctx.drawImage(city._ground, 0, 0, view.cssW * view.dpr, view.cssH * view.dpr,
                  0, 0, view.cssW * view.dpr, view.cssH * view.dpr);

    // world space
    ctx.setTransform(view.dpr * view.scale, 0, 0, view.dpr * view.scale,
                     view.dpr * view.camX, view.dpr * view.camY);

    // animated wave streaks on the water
    ctx.strokeStyle = 'rgba(120,180,255,0.10)'; ctx.lineWidth = 1;
    ctx.beginPath();
    for (var wv = 0; wv < 14; wv++) {
      var gyw = ((S.time * 0.35 + wv * 2.31) % 31) - 2.5;
      var gxw = WATER.x + 0.8 + (wv % 5) * 2.2;
      var ax = I.wx(gxw, gyw), ay = I.wy(gxw, gyw) + Math.sin(S.time + wv) * 1.5;
      ctx.moveTo(ax, ay); ctx.lineTo(ax + 14, ay + 3);
    }
    ctx.stroke();

    // hover highlight under the buildings
    if (S.hoverId) {
      var hp = null;
      for (var pi = 0; pi < city.plots.length; pi++) if (city.plots[pi].id === S.hoverId) hp = city.plots[pi];
      if (hp && hp.kind !== 'harbor') {
        I.diamond(ctx, hp.x - 0.3, hp.y - 0.3, hp.w + 0.6, hp.h + 0.6);
        ctx.fillStyle = I.rgba(hp.color, 0.10); ctx.fill();
        ctx.strokeStyle = I.rgba(hp.color, 0.55); ctx.lineWidth = 1.5; ctx.stroke();
      }
    }

    drawCranes(ctx, S.time);

    // drawables, back to front
    var ease = Math.min(1, S.dt * 3.2);
    for (var i = 0; i < city.drawables.length; i++) {
      var d = city.drawables[i];
      if (d.kind === 'capitol') { drawCapitol(ctx, d, S.time); continue; }
      if (d.kind === 'cbank') { drawCBank(ctx, d, view, city, S.time); continue; }
      if (d.kind === 'bank') { drawBank(ctx, d, view, city, S.time); continue; }

      var idx = 1, lit = 0.5;
      if (d.kind === 'bldg') { idx = S.idx[d.g]; lit = S.lit[d.g]; }
      else if (d.kind === 'house') { idx = 0.9 + 0.1 * S.residLit / 0.6; lit = S.residLit; }
      // height = base * index^2 so changes in GVA are visible in the skyline
      var target = Math.max(2.5, d.baseH * idx * idx);
      d.h += (target - d.h) * ease;

      var c = I.box(ctx, d.gx, d.gy, d.fw, d.fh, d.h, d.faces);
      if (d.h > 11) {
        windowsForBox(ctx, c, d.h, d.seed, lit, S.time);
        ctx.fillStyle = I.rgba(WARM, d.kind === 'house' ? 0.95 : 0.82);
        ctx.fill();
      }
      // baseline ghost outline (only for district buildings during a policy run)
      if (S.ghost && d.kind === 'bldg') {
        var gh = Math.max(2.5, d.baseH * S.ghost[d.g] * S.ghost[d.g]);
        if (Math.abs(gh - target) > 1.2) {
          ctx.strokeStyle = 'rgba(210,225,255,0.16)'; ctx.lineWidth = 0.8;
          I.boxGhost(ctx, d.gx, d.gy, d.fw, d.fh, gh);
        }
      }
    }

    // ships: activate `shipCount`, sail along the coast
    for (var s = 0; s < city.ships.length; s++) {
      var sh = city.ships[s];
      var want = s < S.shipCount ? 1 : 0;
      sh.alpha += (want - sh.alpha) * Math.min(1, S.dt * 1.2);
      if (sh.alpha > 0.02) {
        sh.gy += sh.dir * sh.baseSpeed * S.shipSpeedMul * S.dt;
        if (sh.gy > 30) sh.gy = -3.5;
        if (sh.gy < -3.5) sh.gy = 30;
        drawShip(ctx, sh, S.time);
      }
    }

    /* ---------- crisp screen-space layer: plaques + readouts ---------- */
    ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    city.plots.forEach(function (p) {
      if (p.kind === 'harbor') return;                    // harbor gets its plaque on the dock
      var a = project(view, p.x + p.w / 2, p.y + p.h, 0);
      plaque(ctx, a[0], a[1] + 9, p.kind === 'district' ? p.id : p.name.toUpperCase(), p.color, p.id === S.hoverId);
    });
    var hb = project(view, DOCK.x + DOCK.w / 2, DOCK.y + DOCK.h + 0.4, 0);
    plaque(ctx, hb[0], hb[1] + 8, 'HARBOR', '#63b3ff', S.hoverId === 'HARBOR');

    // central-bank glowing rate readout
    if (city.anchors.rate && S.rateText) {
      var ra = city.anchors.rate;
      ctx.font = '700 13px ui-monospace, SFMono-Regular, Menlo, monospace';
      var tw = ctx.measureText(S.rateText).width + 14;
      ctx.fillStyle = 'rgba(4,10,16,0.85)';
      roundRect(ctx, ra[0] - tw / 2, ra[1] - 10, tw, 20, 4); ctx.fill();
      ctx.strokeStyle = 'rgba(60,220,180,0.5)'; ctx.lineWidth = 1;
      roundRect(ctx, ra[0] - tw / 2, ra[1] - 10, tw, 20, 4); ctx.stroke();
      ctx.shadowColor = '#2fe9b6'; ctx.shadowBlur = 9;
      ctx.fillStyle = '#5cf5cb';
      ctx.fillText(S.rateText, ra[0], ra[1] + 0.5);
      ctx.shadowBlur = 0;
      ctx.font = '600 6.5px ui-monospace, monospace';
      ctx.fillStyle = 'rgba(140,240,210,0.75)';
      ctx.fillText('POLICY RATE', ra[0], ra[1] - 15);
    }
    // commercial bank sign
    if (city.anchors.bank) {
      var ba = city.anchors.bank;
      ctx.shadowColor = '#ffd166'; ctx.shadowBlur = 8;
      ctx.fillStyle = '#ffd97e';
      ctx.font = '700 15px Georgia, serif';
      ctx.fillText('€', ba[0], ba[1]);
      ctx.shadowBlur = 0;
    }
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function plaque(ctx, x, y, text, color, hot) {
    ctx.font = '700 9px system-ui, sans-serif';
    var tw = ctx.measureText(text).width + 12;
    ctx.fillStyle = hot ? 'rgba(16,22,44,0.95)' : 'rgba(8,11,24,0.72)';
    roundRect(ctx, x - tw / 2, y - 8, tw, 15, 7); ctx.fill();
    ctx.strokeStyle = I.rgba ? window.Iso.rgba(color, hot ? 0.9 : 0.45) : color;
    ctx.lineWidth = 1;
    roundRect(ctx, x - tw / 2, y - 8, tw, 15, 7); ctx.stroke();
    ctx.fillStyle = hot ? '#ffffff' : '#c6cfe8';
    ctx.fillText(text, x, y);
  }

  /* which plot is under grid point (gx,gy)? */
  function hitTest(city, gx, gy) {
    // landmarks & special zones first (they sit inside/over other slabs)
    var order = ['CAPITOL', 'CBANK', 'BANK', 'HARBOR', 'RESID'];
    for (var o = 0; o < order.length; o++) {
      var p = null;
      for (var i = 0; i < city.plots.length; i++) if (city.plots[i].id === order[o]) p = city.plots[i];
      if (p && gx >= p.x - 0.3 && gx <= p.x + p.w + 0.3 && gy >= p.y - 0.3 && gy <= p.y + p.h + 0.3) return p;
    }
    for (var j = 0; j < city.plots.length; j++) {
      p = city.plots[j];
      if (p.kind !== 'district') continue;
      if (gx >= p.x - 0.3 && gx <= p.x + p.w + 0.3 && gy >= p.y - 0.3 && gy <= p.y + p.h + 0.3) return p;
    }
    return null;
  }

  return { buildCity: buildCity, fitView: fitView, project: project, unproject: unproject,
           render: render, hitTest: hitTest };
})();
