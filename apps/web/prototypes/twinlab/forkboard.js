/* ── forkboard.js — the Δ board: fork Universe A into a treated Universe B ──
 * Shows every knob from /api/knobs as a compact chip. Clicking a chip opens
 * a popover slider seeded at A's effective value (A's recorded override if
 * this page created run A, otherwise the dataset default — past runs don't
 * expose their overrides through the API). Changed chips go amber with a
 * human-readable delta. Plus a shock picker and the RUN UNIVERSE B flow.
 */
(function () {
  'use strict';

  // knobs whose natural display is a percentage (rates / shares)
  var PCT_KEYS = /^(tau_|psi|theta|zeta|rho|mu$|r_star|pi_star|r_G|r_bar|omega)/;
  // short chip names (economics-flavoured, fits a chip)
  var SHORT = {
    tau_INC: 'INC TAX', tau_FIRM: 'CORP TAX', tau_VAT: 'VAT', tau_SIF: 'SIF (EMPLOYER)',
    tau_SIW: 'SIW (WORKER)', tau_EXPORT: 'EXPORT TAX', tau_CF: 'CAPFORM TAX', tau_G: 'GOV-BUY TAX',
    psi: 'ψ CONSUME', psi_H: 'ψH HOUSING', theta_UB: 'UB REPLACE', theta_DIV: 'DIVIDENDS',
    mu: 'BANK RISK μ', zeta: 'CAP REQ ζ', zeta_LTV: 'LTV CAP', zeta_b: 'RESTART ζb',
    theta: 'LOAN REPAY θ', rho: 'CB SMOOTH ρ', r_star: 'r★ NEUTRAL', pi_star: 'π★ TARGET',
    xi_pi: 'ξπ TAYLOR-π', xi_gamma: 'ξγ TAYLOR-g', r_G: 'GOV SPREAD',
    r_bar: 'POLICY r̄₀', sb_other: 'BENEFITS OTH', sb_inact: 'BENEFITS INACT',
    w_UB: 'UB WAGE', omega: 'CAPACITY ω₀'
  };

  function isPct(key) { return PCT_KEYS.test(key); }
  function fmtVal(key, v) {
    if (v == null || !isFinite(v)) return '—';
    if (isPct(key)) {
      var p = v * 100;
      return (Math.abs(p) < 1 ? p.toFixed(2) : p.toFixed(1)) + '%';
    }
    return Math.abs(v) >= 10 ? v.toFixed(1) : v.toFixed(2);
  }
  function humanName(knob) {
    // "VAT (tau_VAT)" → "VAT"
    return knob.label.replace(/\s*\([^)]*\)\s*$/, '');
  }
  function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

  var state = {
    knobs: [],            // /api/knobs rows for A's dataset
    seed: {},             // key → A's effective value (clamped into [min,max])
    overrides: {},        // key → user-chosen value (only keys the user touched)
    shockType: 'none',
    shockParams: { annual_rate: 0.02, multiplier: 1.05, cmult: 1.10, final_time: 4 },
    T: 12,
    onRun: null,          // fn(body) — app wires this to the POST flow
    openKey: null
  };

  var els = {};

  function setup() {
    els.board = document.getElementById('forkboard');
    els.chips = document.getElementById('fb-chips');
    els.basis = document.getElementById('fb-basis');
    els.guard = document.getElementById('fb-guard');
    els.summary = document.getElementById('fb-summary');
    els.runBtn = document.getElementById('btn-run');
    els.pop = document.getElementById('popover');
    els.shockSeg = document.getElementById('shock-seg');
    els.shockParams = document.getElementById('shock-params');

    els.shockSeg.addEventListener('click', function (ev) {
      var b = ev.target.closest('.seg-btn');
      if (!b) return;
      state.shockType = b.dataset.shock;
      els.shockSeg.querySelectorAll('.seg-btn').forEach(function (x) { x.classList.toggle('on', x === b); });
      renderShockParams();
      refresh();
    });

    els.runBtn.addEventListener('click', function () {
      if (els.runBtn.disabled) return;
      if (state.onRun) state.onRun(buildPayload());
    });

    document.addEventListener('mousedown', function (ev) {
      if (state.openKey && !els.pop.contains(ev.target) && !ev.target.closest('.chip')) closePopover();
    });
    renderShockParams();
  }

  /* open the board for a given fork basis */
  function open(knobs, seedOverrides, T, basisText) {
    state.knobs = knobs;
    state.T = T;
    state.overrides = {};
    state.seed = {};
    knobs.forEach(function (k) {
      var eff = (seedOverrides && seedOverrides[k.key] != null) ? seedOverrides[k.key] : k.default;
      // theta_DIV default > max and mu default < min in the live data —
      // keep the raw effective value as seed; slider clamps only when moved.
      state.seed[k.key] = eff;
    });
    els.basis.textContent = basisText || '';
    els.board.classList.remove('hidden');
    renderChips();
    refresh();
  }
  function close() { closePopover(); els.board.classList.add('hidden'); }
  function isOpen() { return !els.board.classList.contains('hidden'); }

  function effective(key) {
    return (key in state.overrides) ? state.overrides[key] : state.seed[key];
  }
  function changedKeys() {
    return Object.keys(state.overrides).filter(function (k) {
      return Math.abs(state.overrides[k] - state.seed[k]) > 1e-12;
    });
  }

  function renderChips() {
    els.chips.innerHTML = '';
    state.knobs.forEach(function (k) {
      var chip = document.createElement('button');
      chip.className = 'chip';
      chip.dataset.key = k.key;
      chip.title = humanName(k) + ' — range ' + fmtVal(k.key, k.min) + ' … ' + fmtVal(k.key, k.max);
      chip.addEventListener('click', function () { openPopover(k, chip); });
      els.chips.appendChild(chip);
    });
    paintChips();
  }

  function paintChips() {
    var changed = changedKeys();
    els.chips.querySelectorAll('.chip').forEach(function (chip) {
      var key = chip.dataset.key;
      var k = state.knobs.find(function (x) { return x.key === key; });
      var isChanged = changed.indexOf(key) !== -1;
      chip.classList.toggle('changed', isChanged);
      if (isChanged) {
        chip.innerHTML = (SHORT[key] || key) + ' <span class="cv">' +
          fmtVal(key, state.seed[key]) + ' → ' + fmtVal(key, state.overrides[key]) + '</span>';
      } else {
        chip.innerHTML = (SHORT[key] || key) + ' <span class="cv">' + fmtVal(key, effective(key)) + '</span>';
      }
    });
  }

  function openPopover(knob, chip) {
    state.openKey = knob.key;
    var seedClamped = clamp(effective(knob.key), knob.min, knob.max);
    var step = (knob.max - knob.min) / 400;
    els.pop.innerHTML =
      '<div class="pop-name">' + humanName(knob) + ' <span style="color:var(--faint);font-family:var(--mono);font-size:9px">' + knob.key + '</span></div>' +
      '<div class="pop-range">range ' + fmtVal(knob.key, knob.min) + ' … ' + fmtVal(knob.key, knob.max) +
      ' · A = ' + fmtVal(knob.key, state.seed[knob.key]) + '</div>' +
      '<div class="pop-row"><input type="range" min="' + knob.min + '" max="' + knob.max + '" step="' + step + '" value="' + seedClamped + '">' +
      '<span class="pop-val">' + fmtVal(knob.key, seedClamped) + '</span></div>' +
      '<div class="pop-delta"></div>' +
      '<div class="pop-foot"><button data-act="reset">RESET TO A</button><button data-act="close">CLOSE</button></div>';
    els.pop.classList.remove('hidden');

    // position under the chip, clamped to viewport
    var r = chip.getBoundingClientRect();
    var x = clamp(r.left, 8, window.innerWidth - 292);
    var y = r.bottom + 6;
    if (y + 150 > window.innerHeight) y = r.top - 150;
    els.pop.style.left = x + 'px';
    els.pop.style.top = y + 'px';

    var slider = els.pop.querySelector('input[type=range]');
    var valEl = els.pop.querySelector('.pop-val');
    var deltaEl = els.pop.querySelector('.pop-delta');

    function paintDelta() {
      var ck = changedKeys();
      if (ck.indexOf(knob.key) !== -1) {
        deltaEl.textContent = humanName(knob) + ' ' + fmtVal(knob.key, state.seed[knob.key]) +
          ' → ' + fmtVal(knob.key, state.overrides[knob.key]);
      } else deltaEl.textContent = '';
    }
    slider.addEventListener('input', function () {
      var v = parseFloat(slider.value);
      state.overrides[knob.key] = v;
      valEl.textContent = fmtVal(knob.key, v);
      paintChips(); paintDelta(); refresh();
    });
    els.pop.querySelector('[data-act=reset]').addEventListener('click', function () {
      delete state.overrides[knob.key];
      slider.value = seedClamped;
      valEl.textContent = fmtVal(knob.key, seedClamped);
      paintChips(); paintDelta(); refresh();
    });
    els.pop.querySelector('[data-act=close]').addEventListener('click', closePopover);
    paintDelta();
  }
  function closePopover() { state.openKey = null; els.pop.classList.add('hidden'); }

  function renderShockParams() {
    var p = state.shockParams, h = '';
    if (state.shockType === 'interest_rate') {
      h = '<label>annual rate +<input id="shk-rate" type="number" step="0.005" value="' + p.annual_rate + '"></label>' +
          '<label>through Q<input id="shk-ft" type="number" min="1" max="' + state.T + '" step="1" value="' + p.final_time + '"></label>';
    } else if (state.shockType === 'consumption') {
      h = '<label>multiplier ×<input id="shk-cmult" type="number" step="0.01" value="' + p.cmult + '"></label>' +
          '<label>through Q<input id="shk-ft" type="number" min="1" max="' + state.T + '" step="1" value="' + p.final_time + '"></label>';
    } else if (state.shockType === 'productivity') {
      h = '<label>multiplier ×<input id="shk-mult" type="number" step="0.01" value="' + p.multiplier + '"></label>';
    }
    els.shockParams.innerHTML = h;
    els.shockParams.querySelectorAll('input').forEach(function (inp) {
      inp.addEventListener('input', function () {
        var v = parseFloat(inp.value);
        if (!isFinite(v)) return;
        if (inp.id === 'shk-rate') p.annual_rate = v;
        if (inp.id === 'shk-cmult') p.cmult = v;
        if (inp.id === 'shk-mult') p.multiplier = v;
        if (inp.id === 'shk-ft') p.final_time = Math.max(1, Math.round(v));
        refresh();
      });
    });
  }

  /* client-side guard: households cannot budget more than 100% of income */
  function guardViolation() {
    var psi = effective('psi'), psiH = effective('psi_H');
    if (psi != null && psiH != null && psi + psiH > 1) {
      return 'ψ + ψ_H = ' + ((psi + psiH) * 100).toFixed(1) + '% > 100% — households cannot spend more than their income; lower one of them';
    }
    return null;
  }

  function refresh() {
    if (!isOpen()) return;
    var viol = guardViolation();
    els.guard.classList.toggle('hidden', !viol);
    if (viol) els.guard.textContent = viol;
    els.runBtn.disabled = !!viol;

    var ck = changedKeys();
    var bits = [];
    if (ck.length) bits.push(ck.length + ' knob' + (ck.length > 1 ? 's' : '') + ' changed');
    if (state.shockType !== 'none') bits.push(state.shockType.replace('_', ' ') + ' shock');
    els.summary.textContent = bits.length
      ? bits.join(' + ') + ' · T=' + state.T + ' · n_sims=4'
      : 'no changes — B would replay A’s physics with a fresh seed · T=' + state.T + ' · n_sims=4';
  }

  /* Build the POST /api/runs body fragment (overrides in UI units,
   * CHANGED KEYS ONLY, per contract). The dataset/scenario/sim envelope
   * is added by the app which knows Universe A. */
  function buildPayload() {
    var params = {}, inits = {};
    changedKeys().forEach(function (key) {
      var knob = state.knobs.find(function (k) { return k.key === key; });
      if (!knob) return;
      var v = clamp(state.overrides[key], knob.min, knob.max); // never 400 on range
      if (knob.group === 'initial_conditions') inits[key] = v; else params[key] = v;
    });
    // ALSO carry forward A's own overrides (when known) so a fork of a
    // forked run keeps its parentage — but only keys the user did NOT re-touch.
    state.knobs.forEach(function (k) {
      var seeded = state.seed[k.key];
      if (seeded == null || k.default == null) return;
      if (k.key in state.overrides) return;
      if (Math.abs(seeded - k.default) > 1e-12) {
        // seed differs from dataset default → it was an override on A
        if (k.group === 'initial_conditions') inits[k.key] = seeded; else params[k.key] = seeded;
      }
    });

    var overrides = {};
    if (Object.keys(params).length) overrides.parameters = params;
    if (Object.keys(inits).length) overrides.initial_conditions = inits;

    var p = state.shockParams, shock = { type: 'none' };
    if (state.shockType === 'interest_rate') shock = { type: 'interest_rate', annual_rate: p.annual_rate, final_time: Math.min(p.final_time, state.T) };
    else if (state.shockType === 'consumption') shock = { type: 'consumption', multiplier: p.cmult, final_time: Math.min(p.final_time, state.T) };
    else if (state.shockType === 'productivity') shock = { type: 'productivity', multiplier: p.multiplier };

    return { overrides: overrides, shock: shock, changedCount: changedKeys().length };
  }

  window.ForkBoard = {
    setup: setup, open: open, close: close, isOpen: isOpen,
    set onRun(fn) { state.onRun = fn; },
    setT: function (T) { state.T = T; refresh(); }
  };
})();
