"use strict";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

const canvas = $("#ledger-canvas");
const ctx = canvas.getContext("2d");
const els = {
  shell: $(".canvas-shell"),
  brandSigil: $(".brand-sigil"),
  run: $("#run-select"),
  badge: $("#accounting-badge"),
  loading: $("#loading"),
  empty: $("#empty-state"),
  tooltip: $("#tooltip"),
  inspector: $("#inspector"),
  inspectKicker: $("#inspect-kicker"),
  inspectTitle: $("#inspect-title"),
  inspectSubtitle: $("#inspect-subtitle"),
  inspectMetrics: $("#inspect-metrics"),
  inspectCopy: $("#inspect-copy"),
  inspectFocus: $("#inspect-focus"),
  filters: $("#flow-filters"),
  range: $("#quarter-range"),
  period: $("#period-label"),
  quarterCount: $("#quarter-count"),
  realization: $("#realization-label"),
  units: $("#units-label"),
  play: $("#play"),
  zoom: $("#zoom-label"),
  firmQuery: $("#firm-query"),
  firmOptions: $("#firm-options"),
  table: $("#flow-table"),
  tableCaption: $("#table-caption"),
  live: $("#live-status"),
  datasetLabel: $("#dataset-label"),
  querySummary: $("#query-summary"),
  coverageNote: $("#coverage-note"),
  scaleNote: $("#scale-note"),
  showAllFirms: $("#show-all-firms"),
};

const CATEGORY_COLORS = {
  goods: "#85e0b4",
  business: "#69c8d7",
  external: "#80b8f4",
  income: "#f3c66f",
  fiscal: "#ee9a72",
  credit: "#c395ef",
  interest: "#e593be",
  deposits: "#a9b7c2",
  capacity: "#f3c66f",
  stocks: "#7aa9e8",
};

const CATEGORY_LABELS = {
  goods: "Goods",
  business: "Firm trade",
  external: "World trade",
  income: "Income",
  fiscal: "Taxes & benefits",
  credit: "Credit",
  interest: "Interest",
  deposits: "Deposits",
  capacity: "Potential supply response",
  stocks: "Financial stocks",
};

const NODE_STYLES = {
  households: ["#17312b", "#85e0b4"],
  household_cohort: ["#17312b", "#85e0b4"],
  production: ["#173126", "#91d98b"],
  market: ["#2d2818", "#f3c66f"],
  government: ["#2d2018", "#ee9a72"],
  bank: ["#211d37", "#c395ef"],
  central_bank: ["#172839", "#80b8f4"],
  sector: ["#142a25", "#69c8d7"],
  firm: ["#12231f", "#85e0b4"],
  outside_portal: ["#122338", "#80b8f4"],
};

const state = {
  runs: [],
  manifest: null,
  data: null,
  runId: null,
  quarter: 1,
  mode: "macro",
  layoutVariant: 0,
  nodes: [],
  nodeMap: new Map(),
  flows: [],
  positions: new Map(),
  egoSlots: new Map(),
  sectorMetadata: new Map(),
  firmCatalog: new Map(),
  activeCategories: new Set(Object.keys(CATEGORY_COLORS)),
  selected: null,
  hovered: null,
  hoverPoint: null,
  firmFocus: null,
  playing: false,
  playTimer: null,
  runRevision: 0,
  dataRevision: 0,
  runController: null,
  quarterController: null,
  cameraIntent: null,
  frameRequest: null,
  fontFamily: getComputedStyle(document.body).fontFamily,
  currencySymbol: "€",
  drag: null,
  view: { x: 0, y: 0, scale: 1 },
  cameraMode: "manual",
  size: { width: 1, height: 1, dpr: 1 },
};

