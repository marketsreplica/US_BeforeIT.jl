/* util.js — shared helpers: fetch, formatting, error banner */
"use strict";

/** Fetch JSON with error propagation. All /api calls are absolute paths. */
async function getJSON(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url} → HTTP ${r.status}`);
  return r.json();
}

async function postJSON(url, body) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    let msg = `HTTP ${r.status}`;
    try { msg += " — " + (await r.text()).slice(0, 200); } catch (_) {}
    throw new Error(`${url} → ${msg}`);
  }
  return r.json();
}

/* ---- error banner ---- */
const ERR_EL = () => document.getElementById("error-banner");
function showError(msg) {
  const el = ERR_EL();
  el.textContent = "⚠ " + msg;
  el.hidden = false;
}
function hideError() { ERR_EL().hidden = true; }

/* ---- number formatting ----
   Model money units ≈ millions of € per quarter (real_gdp ≈ 130,000 → €130bn/q). */
function fmtMoney(v) {
  if (!Number.isFinite(v)) return "—";
  const sign = v < 0 ? "−" : "";
  const a = Math.abs(v);
  if (a >= 100000) return sign + (a / 1000).toFixed(0) + " bn€";
  if (a >= 1000) return sign + (a / 1000).toFixed(1) + " bn€";
  return sign + a.toFixed(0) + " m€";
}

function fmtPct(v, dp = 2) {
  if (!Number.isFinite(v)) return "—";
  return (v * 100).toFixed(dp) + "%";
}

/** Knob value readout: precision adapts to magnitude. */
function fmtKnob(v) {
  if (!Number.isFinite(v)) return "—";
  const a = Math.abs(v);
  if (a >= 10) return v.toFixed(2);
  if (a >= 1) return v.toFixed(3);
  return v.toFixed(4);
}

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

/** Safe array read: returns NaN instead of throwing / undefined. */
function at(arr, i) {
  if (!arr || i < 0 || i >= arr.length) return NaN;
  const v = arr[i];
  return (v === null || v === undefined) ? NaN : v;
}
