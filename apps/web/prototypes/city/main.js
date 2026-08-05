/* main.js — Econopolis app: boot, HUD, ticker, policy cards, run flow, rAF loop. */
(function () {
  'use strict';
  var E = window.Econ, C = window.City;

  /* ---------------- state ---------------- */
  var S = {
    city: null, view: null,
    tl: null,               // timeline currently on screen
    baseTl: null,           // newest done baseline run of the dataset (the "ghost")
    mode: 'baseline',       // 'baseline' | 'card'
    qTime: 0, playing: true, speedIdx: 1,
    speeds: [0.25, 0.5, 1.0],          // quarters per second
    lastTs: 0, time: 0,
    hoverId: null, mouse: [0, 0],
    knobs: null, sectorMeta: null,
    selectedCards: [], runInFlight: false, pollTimer: null,
    endShown: false, feed: [], feedX: 0, feedW: 1,
    runsList: []
  };

  /* ---------------- dom ---------------- */
  function $(id) { return document.getElementById(id); }
  var canvas = $('city'), ctx = canvas.getContext('2d');
  var gauge = $('gaugeCanvas'), gctx = gauge.getContext('2d');
  var tooltip = $('tooltip');

  function showError(msg, sticky) {
    var b = $('errorBanner');
    b.innerHTML = msg + ' <button id="retryBtn">RETRY</button>';
    b.classList.remove('hidden');
    var r = $('retryBtn');
    if (r) r.onclick = function () { location.reload(); };
    if (!sticky) setTimeout(function () { b.classList.add('hidden'); }, 12000);
  }

  /* ---------------- boot ---------------- */
  function boot() {
    resize();
    window.addEventListener('resize', resize);

    var pMeta = fetch('sector-metadata.json').then(function (r) { return r.json(); }).catch(function () { return null; });
    var pRuns = E.fetchJSON('/api/runs');
    var pKnobs = E.fetchJSON('/api/knobs?dataset_id=AUSTRIA2026Q1').catch(function () { return null; });
    var pIS = E.fetchJSON('/api/datasets/value?dataset_id=AUSTRIA2026Q1&group=parameters&key=I_s').catch(function () { return null; });
    var pNS = E.fetchJSON('/api/datasets/value?dataset_id=AUSTRIA2026Q1&group=initial_conditions&key=N_s').catch(function () { return null; });

    Promise.all([pMeta, pKnobs, pIS, pNS]).then(function (res) {
      S.sectorMeta = res[0];
      S.knobs = {};
      if (res[1]) res[1].forEach(function (k) { S.knobs[k.key] = k.default; });
      else S.knobs = Object.assign({}, E.FALLBACK_KNOBS);
      var iS = res[2] ? res[2].value : E.FALLBACK_I_S;
      var nS = res[3] ? res[3].value : E.FALLBACK_N_S;
      S.city = C.buildCity(iS, nS);
      resize();
      buildCards();
    });

    pRuns.then(function (runs) {
      S.runsList = runs || [];
      var done = S.runsList.filter(function (r) { return r.state === 'done'; });
      if (!done.length) {
        showError('No completed runs on the backend yet — the city is idling. Play a policy card to simulate one.', true);
        return;
      }
      // newest done run, preferring the AUSTRIA2026Q1 dataset
      var preferred = done.filter(function (r) { return r.dataset_id === 'AUSTRIA2026Q1'; });
      var current = (preferred.length ? preferred : done)[0];
      // ghost source: newest done *baseline* run of the same dataset
      var baseRun = done.filter(function (r) {
        return r.dataset_id === current.dataset_id && r.scenario === 'baseline';
      })[0] || current;

      E.fetchJSON('/api/runs/' + current.run_id + '/summary').then(function (sum) {
        setTimeline(E.buildTimeline(sum), 'baseline');
        $('datasetChip').textContent = sum.dataset_id + ' · ' + sum.scenario;
      }).catch(function (e) { showError('Could not load run summary: ' + e.message, true); });

      if (baseRun.run_id !== current.run_id) {
        E.fetchJSON('/api/runs/' + baseRun.run_id + '/summary').then(function (sum) {
          S.baseTl = E.buildTimeline(sum);
        }).catch(function () { /* ghost is optional */ });
      }
    }).catch(function (e) {
      showError('Backend unreachable (' + e.message + '). Showing an empty city.', true);
    });

    bindUI();
    requestAnimationFrame(frame);
  }

  function setTimeline(tl, mode) {
    S.tl = tl;
    S.mode = mode;
    if (mode === 'baseline' && tl.scenario === 'baseline' && !S.baseTl) S.baseTl = tl;
    S.qTime = 0; S.playing = true; S.endShown = false;
    S.feed = []; S.feedX = 0;
    pushFeedItem({ period: tl.periods[0], text: (mode === 'card' ? 'Policy run begins — ' : 'Timeline loaded — ') + tl.datasetId + ' / ' + tl.scenario + ', ' + tl.T + ' quarters', cls: 'flat' });
    var chip = $('timelineChip');
    if (mode === 'card') {
      chip.textContent = 'POLICY RUN · ' + (tl.cardNames || []).join(' + ');
      chip.className = 'chip chip-card';
      $('ghostLegend').classList.toggle('hidden', !S.baseTl);
    } else {
      chip.textContent = 'CURRENT TIMELINE';
      chip.className = 'chip chip-baseline';
      $('ghostLegend').classList.add('hidden');
    }
  }

  /* ---------------- layout / resize ---------------- */
  function resize() {
    var wrap = $('cityWrap');
    var w = wrap.clientWidth, h = wrap.clientHeight;
    var dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(2, Math.round(w * dpr));
    canvas.height = Math.max(2, Math.round(h * dpr));
    canvas.style.width = w + 'px';
    canvas.style.height = h + 'px';
    if (S.city) {
      S.view = C.fitView(S.city, w, h, dpr);
      S.city.groundDirty = true;
    }
  }

  /* ---------------- per-frame ---------------- */
  function frame(ts) {
    requestAnimationFrame(frame);
    var dt = S.lastTs ? Math.min(0.1, (ts - S.lastTs) / 1000) : 0.016;
    S.lastTs = ts; S.time += dt;
    if (!S.city || !S.view) return;

    var tl = S.tl;
    if (tl && S.playing) {
      var prevQ = Math.floor(S.qTime);
      S.qTime = Math.min(tl.T, S.qTime + dt * S.speeds[S.speedIdx]);
      var newQ = Math.floor(S.qTime);
      for (var q = prevQ + 1; q <= newQ; q++) {
        (tl.headlines[q] || []).forEach(pushFeedItem);
      }
      if (S.qTime >= tl.T) {
        S.playing = false;
        updatePlayBtn();
        if (S.mode === 'card' && !S.endShown) {
          S.endShown = true;
          setTimeout(showEndScreen, 700);
        }
      }
    }

    // frame inputs for the city renderer
    var idx = [], ghost = null, lit = [], residLit = 0.5;
    var shipCount = 4, shipSpeedMul = 1, rateText = '';
    if (tl) {
      for (var g = 0; g < 12; g++) {
        var v = sampleGroup(tl, g, S.qTime);
        idx.push(v);
        lit.push(E.clamp(0.30 + 0.55 * (v - 0.75) / 0.5, 0.14, 0.9));
      }
      if (S.mode === 'card' && S.baseTl) {
        ghost = [];
        for (g = 0; g < 12; g++) ghost.push(sampleGroup(S.baseTl, g, Math.min(S.qTime, S.baseTl.T)));
      }
      residLit = E.clamp(0.65 * Math.pow(E.sample(tl.realWageIdx, S.qTime), 2), 0.08, 0.95);
      var vol = E.sample(tl.tradeVol, S.qTime);
      shipCount = E.clamp(Math.round(vol / 19000), 1, 9);
      shipSpeedMul = E.clamp(E.safeDiv(vol, tl.tradeVol[0], 1), 0.5, 1.8);
      rateText = (E.sample(tl.rateA, S.qTime) * 100).toFixed(2) + '%';
    } else {
      for (g = 0; g < 12; g++) { idx.push(1); lit.push(0.4); }
    }

    C.render(ctx, S.city, S.view, {
      time: S.time, dt: dt, idx: idx, ghost: ghost, lit: lit, residLit: residLit,
      shipCount: shipCount, shipSpeedMul: shipSpeedMul, hoverId: S.hoverId, rateText: rateText
    });

    if (tl) { updateHUD(tl); updateTransport(tl); }
    tickTicker(dt);
  }

  function sampleGroup(tl, g, qt) {
    var n = tl.groupIdx.length;
    if (qt <= 0) return tl.groupIdx[0][g];
    if (qt >= n - 1) return tl.groupIdx[n - 1][g];
    var i = Math.floor(qt);
    return E.lerp(tl.groupIdx[i][g], tl.groupIdx[i + 1][g], qt - i);
  }

  /* ---------------- HUD ---------------- */
  function deltaSpan(el, pct, digits, invert) {
    if (pct == null || !isFinite(pct)) { el.textContent = ''; return; }
    var up = pct >= 0;
    var good = invert ? !up : up;
    el.innerHTML = (up ? '&#9650; ' : '&#9660; ') + E.fmtSignedPct(pct, digits == null ? 1 : digits) + ' q/q';
    el.className = 'kpi-delta ' + (good ? 'good' : 'bad');
  }

  function updateHUD(tl) {
    var q = Math.floor(S.qTime);
    $('quarterBig').textContent = tl.periods[q] || '—';

    $('kpiGdp').textContent = E.fmtBn(E.sample(tl.gdp, S.qTime));
    deltaSpan($('kpiGdpDelta'), q >= 1 ? E.safeDiv(tl.gdp[q], tl.gdp[q - 1], 1) - 1 : null);

    var infl = E.sample(tl.inflYoY, S.qTime);
    $('kpiInfl').textContent = E.fmtPct(infl, 1);
    drawGauge(infl);

    $('kpiRate').textContent = (E.sample(tl.rateA, S.qTime) * 100).toFixed(2) + '%';
    var rd = $('kpiRateDelta');
    if (q >= 1) {
      var dr = (tl.rateA[q] - tl.rateA[q - 1]) * 100;
      rd.textContent = (Math.abs(dr) < 0.005) ? 'holding' : ((dr > 0 ? '+' : '') + dr.toFixed(2) + 'pp');
      rd.className = 'kpi-delta ' + (Math.abs(dr) < 0.005 ? '' : (dr > 0 ? 'bad' : 'good'));
    } else { rd.textContent = ''; }

    var tb = E.sample(tl.tradeBal, S.qTime);
    var te = $('kpiTrade');
    te.textContent = E.fmtSignedBn(tb);
    te.style.color = tb >= 0 ? 'var(--good)' : 'var(--bad)';
    var td = $('kpiTradeDelta');
    if (q >= 1) {
      var dtb = tl.tradeBal[q] - tl.tradeBal[q - 1];
      td.textContent = (dtb >= 0 ? 'improving' : 'widening');
      td.className = 'kpi-delta ' + (dtb >= 0 ? 'good' : 'bad');
    } else td.textContent = '';
  }

  /* inflation gauge: blue deflation | green 0–2.5 | amber 2.5–4 | red 4+ */
  function drawGauge(infl) {
    var w = gauge.width, h = gauge.height, cx = w / 2, cy = h - 6, R = Math.min(cx - 4, h - 14);
    gctx.clearRect(0, 0, w, h);
    var lo = -0.015, hi = 0.06;
    function ang(v) { return Math.PI + (E.clamp(v, lo, hi) - lo) / (hi - lo) * Math.PI; }
    var zones = [[-0.015, 0, '#4d7dd6'], [0, 0.025, '#3fce77'], [0.025, 0.04, '#e8b23c'], [0.04, 0.06, '#e05252']];
    zones.forEach(function (z) {
      gctx.beginPath();
      gctx.arc(cx, cy, R, ang(z[0]), ang(z[1]));
      gctx.strokeStyle = z[2]; gctx.lineWidth = 7; gctx.stroke();
    });
    // target tick at 2% (pi_star annualized)
    gctx.beginPath();
    var ta = ang(0.02);
    gctx.moveTo(cx + Math.cos(ta) * (R - 6), cy + Math.sin(ta) * (R - 6));
    gctx.lineTo(cx + Math.cos(ta) * (R + 6), cy + Math.sin(ta) * (R + 6));
    gctx.strokeStyle = 'rgba(255,255,255,0.55)'; gctx.lineWidth = 1.4; gctx.stroke();
    // needle
    var na = ang(infl);
    gctx.beginPath();
    gctx.moveTo(cx, cy);
    gctx.lineTo(cx + Math.cos(na) * (R - 3), cy + Math.sin(na) * (R - 3));
    gctx.strokeStyle = '#f4f7ff'; gctx.lineWidth = 2; gctx.stroke();
    gctx.beginPath(); gctx.arc(cx, cy, 2.6, 0, 6.284); gctx.fillStyle = '#f4f7ff'; gctx.fill();
  }

  /* ---------------- transport + ticker ---------------- */
  function updateTransport(tl) {
    var scrub = $('scrub');
    if (document.activeElement !== scrub) scrub.value = Math.round(S.qTime / tl.T * 1000);
    $('scrubLabel').textContent = 'Q' + (Math.floor(S.qTime) + 1) + '/' + (tl.T + 1) + ' · ' + (tl.periods[Math.floor(S.qTime)] || '');
  }
  function updatePlayBtn() {
    $('playBtn').innerHTML = S.playing ? '&#10074;&#10074;' : '&#9654;';
  }

  function pushFeedItem(it) {
    S.feed.push(it);
    if (S.feed.length > 14) S.feed.shift();
    var html = '';
    for (var r = 0; r < 2; r++) {          // duplicated for seamless loop
      S.feed.forEach(function (f) {
        html += '<span class="tk ' + (f.cls || '') + '"><b>' + f.period + '</b>' + f.text + '</span><span class="tksep">&#9670;</span>';
      });
    }
    var inner = $('tickerInner');
    inner.innerHTML = html;
    S.feedW = Math.max(1, inner.scrollWidth / 2);
  }
  function tickTicker(dt) {
    var inner = $('tickerInner');
    if (!S.feed.length) return;
    S.feedX += dt * 55;
    if (S.feedX > S.feedW) S.feedX -= S.feedW;
    inner.style.transform = 'translateX(' + (-S.feedX) + 'px)';
  }

  /* ---------------- policy cards ---------------- */
  function buildCards() {
    var wrap = $('cards');
    wrap.innerHTML = '';
    wrap.setAttribute('role', 'group');
    wrap.setAttribute('aria-label', 'Policy cards. Choose up to three, with at most one shock.');
    $('runHint').setAttribute('aria-live', 'polite');
    E.CARDS.forEach(function (c) {
      var el = document.createElement('button');
      var descriptionId = 'card-description-' + c.id;
      var statusId = 'card-status-' + c.id;
      el.type = 'button';
      el.className = 'card kind-' + c.kind;
      el.id = 'card-' + c.id;
      el.setAttribute('aria-label', c.name + ' policy card');
      el.setAttribute('aria-describedby', descriptionId + ' ' + statusId);
      el.setAttribute('aria-pressed', 'false');
      el.innerHTML =
        '<div class="card-top"><span class="mono">' + c.mono + '</span>' +
        '<span class="card-name">' + c.name + '</span>' +
        '<span class="kind-tag">' + c.kind.toUpperCase() + '</span></div>' +
        '<div class="card-flavor" id="' + descriptionId + '">' + c.flavor + '</div>' +
        '<div class="card-dials">' + c.dials.map(function (d) { return '<span>' + d + '</span>'; }).join('') + '</div>' +
        '<span class="sr-only" id="' + statusId + '"></span>';
      el.onclick = function () { toggleCard(c.id); };
      wrap.appendChild(el);
    });
    refreshCards();
  }

  function toggleCard(id) {
    var i = S.selectedCards.indexOf(id);
    if (i >= 0) S.selectedCards.splice(i, 1);
    else {
      var card = E.CARDS.filter(function (c) { return c.id === id; })[0];
      var haveShock = S.selectedCards.some(function (sid) {
        return E.CARDS.some(function (c) { return c.id === sid && c.kind === 'shock'; });
      });
      if (card.kind === 'shock' && haveShock) return;      // shock types cannot combine
      if (S.selectedCards.length >= 3) return;
      S.selectedCards.push(id);
    }
    refreshCards();
  }

  function refreshCards() {
    var haveShock = S.selectedCards.some(function (sid) {
      return E.CARDS.some(function (c) { return c.id === sid && c.kind === 'shock'; });
    });
    var full = S.selectedCards.length >= 3;
    E.CARDS.forEach(function (c) {
      var el = $('card-' + c.id);
      if (!el) return;
      var sel = S.selectedCards.indexOf(c.id) >= 0;
      var blocked = !sel && (full || (c.kind === 'shock' && haveShock));
      el.classList.toggle('selected', sel);
      el.classList.toggle('blocked', blocked);
      el.setAttribute('aria-pressed', sel ? 'true' : 'false');
      el.disabled = blocked;

      var status = $('card-status-' + c.id);
      var reason = '';
      if (sel) {
        status.textContent = 'Selected. Press to remove this card.';
      } else if (full) {
        reason = 'Three policy cards are already selected.';
        status.textContent = 'Unavailable. ' + reason;
      } else if (c.kind === 'shock' && haveShock) {
        reason = 'Another shock card is already selected.';
        status.textContent = 'Unavailable. ' + reason;
      } else {
        status.textContent = 'Available. Press to add this card.';
      }
      el.title = reason;
    });
    var n = S.selectedCards.length;
    var btn = $('runBtn');
    btn.disabled = n === 0 || S.runInFlight;
    $('runHint').textContent = S.runInFlight ? 'Simulation in progress…'
      : n === 0 ? 'Select at least one card'
      : n + ' card' + (n > 1 ? 's' : '') + ' in hand — ready to simulate';
  }

  /* ---------------- run flow: POST → poll → time-lapse ---------------- */
  function startRun() {
    if (S.runInFlight || !S.selectedCards.length) return;
    var payload = E.buildRunPayload(S.selectedCards, S.knobs, 'AUSTRIA2026Q1');
    var names = E.CARDS.filter(function (c) { return S.selectedCards.indexOf(c.id) >= 0; })
                       .map(function (c) { return c.name; });
    S.runInFlight = true;
    refreshCards();
    $('progressOverlay').classList.remove('hidden');
    $('progressFill').style.width = '2%';
    $('progressMsg').textContent = 'submitting run…';

    E.fetchJSON('/api/runs', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    }).then(function (res) {
      pollRun(res.run_id, names, payload);
    }).catch(function (e) {
      runFailed('Could not start the simulation: ' + e.message);
    });
  }

  function pollRun(runId, names, payload) {
    var fails = 0;
    S.pollTimer = setInterval(function () {
      E.fetchJSON('/api/runs/' + runId + '/status').then(function (st) {
        fails = 0;
        var pct = Math.max(2, Math.round((st.progress || 0) * 100));
        $('progressFill').style.width = pct + '%';
        $('progressMsg').textContent = (st.state || '') + ' · ' + pct + '%' + (st.message ? ' — ' + st.message : '');
        if (st.state === 'done') {
          clearInterval(S.pollTimer);
          E.fetchJSON('/api/runs/' + runId + '/summary').then(function (sum) {
            var tl = E.buildTimeline(sum);
            tl.cardNames = names;
            tl.overridesApplied = payload.overrides || null;
            tl.shockApplied = payload.shock && payload.shock.type !== 'none' ? payload.shock : null;
            S.runInFlight = false;
            S.selectedCards = [];
            refreshCards();
            $('progressOverlay').classList.add('hidden');
            setTimeline(tl, 'card');          // auto-play the time-lapse
            updatePlayBtn();
          }).catch(function (e) { runFailed('Run finished but summary failed: ' + e.message); });
        } else if (st.state === 'error') {
          clearInterval(S.pollTimer);
          runFailed('Simulation error: ' + (st.message || 'unknown'));
        }
      }).catch(function () {
        if (++fails > 6) {
          clearInterval(S.pollTimer);
          runFailed('Lost contact with the backend while polling.');
        }
      });
    }, 1500);
  }

  function runFailed(msg) {
    S.runInFlight = false;
    refreshCards();
    $('progressOverlay').classList.add('hidden');
    showError(msg, false);
  }

  /* ---------------- end screen ---------------- */
  function showEndScreen() {
    var tl = S.tl, gh = S.baseTl;
    var T = tl.T;
    var rows = [];
    function row(label, a, b, diff, badge) {
      rows.push('<div class="score-row"><div class="score-label">' + label + (badge ? ' <span class="badge">derived</span>' : '') + '</div>' +
        '<div class="score-run">' + a + '</div><div class="score-base">' + b + '</div>' +
        '<div class="score-diff">' + diff + '</div></div>');
    }
    rows.push('<div class="score-row score-head"><div class="score-label"></div><div class="score-run">YOUR RUN</div><div class="score-base">BASELINE</div><div class="score-diff">Δ</div></div>');

    if (gh) {
      var Tc = Math.min(T, gh.T);
      var g1 = tl.gdp[Tc], g0 = gh.gdp[Tc];
      var dg = E.safeDiv(g1, g0, 1) - 1;
      row('Final real GDP /qtr', E.fmtBn(g1), E.fmtBn(g0),
          '<span class="' + (dg >= 0 ? 'good' : 'bad') + '">' + E.fmtSignedPct(dg) + '</span>');
      var iaR = Math.pow(E.safeDiv(tl.defl[Tc], tl.defl[0], 1), 4 / Math.max(1, Tc)) - 1;
      var iaB = Math.pow(E.safeDiv(gh.defl[Tc], gh.defl[0], 1), 4 / Math.max(1, Tc)) - 1;
      var di = iaR - iaB;
      row('Avg inflation /yr', E.fmtPct(iaR), E.fmtPct(iaB),
          '<span class="' + (di <= 0 ? 'good' : 'bad') + '">' + (di >= 0 ? '+' : '') + (di * 100).toFixed(2) + 'pp</span>', true);
      var rR = tl.rateA[Tc] * 100, rB = gh.rateA[Tc] * 100, drr = rR - rB;
      row('Final policy rate', rR.toFixed(2) + '%', rB.toFixed(2) + '%',
          (drr >= 0 ? '+' : '') + drr.toFixed(2) + 'pp');
      var wR = tl.realWageIdx[Tc], wB = gh.realWageIdx[Tc], dw = E.safeDiv(wR, wB, 1) - 1;
      row('Real wage bill (employment proxy)', wR.toFixed(3), wB.toFixed(3),
          '<span class="' + (dw >= 0 ? 'good' : 'bad') + '">' + E.fmtSignedPct(dw) + '</span>', true);
      $('verdict').textContent = verdict(dg, di);
    } else {
      row('Final real GDP /qtr', E.fmtBn(tl.gdp[T]), '—', '');
      $('verdict').textContent = 'No baseline ghost available for comparison.';
    }
    $('scoreTable').innerHTML = rows.join('');
    $('endCards').innerHTML = (tl.cardNames || []).map(function (n) {
      return '<span class="end-card-chip">' + n + '</span>';
    }).join('');
    $('endOverlay').classList.remove('hidden');
  }

  function verdict(dGdp, dInfl) {
    if (dGdp > 0.01 && dInfl < 0.005) return 'Boom without the bill — the council votes you Mayor for Life.';
    if (dGdp > 0.01) return 'The city roars… and so do the prices. Growth bought on credit at the bakery.';
    if (dGdp < -0.01 && dInfl < 0) return 'A colder, cheaper city. The accountants cheer quietly; the pigeons approve.';
    if (dGdp < -0.01) return 'Recession. Torches and pitchforks are forming an orderly queue at the Capitol.';
    if (dInfl < -0.003) return 'GDP shrugged, but inflation cooled — the central banker buys you a coffee.';
    if (dInfl > 0.003) return 'Little growth, hotter prices. The economics faculty would like a word.';
    return 'Econopolis shrugs. History will barely footnote this administration.';
  }

  /* ---------------- tooltips ---------------- */
  function onMove(ev) {
    var rect = canvas.getBoundingClientRect();
    var mx = ev.clientX - rect.left, my = ev.clientY - rect.top;
    S.mouse = [mx, my];
    if (!S.city || !S.view) return;
    var gpt = C.unproject(S.view, mx, my);
    var plot = C.hitTest(S.city, gpt[0], gpt[1]);
    S.hoverId = plot ? plot.id : null;
    if (plot) {
      tooltip.innerHTML = tooltipHTML(plot);
      tooltip.classList.remove('hidden');
      var tx = Math.min(mx + 18, rect.width - 290), ty = Math.max(10, my - 14);
      tooltip.style.left = tx + 'px';
      tooltip.style.top = ty + 'px';
    } else {
      tooltip.classList.add('hidden');
    }
  }

  function tooltipHTML(plot) {
    var tl = S.tl, q = tl ? Math.floor(S.qTime) : 0;
    var h = '<div class="tt-title" style="color:' + plot.color + '">' + plot.name + '</div>';
    if (!tl) return h + '<div class="tt-row">waiting for run data…</div>';
    var flows = E.derivedFlows(tl, q, Object.assign({}, S.knobs || E.FALLBACK_KNOBS));

    if (plot.kind === 'district') {
      var g = plot.g;
      var idx = tl.groupIdx[q][g];
      var qoq = q >= 1 ? E.safeDiv(tl.groupIdx[q][g], tl.groupIdx[q - 1][g], 1) - 1 : 0;
      h += '<div class="tt-row"><span>Firms</span><b>' + S.city.firmsByGroup[g] + '</b></div>';
      h += '<div class="tt-row"><span>Workers (t=0)</span><b>' + S.city.workersByGroup[g] + '</b></div>';
      h += '<div class="tt-row"><span>Real GVA /qtr</span><b>' + E.fmtBn(tl.groupGva[q][g]) + '</b></div>';
      h += '<div class="tt-row"><span>GVA index vs start</span><b>' + idx.toFixed(3) +
           ' <i class="' + (qoq >= 0 ? 'good' : 'bad') + '">' + E.fmtSignedPct(qoq) + ' q/q</i></b></div>';
      h += '<div class="tt-sub">Top member sectors</div>';
      E.topSectors(tl, g, q, S.sectorMeta, 3).forEach(function (s) {
        var lbl = s.label.length > 40 ? s.label.slice(0, 38) + '…' : s.label;
        h += '<div class="tt-row tt-small"><span>' + s.code + ' ' + lbl + '</span><b>' + (s.share * 100).toFixed(0) + '%</b></div>';
      });
    } else if (plot.kind === 'capitol') {
      h += '<div class="tt-sub">Government, this quarter <span class="badge">derived</span></div>';
      h += '<div class="tt-row"><span>VAT intake</span><b>' + E.fmtBn(flows.vat) + '</b></div>';
      h += '<div class="tt-row"><span>Income tax</span><b>' + E.fmtBn(flows.incomeTax) + '</b></div>';
      h += '<div class="tt-row"><span>Social insurance</span><b>' + E.fmtBn(flows.socialIns) + '</b></div>';
      h += '<div class="tt-row"><span>Corporate tax (rough)</span><b>' + E.fmtBn(flows.corpTax) + '</b></div>';
      h += '<div class="tt-row"><span>Benefits paid out</span><b>' + E.fmtBn(flows.benefits) + '</b></div>';
      h += '<div class="tt-row"><span>Gov purchases</span><b>' + E.fmtBn(flows.G) + '</b></div>';
      h += '<div class="tt-note">Estimated from aggregates via the contract flow recipes.</div>';
    } else if (plot.kind === 'cbank') {
      h += '<div class="tt-row"><span>Policy rate (annual)</span><b>' + E.fmtPct(tl.rateA[q], 2) + '</b></div>';
      h += '<div class="tt-row"><span>Inflation (yoy)</span><b>' + E.fmtPct(tl.inflYoY[q], 1) + '</b></div>';
      h += '<div class="tt-row"><span>Target (pi_star, /yr)</span><b>~2.0%</b></div>';
      h += '<div class="tt-note">Sets the rate each quarter by a Taylor rule (phase 3 of 15), smoothing rho = 0.94.</div>';
    } else if (plot.kind === 'bank') {
      h += '<div class="tt-row"><span>Loan rate backdrop</span><b>policy + mu</b></div>';
      h += '<div class="tt-row"><span>Capital requirement</span><b>zeta = 3%</b></div>';
      h += '<div class="tt-row"><span>Mortgage LTV cap</span><b>60%</b></div>';
      h += '<div class="tt-note">One commercial bank funds all 652 firms via search &amp; matching (phase 7).</div>';
    } else if (plot.kind === 'harbor') {
      h += '<div class="tt-row"><span>Exports /qtr</span><b>' + E.fmtBn(tl.exp[q]) + '</b></div>';
      h += '<div class="tt-row"><span>Imports /qtr</span><b>' + E.fmtBn(tl.imp[q]) + '</b></div>';
      var tb = tl.tradeBal[q];
      h += '<div class="tt-row"><span>Balance</span><b class="' + (tb >= 0 ? 'good' : 'bad') + '">' + E.fmtSignedBn(tb) + '</b></div>';
      h += '<div class="tt-note">Ship traffic tracks exports + imports volume. Trade clears against one rest-of-world agent.</div>';
    } else if (plot.kind === 'resid') {
      var hh = E.HOUSEHOLDS;
      h += '<div class="tt-row"><span>Households</span><b>' + hh.total.toLocaleString() + '</b></div>';
      h += '<div class="tt-row"><span>Active / inactive</span><b>' + hh.active.toLocaleString() + ' / ' + hh.inactive.toLocaleString() + '</b></div>';
      h += '<div class="tt-row"><span>Employment proxy <span class="badge">derived</span></span><b>' + E.sample(tl.realWageIdx, S.qTime).toFixed(3) + '</b></div>';
      h += '<div class="tt-row"><span>Wage bill /qtr</span><b>' + E.fmtBn(tl.wages[q]) + '</b></div>';
      h += '<div class="tt-note">Lit windows track the real wage bill (wages / deflator, normalized).</div>';
    }
    return h;
  }

  /* ---------------- UI bindings ---------------- */
  function bindUI() {
    canvas.addEventListener('mousemove', onMove);
    canvas.addEventListener('mouseleave', function () { S.hoverId = null; tooltip.classList.add('hidden'); });

    $('playBtn').onclick = function () {
      if (!S.tl) return;
      if (!S.playing && S.qTime >= S.tl.T) S.qTime = 0;   // replay from start
      S.playing = !S.playing;
      updatePlayBtn();
    };
    $('speedBtn').onclick = function () {
      S.speedIdx = (S.speedIdx + 1) % S.speeds.length;
      $('speedBtn').textContent = ['½×', '1×', '2×'][S.speedIdx];
    };
    $('scrub').addEventListener('input', function () {
      if (!S.tl) return;
      S.qTime = (+this.value) / 1000 * S.tl.T;
      S.playing = false;
      updatePlayBtn();
      // rebuild feed to match the scrubbed position
      S.feed = [];
      var from = Math.max(1, Math.floor(S.qTime) - 4);
      for (var q = from; q <= Math.floor(S.qTime); q++) (S.tl.headlines[q] || []).forEach(pushFeedItem);
      if (!S.feed.length) pushFeedItem({ period: S.tl.periods[0], text: 'quiet quarter in Econopolis', cls: 'flat' });
    });

    $('runBtn').onclick = startRun;
    $('hideProgressBtn').onclick = function () { $('progressOverlay').classList.add('hidden'); };

    $('replayBtn').onclick = function () {
      $('endOverlay').classList.add('hidden');
      S.qTime = 0; S.playing = true; S.endShown = false;   // scoreboard returns at the end
      updatePlayBtn();
    };
    $('backBtn').onclick = function () {
      $('endOverlay').classList.add('hidden');
      if (S.baseTl) setTimeline(S.baseTl, 'baseline');
      updatePlayBtn();
    };
    $('closeEndBtn').onclick = function () { $('endOverlay').classList.add('hidden'); };

    window.addEventListener('keydown', function (ev) {
      if (ev.target && /INPUT|TEXTAREA|BUTTON/.test(ev.target.tagName)) return;
      if (ev.code === 'Space') { ev.preventDefault(); $('playBtn').onclick(); }
      if (ev.code === 'ArrowRight' && S.tl) { S.qTime = Math.min(S.tl.T, Math.floor(S.qTime) + 1); S.playing = false; updatePlayBtn(); }
      if (ev.code === 'ArrowLeft' && S.tl) { S.qTime = Math.max(0, Math.ceil(S.qTime) - 1); S.playing = false; updatePlayBtn(); }
    });
  }

  boot();
})();