function finite(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function formatMoney(value) {
  const amount = finite(value);
  const absolute = Math.abs(amount);
  const symbol = state.currencySymbol || "¤";
  if (absolute >= 1e6) return `${symbol}${(amount / 1e6).toFixed(2)}tn`;
  if (absolute >= 1e3) return `${symbol}${(amount / 1e3).toFixed(2)}bn`;
  if (absolute >= 10) return `${symbol}${amount.toFixed(1)}m`;
  return `${symbol}${amount.toFixed(2)}m`;
}

function humanize(value) {
  return String(value || "exact model record")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

async function fetchJSON(url, { signal } = {}) {
  const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
  return body;
}

function showLoading(message) {
  els.loading.textContent = message;
  els.loading.hidden = false;
  els.shell.setAttribute("aria-busy", "true");
}

function hideLoading() {
  els.loading.hidden = true;
  els.shell.setAttribute("aria-busy", "false");
}

function showEmpty(message) {
  els.empty.hidden = false;
  if (message) els.empty.querySelector("p").textContent = message;
  hideLoading();
  state.data = null;
  state.nodes = [];
  state.nodeMap = new Map();
  state.flows = [];
  els.querySummary.textContent = "No exact transaction trace is available";
  els.coverageNote.textContent = "";
  els.scaleNote.textContent = "";
  els.table.replaceChildren();
  els.live.textContent = els.querySummary.textContent;
  draw();
}

function setError(message) {
  showEmpty(`${message} Run a new simulation to collect exact quarterly cash transactions.`);
  els.badge.className = "status-badge fail";
  els.badge.textContent = "Ledger unavailable";
}

async function loadRuns() {
  showLoading("Looking for transaction-capable runs…");
  els.empty.hidden = true;
  try {
    const allRuns = await fetchJSON("/api/runs");
    state.runs = allRuns.filter((run) => run.state === "done" && run.cashflows_available);
    els.run.replaceChildren();
    if (!state.runs.length) {
      showEmpty();
      els.run.disabled = true;
      els.run.add(new Option("No traced runs", ""));
      return;
    }
    els.run.disabled = false;
    state.runs.forEach((run) => {
      const date = run.created_at ? new Date(run.created_at).toLocaleDateString(undefined, { month: "short", day: "numeric" }) : "saved";
      const label = `${run.dataset_id} · ${run.scenario} · ${run.cashflow_quarters}Q · ${date}`;
      els.run.add(new Option(label, run.run_id));
    });
    els.run.value = state.runs[0].run_id;
    await dispatch({ type: "SELECT_RUN", runId: state.runs[0].run_id });
  } catch (error) {
    setError(error.message);
  }
}

function isAbort(error) {
  return error?.name === "AbortError";
}

function queueCameraIntent(type = "fit-scene") {
  state.cameraIntent = { type, runRevision: state.runRevision, dataRevision: state.dataRevision };
}

function cancelCameraIntent() {
  state.cameraIntent = null;
}

function abortQuarterRequest() {
  state.quarterController?.abort();
  state.quarterController = null;
}

function reduce(action) {
  switch (action.type) {
    case "SELECT_RUN":
      if (!action.runId) return null;
      stopPlayback();
      state.runController?.abort();
      abortQuarterRequest();
      state.runRevision += 1;
      state.dataRevision += 1;
      state.runId = action.runId;
      state.manifest = null;
      state.data = null;
      state.quarter = 1;
      state.firmFocus = null;
      state.selected = null;
      state.hovered = null;
      state.nodes = [];
      state.nodeMap = new Map();
      state.flows = [];
      state.positions.clear();
      state.egoSlots.clear();
      state.sectorMetadata = new Map();
      state.firmCatalog = new Map();
      queueCameraIntent();
      return () => loadRun(action.runId, state.runRevision);
    case "SET_MODE":
      if (!["macro", "sector", "firm"].includes(action.mode) || action.mode === state.mode && !state.firmFocus) return null;
      stopPlayback();
      abortQuarterRequest();
      state.mode = action.mode;
      state.firmFocus = null;
      state.selected = null;
      state.dataRevision += 1;
      queueCameraIntent();
      return () => loadQuarter();
    case "SET_QUARTER":
      if (!Number.isInteger(action.quarter) || action.quarter === state.quarter) return null;
      if (action.source !== "playback") stopPlayback();
      abortQuarterRequest();
      state.quarter = action.quarter;
      state.dataRevision += 1;
      return () => loadQuarter();
    case "FOCUS_FIRM":
      if (!Number.isInteger(action.firmId) || action.firmId < 1) return null;
      stopPlayback();
      abortQuarterRequest();
      state.mode = "firm";
      state.firmFocus = action.firmId;
      state.selected = { type: "node", id: `firm:${action.firmId}` };
      state.dataRevision += 1;
      queueCameraIntent();
      return () => loadQuarter();
    case "CLEAR_FOCUS":
      if (!state.firmFocus) return null;
      stopPlayback();
      abortQuarterRequest();
      state.firmFocus = null;
      state.dataRevision += 1;
      queueCameraIntent();
      return () => loadQuarter();
    default:
      return null;
  }
}

function dispatch(action) {
  const effect = reduce(action);
  syncControls();
  return effect ? effect() : Promise.resolve(false);
}

function normalizeSectorMetadata(payload) {
  const rows = Array.isArray(payload) ? payload : payload?.sectors || payload?.data || [];
  return new Map(rows.map((row, index) => {
    const sector = Math.round(finite(row.index ?? row.sector ?? row.id, index + 1));
    const code = String(row.code || `S${sector}`);
    const label = String(row.label || row.name || `Sector ${sector}`);
    return [sector, { ...row, index: sector, code, label }];
  }));
}

async function fetchSectorMetadata(datasetId, signal) {
  const encoded = encodeURIComponent(datasetId || "");
  const candidates = [
    `/api/datasets/${encoded}/sector-metadata`,
    `/api/datasets/sector-metadata?dataset_id=${encoded}`,
    "/sector-metadata.json",
  ];
  let lastError = null;
  for (const url of candidates) {
    try {
      const payload = await fetchJSON(url, { signal });
      const metadata = normalizeSectorMetadata(payload);
      if (metadata.size) return metadata;
    } catch (error) {
      if (isAbort(error)) throw error;
      lastError = error;
    }
  }
  if (lastError) console.info("Sector metadata unavailable; using trace labels.", lastError.message);
  return new Map();
}

function datasetDisplayName(datasetId) {
  return String(datasetId || "Modeled economy").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

async function loadRun(runId, runRevision) {
  const controller = new AbortController();
  state.runController = controller;
  state.selected = null;
  els.inspector.hidden = true;
  els.empty.hidden = true;
  els.filters.replaceChildren();
  els.table.replaceChildren();
  els.tableCaption.textContent = "Largest visible ledger entries";
  els.querySummary.textContent = "Reading cash-flow manifest…";
  els.coverageNote.textContent = "";
  els.scaleNote.textContent = "";
  els.live.textContent = "Reading a new traced run.";
  showLoading("Reading cash-flow manifest…");
  requestDraw();
  try {
    const run = state.runs.find((item) => item.run_id === runId) || {};
    const [manifest, metadata] = await Promise.all([
      fetchJSON(`/api/runs/${encodeURIComponent(runId)}/cashflows`, { signal: controller.signal }),
      fetchSectorMetadata(run.dataset_id, controller.signal),
    ]);
    if (controller.signal.aborted || runRevision !== state.runRevision || runId !== state.runId) return false;
    const quarters = (manifest.quarters || []).map(Number).filter(Number.isInteger).sort((a, b) => a - b);
    if (!quarters.length) throw new Error("This trace contains no settled quarters.");
    state.manifest = { ...manifest, quarters };
    state.sectorMetadata = manifest.sector_metadata?.length
      ? normalizeSectorMetadata(manifest.sector_metadata)
      : metadata;
    state.quarter = quarters[0];
    state.dataRevision += 1;
    queueCameraIntent();
    els.range.min = String(quarters[0]);
    els.range.max = String(quarters.at(-1));
    els.range.value = String(state.quarter);
    syncControls();
    const datasetId = manifest.dataset_id || run.dataset_id;
    els.datasetLabel.textContent = `${datasetDisplayName(datasetId)} · exact quarterly cash flows`;
    const quarterPromise = loadQuarter();
    void loadFirmCatalog({ runId, runRevision, quarter: quarters[0], signal: controller.signal });
    return await quarterPromise;
  } catch (error) {
    if (!isAbort(error) && runRevision === state.runRevision) setError(error.message);
    return false;
  }
}

function quarterURL(snapshot, overrides = {}) {
  const level = snapshot.mode === "macro" ? "macro" : snapshot.mode;
  const params = new URLSearchParams({
    quarter: String(overrides.quarter ?? snapshot.quarter),
    detail: overrides.detail || (snapshot.mode === "firm" ? "firm" : "sector"),
    level: overrides.level || level,
    limit: String(overrides.limit ?? (snapshot.firmFocus ? 5000 : snapshot.mode === "firm" ? 1400 : 300)),
    sector_limit: "900",
  });
  if (snapshot.firmFocus && !overrides.ignoreFocus) {
    params.set("firm_id", String(snapshot.firmFocus));
    params.set("focus", `firm:${snapshot.firmFocus}`);
  }
  return `/api/runs/${encodeURIComponent(snapshot.runId)}/cashflows?${params}`;
}

async function loadFirmCatalog({ runId, runRevision, quarter, signal }) {
  const snapshot = { runId, quarter, mode: "firm", firmFocus: null };
  try {
    const payload = await fetchJSON(quarterURL(snapshot, { detail: "firm", limit: 1, ignoreFocus: true }), { signal });
    if (signal.aborted || runRevision !== state.runRevision || runId !== state.runId) return;
    if (payload.firms?.length) {
      setFirmCatalog(payload.firms);
      updateFirmOptions();
    }
  } catch (error) {
    if (!isAbort(error)) console.info("Firm catalog unavailable until the firm layer is opened.", error.message);
  }
}

function requestSnapshot() {
  return {
    runId: state.runId,
    runRevision: state.runRevision,
    dataRevision: state.dataRevision,
    quarter: state.quarter,
    mode: state.mode,
    firmFocus: state.firmFocus,
  };
}

function requestIsCurrent(snapshot, controller) {
  return !controller.signal.aborted &&
    snapshot.runId === state.runId &&
    snapshot.runRevision === state.runRevision &&
    snapshot.dataRevision === state.dataRevision &&
    snapshot.quarter === state.quarter &&
    snapshot.mode === state.mode &&
    snapshot.firmFocus === state.firmFocus;
}

async function loadQuarter() {
  if (!state.runId) return;
  abortQuarterRequest();
  const snapshot = requestSnapshot();
  const controller = new AbortController();
  state.quarterController = controller;
  showLoading(`Settling quarter ${snapshot.quarter}…`);
  try {
    const payload = await fetchJSON(quarterURL(snapshot), { signal: controller.signal });
    if (!requestIsCurrent(snapshot, controller)) return false;
    state.data = payload;
    state.quarterController = null;
    els.empty.hidden = true;
    if (payload.sector_metadata?.length) state.sectorMetadata = normalizeSectorMetadata(payload.sector_metadata);
    if (payload.firms?.length) incorporateQueryFirms(payload.firms);
    updateTimeline();
    buildScene(snapshot);
    updateAccounting();
    updateFirmOptions();
    updateFilters();
    refreshSelection();
    refreshQueryUI();
    applyCameraIntent();
    ensureSceneVisible();
    hideLoading();
    if (state.playing) schedulePlayback();
    return true;
  } catch (error) {
    if (!isAbort(error) && requestIsCurrent(snapshot, controller)) {
      state.quarterController = null;
      hideLoading();
      if (state.playing) stopPlayback();
      els.querySummary.textContent = `Could not load quarter ${snapshot.quarter}: ${error.message}`;
      els.coverageNote.textContent = "";
      els.scaleNote.textContent = "";
      els.live.textContent = els.querySummary.textContent;
      ensureSceneVisible();
    }
    return false;
  }
}

function updateTimeline() {
  const data = state.data;
  const quarters = state.manifest.quarters || [];
  const index = quarters.indexOf(state.quarter);
  const period = data.period || state.manifest.periods?.[index] || `Quarter ${state.quarter}`;
  els.period.textContent = period;
  els.quarterCount.textContent = `Q ${index + 1} / ${quarters.length}`;
  els.range.value = String(state.quarter);
  const realization = data.realization || state.manifest.realization || {};
  els.realization.textContent = `Exact realization ${realization.index || 1} · seed ${realization.seed ?? "—"} · ensemble ${realization.ensemble_size || 1}`;
  const unit = data.units?.flow || "million_eur_per_quarter";
  const normalizedUnit = String(unit).toLowerCase();
  state.currencySymbol = normalizedUnit.includes("usd") || normalizedUnit.includes("dollar") ? "$"
    : normalizedUnit.includes("gbp") || normalizedUnit.includes("sterling") ? "£"
      : normalizedUnit.includes("eur") ? "€" : "¤";
  els.brandSigil.textContent = state.currencySymbol;
  const millionUnit = normalizedUnit.includes("million_")
    ? `${state.currencySymbol}m${normalizedUnit.includes("per_quarter") ? " per quarter" : ""}`
    : unit.replaceAll("_", " ");
  els.units.textContent = millionUnit;
}

function updateAccounting() {
  const diagnostics = state.data?.diagnostics || {};
  const passed = diagnostics.passed === true || diagnostics.passed === 1;
  els.badge.className = `status-badge ${passed ? "pass" : "fail"}`;
  els.badge.textContent = passed ? "Accounting checks pass" : "Review residuals";
  const residuals = Object.entries(diagnostics)
    .filter(([key]) => key.endsWith("_residual"))
    .map(([key, value]) => `${humanize(key)}: ${finite(value).toExponential(2)}`)
    .join("\n");
  els.badge.title = residuals || "No diagnostic residuals reported";
}

function sectorIdentity(sector, fallbackLabel = "") {
  const index = Math.round(finite(sector));
  const metadata = state.sectorMetadata.get(index);
  const code = metadata?.code || `S${index}`;
  const name = metadata?.label || fallbackLabel || `Sector ${index}`;
  return { index, code, name, label: `${code} · ${name}` };
}

function numericFirmId(id) {
  const match = String(id || "").match(/(\d+)$/);
  return match ? Number(match[1]) : Number.NaN;
}

function setFirmCatalog(firms) {
  const sorted = [...firms].sort((a, b) => numericFirmId(a.id) - numericFirmId(b.id));
  const ordinalBySector = new Map();
  const catalog = new Map();
  for (const raw of sorted) {
    const sector = Math.round(finite(raw.sector));
    const ordinal = (ordinalBySector.get(sector) || 0) + 1;
    ordinalBySector.set(sector, ordinal);
    const identity = sectorIdentity(sector);
    const number = numericFirmId(raw.id);
    catalog.set(raw.id, {
      ...raw,
      kind: raw.kind || "firm",
      sector,
      ordinal,
      label: `${identity.code} · ${identity.name} · Firm ${String(ordinal).padStart(3, "0")}`,
      shortLabel: `${identity.code} · Firm ${String(ordinal).padStart(3, "0")}`,
      firmNumber: number,
    });
  }
  state.firmCatalog = catalog;
}

function incorporateQueryFirms(firms) {
  if (!state.firmCatalog.size || firms.length >= state.firmCatalog.size) {
    setFirmCatalog(firms);
    return;
  }
  for (const raw of firms) {
    const existing = state.firmCatalog.get(raw.id);
    if (!existing) continue;
    state.firmCatalog.set(raw.id, {
      ...existing,
      ...raw,
      label: existing.label,
      shortLabel: existing.shortLabel,
      ordinal: existing.ordinal,
      firmNumber: existing.firmNumber,
    });
  }
}

function decorateFirm(firm) {
  const catalogFirm = state.firmCatalog.get(firm.id);
  if (catalogFirm) return { ...firm, ...catalogFirm, metrics: firm.metrics || catalogFirm.metrics };
  const sector = Math.round(finite(firm.sector));
  const identity = sectorIdentity(sector);
  const number = numericFirmId(firm.id);
  return {
    ...firm,
    kind: firm.kind || "firm",
    sector,
    ordinal: number,
    firmNumber: number,
    label: `${identity.code} · ${identity.name} · Firm ${String(number).padStart(3, "0")}`,
    shortLabel: `${identity.code} · Firm ${String(number).padStart(3, "0")}`,
  };
}

function decoratePortal(node) {
  const sector = Math.round(finite(node.sector ?? node.good ?? numericFirmId(node.id)));
  if (!sector) return { ...node, external: true };
  const identity = sectorIdentity(sector);
  return {
    ...node,
    external: true,
    sector,
    label: `World market · ${identity.code} · ${identity.name}`,
    shortLabel: `World · ${identity.code}`,
  };
}

function positionScope() {
  return state.mode === "firm" && state.firmFocus ? `firm-ego-${state.firmFocus}` : state.mode;
}

function positionKey(id, scope = positionScope()) {
  return `${state.runId}:${scope}:${id}`;
}

function getPosition(id, fallback, scope = positionScope()) {
  const key = positionKey(id, scope);
  if (!state.positions.has(key)) state.positions.set(key, { ...fallback });
  return state.positions.get(key);
}

function hash(text) {
  let value = 2166136261;
  for (const character of String(text)) {
    value ^= character.charCodeAt(0);
    value = Math.imul(value, 16777619);
  }
  return value >>> 0;
}

function institutionLayout(id) {
  const base = {
    households: [-620, 300],
    production: [-570, -100],
    "goods-market": [-40, -50],
    government: [470, -330],
    bank: [470, 100],
    "central-bank": [910, 110],
  };
  const [x, y] = base[id] || [0, 0];
  return { x, y };
}

function macroNodes(data) {
  const nodes = (data.nodes || []).filter((node) => node.id !== "outside-world");
  const externalNodes = [
    { id: "world:exports", label: "World demand", kind: "outside_portal", group: "world", external: true },
    { id: "world:imports", label: "World suppliers", kind: "outside_portal", group: "world", external: true },
  ];
  return [...nodes, ...externalNodes].map((rawNode) => {
    const node = rawNode.id === "goods-market"
      ? { ...rawNode, label: "Products & services market" }
      : rawNode.id === "bank"
        ? { ...rawNode, label: "Commercial bank" }
        : rawNode;
    const fallback = node.id === "world:exports" ? { x: -1180, y: -320 } :
      node.id === "world:imports" ? { x: 1180, y: -220 } : institutionLayout(node.id);
    const position = getPosition(node.id, fallback);
    return { ...node, ...position, radius: node.external ? 42 : node.id === "goods-market" ? 52 : 62 };
  });
}

function sectorNodes(data) {
  const sectorList = data.sectors || [];
  const columns = 9;
  const nodes = sectorList.map((node, index) => {
    const sector = Math.round(finite(node.sector ?? node.index, index + 1));
    const identity = sectorIdentity(sector, node.label);
    const col = index % columns;
    const row = Math.floor(index / columns);
    const jitter = state.layoutVariant ? ((hash(node.id) % 100) - 50) * 1.4 : 0;
    const fallback = { x: -610 + col * 145 + jitter, y: -360 + row * 118 + (state.layoutVariant ? jitter * .25 : 0) };
    const position = getPosition(node.id, fallback);
    return { ...node, ...identity, sector, ...position, radius: 39 };
  });
  const institutions = (data.nodes || [])
    .filter((node) => !["outside-world", "production", "goods-market"].includes(node.id))
    .map((node, index) => {
      const angle = Math.PI * .15 + (index / 4) * Math.PI * 1.45;
      const fallback = { x: Math.cos(angle) * 1020, y: Math.sin(angle) * 650 };
      return { ...node, ...getPosition(node.id, fallback), radius: 55 };
    });
  const portals = (data.outside_portals || []).map((rawNode, index, array) => {
    const node = decoratePortal(rawNode);
    const angle = (index / Math.max(1, array.length)) * Math.PI * 2 - Math.PI / 2;
    const fallback = { x: Math.cos(angle) * 1300, y: Math.sin(angle) * 900 };
    return { ...node, ...getPosition(node.id, fallback), radius: 24, external: true };
  });
  return [...nodes, ...institutions, ...portals];
}

function firmNodes(data) {
  const firms = (data.firms || []).map(decorateFirm);
  const sectorIds = [...new Set(firms.map((firm) => Number(firm.sector)))].sort((a, b) => a - b);
  const sectorCenters = new Map();
  sectorIds.forEach((sector, index) => {
    const angle = ((index + 1) / Math.max(1, sectorIds.length)) * Math.PI * 8;
    const radius = 160 + (index + 1) * 15;
    sectorCenters.set(sector, { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius });
  });
  const members = new Map();
  firms.forEach((firm) => members.set(firm.sector, (members.get(firm.sector) || 0) + 1));
  const seen = new Map();
  const nodes = firms.map((firm) => {
    const sector = Number(firm.sector);
    const order = seen.get(sector) || 0;
    seen.set(sector, order + 1);
    const total = members.get(sector) || 1;
    const center = sectorCenters.get(sector) || { x: 0, y: 0 };
    const angle = (order / total) * Math.PI * 2 + (hash(firm.id) % 30) / 30;
    const ring = 24 + 8 * Math.floor(order / 10);
    const fallback = { x: center.x + Math.cos(angle) * ring, y: center.y + Math.sin(angle) * ring };
    return { ...firm, ...getPosition(firm.id, fallback), radius: 9 };
  });
  const portals = (data.outside_portals || []).map((rawNode, index, array) => {
    const node = decoratePortal(rawNode);
    const angle = (index / Math.max(1, array.length)) * Math.PI * 2;
    const fallback = { x: Math.cos(angle) * 1500, y: Math.sin(angle) * 1100 };
    return { ...node, ...getPosition(node.id, fallback), radius: 20, external: true };
  });
  const institutions = (data.nodes || []).map((node, index, array) => {
    const angle = (index / Math.max(1, array.length)) * Math.PI * 2 - Math.PI / 2;
    const fallback = { x: Math.cos(angle) * 1240, y: Math.sin(angle) * 860 };
    return {
      ...node,
      ...getPosition(node.id, fallback),
      radius: node.id === "outside-world" ? 42 : 34,
      external: node.id === "outside-world" || node.external,
    };
  });
  return [...nodes, ...institutions, ...portals];
}

function remapMacroFlow(flow) {
  const mapped = { ...flow };
  if (mapped.source === "outside-world") mapped.source = "world:exports";
  if (mapped.target === "outside-world") mapped.target = "world:imports";
  return mapped;
}

function relationshipFlows(rows, label, { includeLegacyCapacity = false } = {}) {
  const flows = [];
  for (const row of rows || []) {
    const recognition = String(row.recognition || row.cash_recognition || row.measure || "").toLowerCase();
    const rawLayer = String(row.layer || row.economic_layer || row.category || "").toLowerCase();
    const alreadyCapacity = rawLayer === "capacity" || recognition.includes("capacity") || recognition.includes("counterfactual");
    const amount = finite(row.amount ?? row.value);
    const source = row.display_source || row.source;
    const target = row.display_target || row.target;
    const category = alreadyCapacity ? "capacity"
      : ["products", "product", "services", "business_goods"].includes(rawLayer) ? "business"
        : rawLayer === "foreign" ? "external"
        : row.category || row.layer || "business";
    if (amount > 0) {
      flows.push({
        ...row,
        id: row.id || `${row.source}->${row.target}`,
        source,
        target,
        amount,
        category,
        label: alreadyCapacity ? row.label || "Capacity-counterfactual match" : row.label || label,
        nonCash: alreadyCapacity || rawLayer === "stocks" || recognition.includes("non_cash") || Boolean(row.non_cash),
        recognition: alreadyCapacity ? recognition || "capacity_counterfactual" : recognition || "realized_cash",
      });
    }
    const potential = finite(row.potential_amount);
    if (includeLegacyCapacity && !alreadyCapacity && potential > 0) {
      flows.push({
        ...row,
        id: `${row.id || `${row.source}->${row.target}`}:capacity`,
        source,
        target,
        amount: potential,
        category: "capacity",
        label: "Capacity-counterfactual match",
        nonCash: true,
        recognition: "capacity_counterfactual",
        provenance: row.potential_provenance || "capacity_counterfactual",
        explanation: "A non-cash capacity response supplied by the trace. It is visually separated from realized settlement.",
      });
    }
  }
  return flows;
}

function normalizedEdges(data, mode) {
  if (!Array.isArray(data.edges) || !data.edges.length) return null;
  const legacyRows = mode === "macro" ? data.flows : mode === "sector" ? data.sector_relationships : data.relationships;
  const isFilteredV2Response = Boolean(data.query_digest || data.edge_query || data.query);
  if (legacyRows?.length && !isFilteredV2Response) return null;
  const accepted = mode === "macro" ? ["economy", "macro"] : [mode];
  const scoped = data.edges.filter((edge) => {
    const level = String(edge.level || edge.altitude || "").toLowerCase();
    return !level || accepted.includes(level);
  });
  return scoped;
}

function egoFirmScene(data, allFlows) {
  const focusId = `firm:${state.firmFocus}`;
  const adjacentFlows = allFlows.filter((flow) => flow.source === focusId || flow.target === focusId);
  const endpointIds = new Set([focusId]);
  adjacentFlows.forEach((flow) => {
    endpointIds.add(flow.source);
    endpointIds.add(flow.target);
  });

  const candidateMap = new Map();
  (data.firms || []).map(decorateFirm).forEach((node) => candidateMap.set(node.id, node));
  (data.outside_portals || []).map(decoratePortal).forEach((node) => candidateMap.set(node.id, node));
  (data.nodes || []).forEach((node) => candidateMap.set(node.id, node));
  (data.sectors || []).forEach((node, index) => {
    const sector = Math.round(finite(node.sector ?? node.index, index + 1));
    candidateMap.set(node.id, { ...node, ...sectorIdentity(sector, node.label), sector });
  });
  if (!candidateMap.has(focusId) && state.firmCatalog.has(focusId)) candidateMap.set(focusId, state.firmCatalog.get(focusId));

  const roleTotals = new Map();
  const totals = (id) => {
    if (!roleTotals.has(id)) roleTotals.set(id, { supplier: 0, customer: 0 });
    return roleTotals.get(id);
  };
  for (const flow of adjacentFlows) {
    const weight = finite(flow.amount);
    if (flow.source === focusId && flow.target !== focusId) totals(flow.target).supplier += weight;
    if (flow.target === focusId && flow.source !== focusId) totals(flow.source).customer += weight;
  }

  const suppliers = [];
  const customers = [];
  const institutions = [];
  for (const id of endpointIds) {
    if (id === focusId) continue;
    const node = candidateMap.get(id);
    if (!node) continue;
    const role = totals(id);
    const isInstitution = !["firm", "outside_portal"].includes(node.kind) && !node.external;
    if (isInstitution) institutions.push(node);
    else if (role.supplier >= role.customer) suppliers.push(node);
    else customers.push(node);
  }
  const stable = (a, b) => String(a.id).localeCompare(String(b.id), undefined, { numeric: true });
  suppliers.sort(stable);
  customers.sort(stable);
  institutions.sort(stable);

  const laidOut = [];
  const focus = candidateMap.get(focusId) || {
    id: focusId,
    kind: "firm",
    label: `Firm ${state.firmFocus}`,
    firmNumber: state.firmFocus,
  };
  laidOut.push({ ...focus, x: 0, y: 0, radius: 36, focused: true, layoutScope: `${positionScope()}-focus` });

  const layoutSide = (nodes, direction) => {
    const perColumn = 15;
    const role = direction < 0 ? "supplier" : "customer";
    const layoutScope = `${positionScope()}-${role}`;
    const slotPrefix = `${state.runId}:${layoutScope}:`;
    const usedSlots = new Set(
      [...state.egoSlots.entries()]
        .filter(([key]) => key.startsWith(slotPrefix))
        .map(([, slot]) => slot),
    );
    nodes.forEach((node) => {
      const slotKey = `${slotPrefix}${node.id}`;
      let stableSlot = state.egoSlots.get(slotKey);
      if (stableSlot == null) {
        stableSlot = 0;
        while (usedSlots.has(stableSlot)) stableSlot += 1;
        state.egoSlots.set(slotKey, stableSlot);
        usedSlots.add(stableSlot);
      }
      const column = Math.floor(stableSlot / perColumn);
      const rowOrder = [7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1, 13, 0, 14];
      const row = rowOrder[stableSlot % perColumn];
      const y = (row - (perColumn - 1) / 2) * 76;
      const x = direction * (270 + column * 155);
      const jitter = ((hash(node.id) % 17) - 8) * 1.2;
      laidOut.push({
        ...node,
        ...getPosition(node.id, { x, y: y + jitter }, layoutScope),
        radius: node.kind === "firm" ? 18 : 22,
        egoRole: role,
        layoutScope,
      });
    });
  };
  layoutSide(suppliers, -1);
  layoutSide(customers, 1);

  institutions.forEach((node) => {
    const layoutScope = `${positionScope()}-institution`;
    const angle = (hash(node.id) / 0xffffffff) * Math.PI * 2 - Math.PI / 2;
    const ring = 330;
    const fallback = { x: Math.cos(angle) * ring, y: Math.sin(angle) * ring };
    laidOut.push({
      ...node,
      ...getPosition(node.id, fallback, layoutScope),
      radius: 28,
      egoRole: "institution",
      layoutScope,
    });
  });

  return { nodes: laidOut, flows: adjacentFlows };
}

function buildScene(snapshot = requestSnapshot()) {
  const data = state.data;
  if (!data) return;
  const v2Edges = normalizedEdges(data, state.mode);
  const includeLegacyCapacity = Boolean(
    data.query?.include_counterfactual ||
    data.query?.include_potential ||
    data.include_potential === true,
  );
  if (state.mode === "macro") {
    state.nodes = macroNodes(data);
    state.flows = relationshipFlows((v2Edges || data.flows || []).map(remapMacroFlow), "Cash payment", { includeLegacyCapacity });
  } else if (state.mode === "sector") {
    state.nodes = sectorNodes(data);
    state.flows = relationshipFlows(v2Edges || data.sector_relationships, "Business purchase", { includeLegacyCapacity });
  } else {
    state.flows = relationshipFlows(v2Edges || data.relationships, "Firm purchase", { includeLegacyCapacity });
    if (snapshot.firmFocus) {
      const ego = egoFirmScene(data, state.flows);
      state.nodes = ego.nodes;
      state.flows = ego.flows;
    } else {
      state.nodes = firmNodes(data);
    }
  }
  state.nodeMap = new Map(state.nodes.map((node) => [node.id, node]));
  state.flows = state.flows.filter((flow) => state.nodeMap.has(flow.source) && state.nodeMap.has(flow.target) && finite(flow.amount) > 0);
  state.hovered = null;
  hideTooltip();
  requestDraw();
}

function refreshSelection() {
  if (!state.selected) return;
  const type = state.selected.type;
  const id = state.selected.id;
  const item = type === "node"
    ? nodeById(id)
    : state.flows.find((flow) => flow.id === id);
  if (item) {
    inspect({ type, item });
    return;
  }
  state.selected = null;
  els.inspector.hidden = true;
}

function updateFirmOptions() {
  if (!state.firmCatalog.size) return;
  const firms = [...state.firmCatalog.values()].sort((a, b) => finite(a.firmNumber) - finite(b.firmNumber));
  els.firmOptions.replaceChildren(...firms.map((firm) => {
    const option = document.createElement("option");
    option.value = String(firm.firmNumber);
    option.label = firm.label;
    return option;
  }));
  const first = firms[0]?.firmNumber;
  const last = firms.at(-1)?.firmNumber;
  els.firmQuery.placeholder = first && last ? `Find firm ${first}–${last}` : "Find a firm";
}

function updateFilters() {
  const categories = [...new Set(state.flows.map((flow) => flow.category || "business"))];
  els.filters.replaceChildren(...categories.map((category) => {
    if (!state.activeCategories.has(category)) state.activeCategories.add(category);
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.category = category;
    button.setAttribute("aria-pressed", String(state.activeCategories.has(category)));
    button.style.setProperty("--flow-color", CATEGORY_COLORS[category] || "#b3c7be");
    const swatch = document.createElement("i");
    swatch.setAttribute("aria-hidden", "true");
    button.append(swatch, document.createTextNode(CATEGORY_LABELS[category] || humanize(category)));
    button.addEventListener("click", () => {
      if (state.activeCategories.has(category)) state.activeCategories.delete(category);
      else state.activeCategories.add(category);
      button.setAttribute("aria-pressed", String(state.activeCategories.has(category)));
      refreshQueryUI();
    });
    return button;
  }));
}

function nodeById(id) {
  return state.nodeMap.get(id);
}

function nodeLabel(id) {
  return nodeById(id)?.label || id.replaceAll(":", " ");
}

function visibleFlows() {
  return state.flows.filter((flow) => state.activeCategories.has(flow.category || "business"));
}

function isCapacityFlow(flow) {
  const recognition = String(flow.recognition || flow.cash_recognition || "").toLowerCase();
  return flow.category === "capacity" || flow.layer === "capacity" ||
    recognition.includes("capacity") || recognition.includes("counterfactual");
}

function isNonCashFlow(flow) {
  const recognition = String(flow.recognition || flow.cash_recognition || "").toLowerCase();
  return isCapacityFlow(flow) || flow.nonCash || flow.layer === "stocks" || flow.category === "stocks" ||
    recognition.includes("non_cash") || recognition.includes("stock");
}

function flowScaleClass(flow) {
  if (isCapacityFlow(flow)) return "capacity";
  return isNonCashFlow(flow) ? "noncash" : "cash";
}

function updateTable() {
  const top = visibleFlows().slice().sort((a, b) => finite(b.amount) - finite(a.amount)).slice(0, 30);
  els.tableCaption.textContent = `Largest ${top.length} visible ledger entries · ${state.data?.period || "current quarter"}`;
  els.table.replaceChildren(...top.map((flow) => {
    const row = document.createElement("tr");
    const evidence = humanize(flow.provenance);
    const cells = [
      isNonCashFlow(flow) ? `${flow.label || "Non-cash entry"} · non-cash` : flow.label || "Payment",
      nodeLabel(flow.source),
      nodeLabel(flow.target),
      formatMoney(flow.amount),
      evidence,
    ];
    cells.forEach((value, index) => {
      const cell = document.createElement("td");
      if (index === 0) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "table-flow-button";
        button.textContent = value;
        button.addEventListener("focus", () => focusFlow(flow));
        button.addEventListener("click", () => focusFlow(flow));
        cell.append(button);
      } else {
        cell.textContent = value;
      }
      row.append(cell);
    });
    return row;
  }));
}

function firstFinite(...values) {
  for (const value of values) {
    if (value == null || value === "") continue;
    const number = Number(value);
    if (Number.isFinite(number)) return number;
  }
  return null;
}

function coverageObject() {
  const coverage = state.data?.coverage || {};
  const keys = state.mode === "firm"
    ? ["relationships", "firm_relationships", "firm"]
    : state.mode === "sector"
      ? ["sector_relationships", "sectors", "sector"]
      : ["flows", "macro"];
  for (const key of keys) {
    if (coverage[key] && typeof coverage[key] === "object") return coverage[key];
  }
  const domains = Object.values(coverage).filter((value) =>
    value && typeof value === "object" && Number.isFinite(Number(value.count_total)));
  if (domains.length) {
    const summed = {};
    for (const field of ["count_total", "count_matching", "count_returned"]) {
      const supplied = domains.map((domain) => Number(domain[field])).filter(Number.isFinite);
      if (supplied.length) summed[field] = supplied.reduce((sum, value) => sum + value, 0);
    }
    if (domains.length === 1) {
      for (const field of ["amount_total", "amount_matching", "amount_returned"]) {
        const value = Number(domains[0][field]);
        if (Number.isFinite(value)) summed[field] = value;
      }
    }
    return summed;
  }
  return coverage;
}

function queryCoverage() {
  const data = state.data || {};
  const nested = coverageObject();
  const domains = Object.values(data.coverage || {}).filter((value) =>
    value && typeof value === "object" && Number.isFinite(Number(value.amount_matching)));
  const prefix = state.mode === "firm" ? "relationship" : state.mode === "sector" ? "sector_relationship" : "flow";
  const cashFlows = state.flows.filter((flow) => !isNonCashFlow(flow));
  const fallbackCount = cashFlows.length;
  const countTotal = firstFinite(data.edge_count_total, data.count_total, data[`${prefix}_count_total`], nested.count_total, nested.total_count, fallbackCount);
  const countMatching = firstFinite(data.edge_count_matching, data.count_matching, data[`${prefix}_count_matching`], nested.count_matching, nested.matching_count, countTotal);
  const countReturned = firstFinite(data.edge_count_returned, data.count_returned, data[`${prefix}_count_returned`], nested.count_returned, nested.returned_count, fallbackCount);
  const amountTotal = firstFinite(data.edge_amount_total, data.amount_total, data[`${prefix}_amount_total`], nested.amount_total, nested.total_amount);
  const amountMatching = firstFinite(data.edge_amount_matching, data.amount_matching, data[`${prefix}_amount_matching`], nested.amount_matching, nested.matching_amount, amountTotal);
  const amountReturned = firstFinite(data.edge_amount_returned, data.amount_returned, data[`${prefix}_amount_returned`], nested.amount_returned, nested.returned_amount);
  const fractions = domains
    .filter((domain) => Number(domain.amount_matching) > 0 && Number.isFinite(Number(domain.amount_returned)))
    .map((domain) => Number(domain.amount_returned) / Number(domain.amount_matching));
  const amountFractionRange = fractions.length
    ? { min: Math.min(...fractions), max: Math.max(...fractions), domains: fractions.length }
    : null;
  return { countTotal, countMatching, countReturned, amountTotal, amountMatching, amountReturned, amountFractionRange };
}

function normalizedLayer(flow) {
  if (isCapacityFlow(flow)) return "capacity";
  const category = String(flow.category || "").toLowerCase();
  if (["business", "goods", "product", "products", "business_goods"].includes(category)) return "products";
  if (["external", "foreign"].includes(category)) return "foreign";
  const layer = String(flow.layer || category).toLowerCase();
  if (["business", "goods", "product", "business_goods"].includes(layer)) return "products";
  if (layer === "external") return "foreign";
  return layer || "products";
}

function domainMaximum(domains, flow) {
  if (!domains || typeof domains !== "object") return null;
  const layer = normalizedLayer(flow);
  const keys = [
    layer,
    flow.category,
    state.mode === "firm" ? "relationships" : state.mode === "sector" ? "sector_relationships" : "flows",
  ].filter(Boolean);
  for (const key of keys) {
    const domain = domains[key];
    const value = typeof domain === "number" ? domain : domain?.max ?? domain?.maximum ?? domain?.amount_max;
    if (Number.isFinite(Number(value)) && Number(value) > 0) return Number(value);
  }
  const level = state.mode === "macro" ? "macro" : state.mode;
  for (const [key, domain] of Object.entries(domains)) {
    const [domainLevel, domainLayer, domainMeasure, domainUnits, domainRecognition] = key.split("|");
    if (domainLayer && domainLayer !== layer) continue;
    if (domainLevel && ![level, state.mode === "macro" ? "economy" : level].includes(domainLevel)) continue;
    if (domainMeasure && flow.measure_kind && domainMeasure !== String(flow.measure_kind)) continue;
    if (domainUnits && flow.units && domainUnits !== String(flow.units)) continue;
    const recognition = String(flow.recognition || flow.cash_recognition || "");
    if (domainRecognition && recognition && domainRecognition !== recognition) continue;
    const value = typeof domain === "number" ? domain : domain?.max ?? domain?.maximum ?? domain?.amount_max;
    if (Number.isFinite(Number(value)) && Number(value) > 0) return Number(value);
  }
  const generic = domains.max ?? domains.maximum ?? domains.amount_max;
  return Number.isFinite(Number(generic)) && Number(generic) > 0 ? Number(generic) : null;
}

function explicitScaleMaximum(flow) {
  const payloadDomains = state.data?.scale_domains;
  const domains = payloadDomains && Object.keys(payloadDomains).length
    ? payloadDomains
    : state.manifest?.scale_domains;
  return domainMaximum(domains, flow);
}

function currentQuarterScaleMaximum(flow) {
  return domainMaximum(state.data?.scale_domains_current_quarter, flow);
}

function scaleMaximum(flow, fallback) {
  return explicitScaleMaximum(flow) || currentQuarterScaleMaximum(flow) || fallback;
}

function refreshQueryUI() {
  const visible = visibleFlows();
  const cash = visible.filter((flow) => !isNonCashFlow(flow));
  const capacity = visible.filter(isCapacityFlow);
  const otherNonCash = visible.filter((flow) => isNonCashFlow(flow) && !isCapacityFlow(flow));
  const cashAmount = cash.reduce((sum, flow) => sum + finite(flow.amount), 0);
  const capacityAmount = capacity.reduce((sum, flow) => sum + finite(flow.amount), 0);
  const otherNonCashAmount = otherNonCash.reduce((sum, flow) => sum + finite(flow.amount), 0);
  const modeLabel = state.firmFocus ? `Firm ${state.firmFocus} ego` : humanize(state.mode);
  const parts = [];
  if (state.firmFocus) parts.push(`${Math.max(0, state.nodes.length - 1).toLocaleString()} counterparties`);
  parts.push(`${cash.length.toLocaleString()} payments · ${formatMoney(cashAmount)} cash`);
  if (capacity.length) parts.push(`${capacity.length.toLocaleString()} potential supply responses · ${formatMoney(capacityAmount)} non-cash`);
  if (otherNonCash.length) parts.push(`${otherNonCash.length.toLocaleString()} stock/non-cash entries · ${formatMoney(otherNonCashAmount)}`);
  els.querySummary.textContent = `${modeLabel}: ${parts.join(" · ")}`;

  const coverage = queryCoverage();
  const returned = Math.round(coverage.countReturned ?? cash.length);
  const matching = Math.round(coverage.countMatching ?? returned);
  const countText = matching === 0
    ? "No relationships match this query"
    : returned < matching
      ? `${returned.toLocaleString()} of ${matching.toLocaleString()} matching relationships returned`
      : `${matching.toLocaleString()} matching relationships complete`;
  let amountText = "";
  if (coverage.amountReturned != null && coverage.amountMatching != null && coverage.amountMatching > 0) {
    amountText = ` · ${(coverage.amountReturned / coverage.amountMatching * 100).toFixed(1)}% value coverage`;
  } else if (coverage.amountFractionRange) {
    const { min, max, domains } = coverage.amountFractionRange;
    const range = Math.abs(max - min) < .0005
      ? `${(min * 100).toFixed(1)}%`
      : `${(min * 100).toFixed(1)}–${(max * 100).toFixed(1)}%`;
    amountText = ` · ${range} value coverage across ${domains} compatible domains`;
  } else if (returned < matching) {
    amountText = " · value coverage unavailable";
  }
  els.coverageNote.textContent = `Trace coverage · ${countText}${amountText}`;
  els.coverageNote.dataset.level = returned < matching &&
    coverage.amountReturned == null &&
    !coverage.amountFractionRange ? "warning" : "normal";

  const hasExplicitScale = state.flows.some((flow) => explicitScaleMaximum(flow) != null);
  const hasCurrentQuarterScale = state.flows.some((flow) => currentQuarterScaleMaximum(flow) != null);
  els.scaleNote.textContent = hasExplicitScale
    ? "Comparable run-wide scale"
    : hasCurrentQuarterScale
      ? "Current-quarter scale · not cross-quarter comparable"
      : "Legacy current-query scale";
  els.scaleNote.dataset.level = hasExplicitScale ? "normal" : "warning";
  updateTable();
  const period = state.data?.period || `quarter ${state.quarter}`;
  els.live.textContent = `${period}, ${modeLabel}. ${parts.join(". ")}. ${countText}${amountText}.`;
  requestDraw();
}

function worldToScreen(point) {
  return { x: point.x * state.view.scale + state.view.x, y: point.y * state.view.scale + state.view.y };
}

function screenToWorld(point) {
  return { x: (point.x - state.view.x) / state.view.scale, y: (point.y - state.view.y) / state.view.scale };
}

function resizeCanvas() {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  state.size = { width: rect.width, height: rect.height, dpr };
  canvas.width = Math.round(rect.width * dpr);
  canvas.height = Math.round(rect.height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  requestDraw();
  requestAnimationFrame(() => {
    if (state.cameraMode === "fitted") fitView();
    else ensureSceneVisible();
  });
}

function drawGrid() {
  const { width, height } = state.size;
  ctx.fillStyle = "#06100e";
  ctx.fillRect(0, 0, width, height);
  const scale = state.view.scale;
  const step = 80 * scale;
  const major = step * 5;
  ctx.lineWidth = 1;
  for (const [spacing, color] of [[step, "rgba(133,224,180,.045)"], [major, "rgba(133,224,180,.08)"]]) {
    if (spacing < 12) continue;
    ctx.beginPath();
    const startX = ((state.view.x % spacing) + spacing) % spacing;
    const startY = ((state.view.y % spacing) + spacing) % spacing;
    for (let x = startX; x < width; x += spacing) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
    for (let y = startY; y < height; y += spacing) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
    ctx.strokeStyle = color;
    ctx.stroke();
  }
}

function roundRectPath(context, x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.moveTo(x + r, y);
  context.arcTo(x + width, y, x + width, y + height, r);
  context.arcTo(x + width, y + height, x, y + height, r);
  context.arcTo(x, y + height, x, y, r);
  context.arcTo(x, y, x + width, y, r);
  context.closePath();
}

function drawEconomyBoundary() {
  const nw = worldToScreen({ x: -820, y: -520 });
  const se = worldToScreen({ x: 820, y: 520 });
  const width = se.x - nw.x;
  const height = se.y - nw.y;
  ctx.save();
  roundRectPath(ctx, nw.x, nw.y, width, height, Math.max(18, 38 * state.view.scale));
  ctx.fillStyle = "rgba(133,224,180,.025)";
  ctx.fill();
  ctx.setLineDash([8, 8]);
  ctx.lineWidth = 1.2;
  ctx.strokeStyle = "rgba(133,224,180,.24)";
  ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = "rgba(133,224,180,.52)";
  ctx.font = `600 ${Math.max(9, 11 * Math.min(1.2, state.view.scale))}px ${state.fontFamily}`;
  ctx.letterSpacing = "1px";
  ctx.fillText("MODELED ECONOMY · CASH SETTLEMENT BOUNDARY", nw.x + 18, nw.y + 23);
  ctx.restore();

  const worldLabels = [
    { x: -1420, y: -720 }, { x: 980, y: -700 }, { x: -1450, y: 780 }, { x: 1040, y: 790 },
  ];
  ctx.save();
  ctx.fillStyle = "rgba(128,184,244,.22)";
  ctx.font = `600 ${Math.max(10, 13 * state.view.scale)}px ${state.fontFamily}`;
  for (const point of worldLabels) {
    const screen = worldToScreen(point);
    ctx.fillText("REST OF WORLD · OUTSIDE MODELED ECONOMY", screen.x, screen.y);
  }
  ctx.restore();
}

function bezierForFlow(flow) {
  const sourceNode = nodeById(flow.source);
  const targetNode = nodeById(flow.target);
  if (!sourceNode || !targetNode) return null;
  const source = worldToScreen(sourceNode);
  const target = worldToScreen(targetNode);
  const dx = target.x - source.x;
  const dy = target.y - source.y;
  const distance = Math.hypot(dx, dy) || 1;
  const bend = (((hash(flow.id) % 100) / 100) - .5) * Math.min(120, distance * .25);
  const nx = -dy / distance;
  const ny = dx / distance;
  return {
    source, target,
    c1: { x: source.x + dx * .32 + nx * bend, y: source.y + dy * .32 + ny * bend },
    c2: { x: source.x + dx * .68 + nx * bend, y: source.y + dy * .68 + ny * bend },
  };
}

function bezierPoint(curve, t) {
  const mt = 1 - t;
  const x = mt ** 3 * curve.source.x + 3 * mt ** 2 * t * curve.c1.x + 3 * mt * t ** 2 * curve.c2.x + t ** 3 * curve.target.x;
  const y = mt ** 3 * curve.source.y + 3 * mt ** 2 * t * curve.c1.y + 3 * mt * t ** 2 * curve.c2.y + t ** 3 * curve.target.y;
  return { x, y };
}

function drawFlows() {
  const flows = visibleFlows();
  const fallbackMaxima = { cash: 1, capacity: 1, noncash: 1 };
  for (const flow of state.flows) {
    const key = flowScaleClass(flow);
    fallbackMaxima[key] = Math.max(fallbackMaxima[key], finite(flow.amount));
  }
  const selectedId = state.hovered?.type === "flow" ? state.hovered.item.id : state.selected?.type === "flow" ? state.selected.id : null;
  for (const flow of flows.slice().sort((a, b) => finite(a.amount) - finite(b.amount))) {
    const curve = bezierForFlow(flow);
    if (!curve) continue;
    const capacity = isCapacityFlow(flow);
    const nonCash = isNonCashFlow(flow);
    const maximum = scaleMaximum(flow, fallbackMaxima[flowScaleClass(flow)]);
    const ratio = Math.sqrt(finite(flow.amount) / maximum);
    const width = Math.max(.8, 1 + ratio * 13) * Math.min(1.25, Math.max(.7, state.view.scale));
    const color = CATEGORY_COLORS[flow.category] || CATEGORY_COLORS.business;
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(curve.source.x, curve.source.y);
    ctx.bezierCurveTo(curve.c1.x, curve.c1.y, curve.c2.x, curve.c2.y, curve.target.x, curve.target.y);
    ctx.lineWidth = flow.id === selectedId ? width + 4 : width;
    ctx.strokeStyle = color;
    ctx.globalAlpha = flow.id === selectedId ? .98 : nonCash ? .35 + ratio * .28 : .28 + ratio * .48;
    ctx.lineCap = "round";
    if (capacity) ctx.setLineDash([8, 7]);
    else if (nonCash) ctx.setLineDash([2, 5]);
    ctx.stroke();
    ctx.setLineDash([]);

    const arrow = bezierPoint(curve, .84);
    const before = bezierPoint(curve, .80);
    const angle = Math.atan2(arrow.y - before.y, arrow.x - before.x);
    const size = Math.max(5, Math.min(11, width * .8 + 4));
    ctx.translate(arrow.x, arrow.y);
    ctx.rotate(angle);
    ctx.beginPath();
    ctx.moveTo(size, 0);
    ctx.lineTo(-size * .7, size * .6);
    ctx.lineTo(-size * .7, -size * .6);
    ctx.closePath();
    ctx.globalAlpha = .92;
    if (nonCash) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.5;
      ctx.stroke();
    } else {
      ctx.fillStyle = color;
      ctx.fill();
    }
    ctx.restore();
  }
}

function nodeStyle(node) {
  return NODE_STYLES[node.kind] || ["#14251f", "#a9b7c2"];
}

function drawNodes() {
  for (const node of state.nodes) {
    const screen = worldToScreen(node);
    const radius = Math.max(3, node.radius * state.view.scale);
    const [fill, stroke] = nodeStyle(node);
    const highlighted = state.hovered?.type === "node" && state.hovered.item.id === node.id ||
      state.selected?.type === "node" && state.selected.id === node.id;
    ctx.save();
    if (node.external) ctx.setLineDash([6, 5]);
    ctx.beginPath();
    ctx.arc(screen.x, screen.y, radius, 0, Math.PI * 2);
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.strokeStyle = highlighted ? "#d7ff99" : stroke;
    ctx.lineWidth = highlighted ? 3 : Math.max(1, state.view.scale);
    ctx.stroke();
    ctx.setLineDash([]);

    if (radius >= 7) {
      const label = state.mode === "firm" && radius < 13
        ? node.firmNumber || node.id.replace("firm:", "")
        : node.external && node.shortLabel
          ? node.shortLabel
          : state.mode === "firm" && node.shortLabel ? node.shortLabel : node.code || node.label;
      ctx.fillStyle = highlighted ? "#ffffff" : "#e7f3ed";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.font = `${highlighted ? 700 : 600} ${Math.max(8, Math.min(13, radius * .27))}px ${state.fontFamily}`;
      const maxWidth = Math.max(radius * 1.7, 20);
      ctx.fillText(label, screen.x, screen.y, maxWidth);
    }
    ctx.restore();
  }
}

function drawNow() {
  if (!ctx) return;
  ctx.setTransform(state.size.dpr, 0, 0, state.size.dpr, 0, 0);
  drawGrid();
  drawEconomyBoundary();
  if (!state.data) return;
  drawFlows();
  drawNodes();
}

function requestDraw() {
  if (state.frameRequest != null) return;
  state.frameRequest = requestAnimationFrame(() => {
    state.frameRequest = null;
    drawNow();
  });
}

function draw() {
  requestDraw();
}

function safeViewport() {
  const canvasRect = canvas.getBoundingClientRect();
  let top = 20;
  for (const element of [$(".canvas-tools"), els.filters, $("#query-status")]) {
    if (!element || element.hidden) continue;
    const rect = element.getBoundingClientRect();
    if (rect.bottom > canvasRect.top && rect.top < canvasRect.bottom) top = Math.max(top, rect.bottom - canvasRect.top + 16);
  }
  let right = 24;
  let bottom = 62;
  if (!els.inspector.hidden) {
    const rect = els.inspector.getBoundingClientRect();
    if (rect.left > canvasRect.left + canvasRect.width * .45) right = Math.max(right, canvasRect.right - rect.left + 18);
    else bottom = Math.max(bottom, canvasRect.bottom - rect.top + 18);
  }
  return {
    left: 28,
    top: Math.min(top, state.size.height * .48),
    right: Math.max(80, state.size.width - right),
    bottom: Math.max(top + 80, state.size.height - bottom),
  };
}

function fitView(targetNode = null) {
  const nodes = targetNode ? [targetNode] : state.nodes;
  if (!nodes.length) return;
  const safe = safeViewport();
  if (targetNode) {
    state.view.scale = Math.max(state.view.scale, state.mode === "firm" ? 2.4 : 1.25);
    state.view.x = (safe.left + safe.right) / 2 - targetNode.x * state.view.scale;
    state.view.y = (safe.top + safe.bottom) / 2 - targetNode.y * state.view.scale;
  } else {
    const minX = Math.min(...nodes.map((node) => node.x - node.radius));
    const maxX = Math.max(...nodes.map((node) => node.x + node.radius));
    const minY = Math.min(...nodes.map((node) => node.y - node.radius));
    const maxY = Math.max(...nodes.map((node) => node.y + node.radius));
    const width = Math.max(1, maxX - minX);
    const height = Math.max(1, maxY - minY);
    const availableWidth = Math.max(80, safe.right - safe.left - 36);
    const availableHeight = Math.max(80, safe.bottom - safe.top - 36);
    state.view.scale = Math.max(.08, Math.min(1.1, availableWidth / width, availableHeight / height));
    state.view.x = (safe.left + safe.right) / 2 - ((minX + maxX) / 2) * state.view.scale;
    state.view.y = (safe.top + safe.bottom) / 2 - ((minY + maxY) / 2) * state.view.scale;
  }
  state.cameraMode = "fitted";
  updateZoomLabel();
  requestDraw();
}

function resetView() {
  cancelCameraIntent();
  state.cameraMode = "manual";
  state.view = { x: state.size.width / 2, y: state.size.height / 2, scale: 1 };
  updateZoomLabel();
  requestDraw();
}

function updateZoomLabel() {
  els.zoom.textContent = `${Math.round(state.view.scale * 100)}%`;
}

function zoomAt(factor, point = { x: state.size.width / 2, y: state.size.height / 2 }) {
  cancelCameraIntent();
  state.cameraMode = "manual";
  const before = screenToWorld(point);
  state.view.scale = Math.max(.12, Math.min(4.5, state.view.scale * factor));
  state.view.x = point.x - before.x * state.view.scale;
  state.view.y = point.y - before.y * state.view.scale;
  updateZoomLabel();
  requestDraw();
}

function applyCameraIntent() {
  const intent = state.cameraIntent;
  if (!intent || intent.runRevision !== state.runRevision || !state.nodes.length) return false;
  state.cameraIntent = null;
  if (intent.type === "fit-scene") fitView();
  return true;
}

function sceneIntersectsSafeViewport() {
  if (!state.nodes.length) return true;
  const safe = safeViewport();
  return state.nodes.some((node) => {
    const point = worldToScreen(node);
    const radius = Math.max(3, node.radius * state.view.scale);
    return point.x + radius >= safe.left && point.x - radius <= safe.right &&
      point.y + radius >= safe.top && point.y - radius <= safe.bottom;
  });
}

function ensureSceneVisible() {
  if (!state.nodes.length) return;
  const finiteView = [state.view.x, state.view.y, state.view.scale].every(Number.isFinite);
  if (!finiteView || state.view.scale <= 0 || !sceneIntersectsSafeViewport()) {
    cancelCameraIntent();
    fitView();
    els.live.textContent = `${els.live.textContent} View recovered to keep the ledger visible.`.trim();
  }
}

function pointerPosition(event) {
  const rect = canvas.getBoundingClientRect();
  return { x: event.clientX - rect.left, y: event.clientY - rect.top };
}

function hitNode(point) {
  for (let index = state.nodes.length - 1; index >= 0; index -= 1) {
    const node = state.nodes[index];
    const screen = worldToScreen(node);
    if (Math.hypot(point.x - screen.x, point.y - screen.y) <= Math.max(8, node.radius * state.view.scale)) return node;
  }
  return null;
}

function hitFlow(point) {
  const flows = visibleFlows();
  const maxima = {
    cash: Math.max(1, ...state.flows.filter((flow) => flowScaleClass(flow) === "cash").map((flow) => finite(flow.amount))),
    capacity: Math.max(1, ...state.flows.filter(isCapacityFlow).map((flow) => finite(flow.amount))),
    noncash: Math.max(1, ...state.flows.filter((flow) => flowScaleClass(flow) === "noncash").map((flow) => finite(flow.amount))),
  };
  let best = null;
  let bestDistance = Infinity;
  for (const flow of flows) {
    const curve = bezierForFlow(flow);
    if (!curve) continue;
    const maximum = scaleMaximum(flow, maxima[flowScaleClass(flow)]);
    const threshold = 6 + 7 * Math.sqrt(finite(flow.amount) / maximum);
    for (let step = 1; step < 28; step += 1) {
      const sample = bezierPoint(curve, step / 28);
      const distance = Math.hypot(point.x - sample.x, point.y - sample.y);
      if (distance < threshold && distance < bestDistance) {
        best = flow;
        bestDistance = distance;
      }
    }
  }
  return best;
}

function tooltipHTML(target) {
  if (target.type === "flow") {
    const flow = target.item;
    const explanation = flow.explanation || (isCapacityFlow(flow)
      ? "A non-cash capacity-counterfactual response, not a settled payment."
      : isNonCashFlow(flow)
        ? "A recorded stock or other non-cash model entry, visually separated from settlement."
      : flow.category === "business"
      ? "A realized business-goods payment in representative realization 1. The buyer pays the matched seller."
      : "Cash recorded by the model during this quarter.");
    return `<strong>${flow.label || "Payment"}</strong>
      <span class="amount">${formatMoney(flow.amount)}</span>
      <p class="route">${nodeLabel(flow.source)} → ${nodeLabel(flow.target)}</p>
      <span class="meta">${explanation}</span><br>
      <span class="evidence">${humanize(flow.provenance)}</span>`;
  }
  const node = target.item;
  const metrics = Object.entries(node.metrics || {}).slice(0, 3)
    .map(([key, value]) => `${humanize(key)}: ${typeof value === "number" ? formatMetric(key, value) : value}`).join(" · ");
  return `<strong>${node.label}</strong><span class="meta">${humanize(node.kind)}${node.sector ? ` · sector ${node.sector}` : ""}</span>
    ${metrics ? `<p class="route">${metrics}</p>` : ""}<span class="evidence">${node.external ? "World market portal" : "Model agent"}</span>`;
}

function positionTooltip(point) {
  const pad = 14;
  const rect = els.tooltip.getBoundingClientRect();
  let left = point.x + 16;
  let top = point.y + 16;
  if (left + rect.width > window.innerWidth - pad) left = point.x - rect.width - 16;
  if (top + rect.height > window.innerHeight - pad) top = point.y - rect.height - 16;
  els.tooltip.style.left = `${Math.max(pad, left)}px`;
  els.tooltip.style.top = `${Math.max(pad, top)}px`;
}

function showTooltip(target, clientPoint) {
  els.tooltip.innerHTML = tooltipHTML(target);
  els.tooltip.hidden = false;
  positionTooltip(clientPoint);
}

function hideTooltip() {
  els.tooltip.hidden = true;
}

function formatMetric(key, value) {
  if (/rate/.test(key)) return `${(finite(value) * 100).toFixed(2)}%`;
  if (/agents|firms|employment/.test(key)) return Math.round(finite(value)).toLocaleString();
  return formatMoney(value);
}

function stockMetricsForNode(node) {
  const stocks = state.data?.stocks || {};
  let keys = node.id === "households" ? ["household_deposits"] :
    node.id === "production" ? ["firm_deposits", "firm_loans"] :
    node.id === "government" ? ["government_debt"] :
    node.id === "bank" ? ["bank_equity"] :
    node.external ? ["external_position"] : [];
  const reportedKeys = Object.keys(stocks);
  if (node.id === "central-bank") {
    keys = reportedKeys.filter((key) => /central[_-]?bank/i.test(key));
  } else if (node.id === "bank") {
    keys = [...new Set([
      ...keys,
      ...reportedKeys.filter((key) => /commercial[_-]?bank|^bank[_-]/i.test(key) && !/central/i.test(key)),
    ])];
  }
  const metrics = {};
  for (const key of keys) {
    const stock = stocks[key];
    if (!stock) continue;
    metrics[`${humanize(key)} · opening`] = formatMoney(stock.open);
    metrics[`${humanize(key)} · closing`] = formatMoney(stock.close);
  }
  return metrics;
}

function inspect(target) {
  state.selected = { type: target.type, id: target.item.id };
  const item = target.item;
  els.inspector.hidden = false;
  els.inspectMetrics.replaceChildren();
  if (target.type === "flow") {
    els.inspectKicker.textContent = isCapacityFlow(item)
      ? "Non-cash potential supply response"
      : isNonCashFlow(item) ? "Stock / non-cash entry" : "Cash payment";
    els.inspectTitle.textContent = item.label || "Payment";
    els.inspectSubtitle.textContent = `${nodeLabel(item.source)} → ${nodeLabel(item.target)}`;
    const metrics = {
      Amount: formatMoney(item.amount),
      Category: CATEGORY_LABELS[item.category] || humanize(item.category),
      Recognition: humanize(item.recognition || (isCapacityFlow(item) ? "capacity_counterfactual" : "realized_cash")),
      Transactions: item.transaction_count ?? "aggregate equation",
      Quantity: item.quantity != null ? finite(item.quantity).toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—",
      Provenance: humanize(item.provenance),
    };
    fillInspectorMetrics(metrics);
    els.inspectCopy.textContent = item.explanation || (isCapacityFlow(item)
      ? "This response is kept separate from cash settlement so potential capacity is never misread as money that changed hands."
      : isNonCashFlow(item)
        ? "This entry is not included in cash totals. Its direction and value follow the trace’s declared stock or non-cash semantics."
      : item.category === "business"
      ? "This is exact bilateral cash from the representative simulation path. Buyer-to-seller direction follows money, not the physical good."
      : "This cash amount is calculated directly from the model equation for the selected quarter.");
    els.inspectFocus.hidden = true;
  } else {
    els.inspectKicker.textContent = humanize(item.kind);
    els.inspectTitle.textContent = item.label;
    const identity = item.sector ? sectorIdentity(item.sector) : null;
    els.inspectSubtitle.textContent = item.kind === "firm" && identity
      ? `Synthetic firm · ${identity.code} · ${identity.name}`
      : identity
        ? `${identity.code} · ${identity.name}`
        : item.external ? "A portal into the surrounding world market" : "Model agent";
    const metrics = {};
    Object.entries(item.metrics || {}).forEach(([key, value]) => { metrics[humanize(key)] = typeof value === "number" ? formatMetric(key, value) : value; });
    Object.assign(metrics, stockMetricsForNode(item));
    fillInspectorMetrics(metrics);
    els.inspectCopy.textContent = item.external
      ? "The world is not a single agent or a harbor. This perimeter portal represents an imported good’s supplier market beyond the modeled economy."
      : "Drag this node to disentangle crossings. Its position is explanatory; cash values and counterparties remain unchanged.";
    const firmId = item.kind === "firm" ? numericFirmId(item.id) : null;
    els.inspectFocus.hidden = !firmId || state.firmFocus === firmId;
    els.inspectFocus.dataset.firmId = firmId || "";
  }
  requestDraw();
}

function fillInspectorMetrics(metrics) {
  for (const [label, value] of Object.entries(metrics)) {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = label;
    dd.textContent = String(value);
    els.inspectMetrics.append(dt, dd);
  }
}

function focusFlow(flow) {
  const curve = bezierForFlow(flow);
  if (!curve) return;
  inspect({ type: "flow", item: flow });
  const point = bezierPoint(curve, .5);
  showTooltip({ type: "flow", item: flow }, {
    x: canvas.getBoundingClientRect().left + point.x,
    y: canvas.getBoundingClientRect().top + point.y,
  });
  setTimeout(hideTooltip, 2400);
}

async function focusFirm(firmId) {
  if (!Number.isInteger(firmId) || firmId < 1) {
    els.live.textContent = "Enter a valid firm ID.";
    els.firmQuery.setCustomValidity("Enter a valid firm ID.");
    els.firmQuery.reportValidity();
    return;
  }
  if (state.firmCatalog.size && !state.firmCatalog.has(`firm:${firmId}`)) {
    els.live.textContent = `Firm ${firmId} is not present in this traced run.`;
    els.firmQuery.setCustomValidity("Choose a firm from this traced run.");
    els.firmQuery.reportValidity();
    return;
  }
  els.firmQuery.setCustomValidity("");
  await dispatch({ type: "FOCUS_FIRM", firmId });
  const node = nodeById(`firm:${firmId}`);
  if (!node) {
    els.live.textContent = `Firm ${firmId} was not found in this realization.`;
    return;
  }
  inspect({ type: "node", item: node });
}

function syncControls() {
  $$("[data-mode]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.mode === state.mode)));
  els.showAllFirms.hidden = !state.firmFocus;
  els.showAllFirms.textContent = state.firmFocus ? `Show all firms · leave Firm ${state.firmFocus}` : "Show all firms";
  if (state.runId && els.run.value !== state.runId) els.run.value = state.runId;
  if (Number(els.range.value) !== state.quarter) els.range.value = String(state.quarter);
  els.play.disabled = !state.manifest || (state.manifest.quarters || []).length < 2;
}

function stopPlayback() {
  state.playing = false;
  clearTimeout(state.playTimer);
  state.playTimer = null;
  els.play.textContent = "▶";
  els.play.setAttribute("aria-label", "Play quarters");
}

function schedulePlayback() {
  clearTimeout(state.playTimer);
  state.playTimer = null;
  if (!state.playing || state.quarterController) return;
  state.playTimer = setTimeout(() => {
    state.playTimer = null;
    if (!state.playing || state.quarterController) return;
    const quarters = state.manifest?.quarters || [];
    const index = quarters.indexOf(state.quarter);
    const next = quarters[(index + 1) % quarters.length];
    if (next == null || next === state.quarter) {
      stopPlayback();
      return;
    }
    void dispatch({ type: "SET_QUARTER", quarter: next, source: "playback" });
  }, 1150);
}

function togglePlayback() {
  if (state.playing) {
    stopPlayback();
    return;
  }
  const quarters = state.manifest?.quarters || [];
  if (quarters.length < 2) {
    stopPlayback();
    els.live.textContent = "Playback requires at least two settled quarters.";
    return;
  }
  state.playing = true;
  els.play.textContent = "Ⅱ";
  els.play.setAttribute("aria-label", "Pause quarters");
  schedulePlayback();
}

canvas.addEventListener("pointerdown", (event) => {
  cancelCameraIntent();
  const point = pointerPosition(event);
  const node = hitNode(point);
  canvas.setPointerCapture(event.pointerId);
  state.drag = node && !node.focused
    ? { type: "node", node, start: point, origin: { x: node.x, y: node.y }, moved: false }
    : { type: "pan", start: point, origin: { x: state.view.x, y: state.view.y }, moved: false };
  canvas.classList.add("dragging");
});

canvas.addEventListener("pointermove", (event) => {
  const point = pointerPosition(event);
  if (state.drag) {
    const dx = point.x - state.drag.start.x;
    const dy = point.y - state.drag.start.y;
    state.drag.moved ||= Math.hypot(dx, dy) > 3;
    if (state.drag.type === "node") {
      state.drag.node.x = state.drag.origin.x + dx / state.view.scale;
      state.drag.node.y = state.drag.origin.y + dy / state.view.scale;
      const key = positionKey(state.drag.node.id, state.drag.node.layoutScope || positionScope());
      state.positions.set(key, { x: state.drag.node.x, y: state.drag.node.y });
    } else {
      state.cameraMode = "manual";
      state.view.x = state.drag.origin.x + dx;
      state.view.y = state.drag.origin.y + dy;
    }
    hideTooltip();
    requestDraw();
    return;
  }
  const node = hitNode(point);
  const flow = node ? null : hitFlow(point);
  state.hovered = node ? { type: "node", item: node } : flow ? { type: "flow", item: flow } : null;
  canvas.classList.toggle("over-node", Boolean(node));
  if (state.hovered) showTooltip(state.hovered, { x: event.clientX, y: event.clientY });
  else hideTooltip();
  requestDraw();
});

canvas.addEventListener("pointerup", (event) => {
  const point = pointerPosition(event);
  if (state.drag && !state.drag.moved) {
    const node = hitNode(point);
    const flow = node ? null : hitFlow(point);
    if (node) inspect({ type: "node", item: node });
    else if (flow) inspect({ type: "flow", item: flow });
  }
  state.drag = null;
  canvas.classList.remove("dragging");
  try { canvas.releasePointerCapture(event.pointerId); } catch (_) { /* pointer already released */ }
});

canvas.addEventListener("pointerleave", () => {
  if (!state.drag) {
    state.hovered = null;
    hideTooltip();
    requestDraw();
  }
});

canvas.addEventListener("wheel", (event) => {
  event.preventDefault();
  zoomAt(Math.exp(-event.deltaY * .0012), pointerPosition(event));
}, { passive: false });

els.run.addEventListener("change", () => void dispatch({ type: "SELECT_RUN", runId: els.run.value }));
els.range.addEventListener("input", () => {
  void dispatch({ type: "SET_QUARTER", quarter: Number(els.range.value), source: "user" });
});
els.play.addEventListener("click", togglePlayback);

$$("[data-mode]").forEach((button) => button.addEventListener("click", () => {
  els.inspector.hidden = true;
  void dispatch({ type: "SET_MODE", mode: button.dataset.mode });
}));

$("#zoom-in").addEventListener("click", () => zoomAt(1.25));
$("#zoom-out").addEventListener("click", () => zoomAt(.8));
$("#fit-view").addEventListener("click", () => {
  cancelCameraIntent();
  state.cameraMode = "manual";
  fitView();
});
$("#reset-view").addEventListener("click", resetView);
$("#reflow").addEventListener("click", () => {
  state.layoutVariant = (state.layoutVariant + 1) % 2;
  const scope = positionScope();
  const scopePrefix = `${state.runId}:${scope}`;
  const matchesScope = (key) => key.startsWith(`${scopePrefix}:`) ||
    Boolean(state.firmFocus) && key.startsWith(`${scopePrefix}-`);
  for (const key of [...state.positions.keys()]) {
    if (matchesScope(key)) state.positions.delete(key);
  }
  for (const key of [...state.egoSlots.keys()]) {
    if (matchesScope(key)) state.egoSlots.delete(key);
  }
  buildScene(requestSnapshot());
  refreshSelection();
  refreshQueryUI();
  fitView();
});
els.showAllFirms.addEventListener("click", () => void dispatch({ type: "CLEAR_FOCUS" }));

$("#firm-search").addEventListener("submit", (event) => {
  event.preventDefault();
  focusFirm(Number.parseInt(els.firmQuery.value.replace(/\D/g, ""), 10));
});
els.inspectFocus.addEventListener("click", () => focusFirm(Number(els.inspectFocus.dataset.firmId)));
$("#close-inspector").addEventListener("click", () => {
  state.selected = null;
  els.inspector.hidden = true;
  requestDraw();
});

window.addEventListener("resize", resizeCanvas);
window.addEventListener("keydown", (event) => {
  if (event.target.matches("input, select, button, summary")) return;
  cancelCameraIntent();
  state.cameraMode = "manual";
  const step = event.shiftKey ? 90 : 35;
  if (event.key === "ArrowLeft") state.view.x += step;
  else if (event.key === "ArrowRight") state.view.x -= step;
  else if (event.key === "ArrowUp") state.view.y += step;
  else if (event.key === "ArrowDown") state.view.y -= step;
  else if (event.key === "+" || event.key === "=") zoomAt(1.2);
  else if (event.key === "-") zoomAt(.82);
  else if (event.key === "Home") fitView();
  else return;
  event.preventDefault();
  requestDraw();
});

resizeCanvas();
resetView();
loadRuns();
