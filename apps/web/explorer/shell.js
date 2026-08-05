import {
  ApiError,
  cashflowExportURL,
  createExperiment,
  getEdgeHistory,
  getManifest,
  getFirmDirectory,
  getQuarter,
  getRunStatus,
  getRuns,
  getRunSpec,
  getSectorMetadata,
  prefetchQuarter,
} from "./api.js";
import {
  adaptComparison,
  comparisonCoverageText,
  getComparison,
  getComparisonContext,
} from "./comparison.js";
import { adaptQuarter, coverageText, formatMoney, LAYERS, payloadBoolean } from "./model/edges.js";
import { renderComparisonPanel } from "./panels/comparison.js";
import { actorLabel, createMetadataIndex, metadataSearchOptions } from "./metadata.js";
import { renderInspector } from "./panels/inspector.js";
import { questionPatch, QUESTIONS } from "./panels/questions.js";
import { renderReconciliation } from "./panels/reconciliation.js";
import { renderRelationshipTable } from "./panels/table.js";
import { createCanvasRenderer } from "./render/canvas.js";
import { buildLayout } from "./render/layout.js";
import { createInitialState, createStore } from "./state.js";
import { parseURLState, replaceURLState } from "./url-state.js";
import { economyDescriptor } from "./views/economy.js";
import { defaultFirmFocus, firmsDescriptor } from "./views/firms.js";
import { defaultSectorFocus, sectorsDescriptor } from "./views/sectors.js";

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const urlAtBoot = new URLSearchParams(location.search);
const explicitEntry = urlAtBoot.toString().length > 0;
const store = createStore(createInitialState(parseURLState()));

const elements = {
  run: $("#run-select"),
  compare: $("#compare-select"),
  clearComparison: $("#clear-comparison"),
  datasetLabel: $("#dataset-label"),
  status: $("#ledger-status"),
  cloneRun: $("#clone-run"),
  questions: $("#question-shelf"),
  questionNote: $("#question-note"),
  altitude: $("#altitude-switch"),
  layers: $("#layer-filters"),
  layersAll: $("#layers-all"),
  actorForm: $("#actor-search"),
  actorQuery: $("#actor-query"),
  actorOptions: $("#actor-options"),
  coverageRange: $("#coverage-range"),
  coverageValue: $("#coverage-value"),
  coverageCopy: $("#coverage-copy"),
  canvas: $("#economy-canvas"),
  canvasSummary: $("#canvas-summary"),
  breadcrumbs: $("#breadcrumbs"),
  zoomValue: $("#zoom-value"),
  scaleBadge: $("#scale-badge"),
  directionToggle: $("#direction-toggle"),
  tooltip: $("#tooltip"),
  loading: $("#stage-loading"),
  loadingDetail: $("#loading-detail"),
  empty: $("#stage-empty"),
  emptyTitle: $("#empty-title"),
  emptyCopy: $("#empty-copy"),
  emptyAction: $("#empty-action"),
  clearFocus: $("#clear-focus"),
  inspector: {
    panel: $("#inspector"),
    kicker: $("#inspector-kicker"),
    title: $("#inspector-title"),
    subtitle: $("#inspector-subtitle"),
    badges: $("#evidence-badges"),
    metrics: $("#inspector-metrics"),
    reconciliation: $("#node-reconciliation"),
    history: $("#edge-history"),
    explanation: $("#inspector-explanation"),
    path: $("#aggregation-path"),
    drill: $("#drill-down"),
    rollup: $("#roll-up"),
  },
  comparison: $("#comparison-panel"),
  accounting: { root: $("#accounting-content"), dot: $("#accounting-dot") },
  table: {
    body: $("#relationship-rows"),
    count: $("#table-count"),
    caption: $("#table-caption"),
    filter: $("#table-filter"),
    prev: $("#table-prev"),
    next: $("#table-next"),
    page: $("#table-page"),
  },
  export: $("#export-link"),
  play: $("#play-toggle"),
  period: $("#period-label"),
  realization: $("#realization-label"),
  quarter: $("#quarter-range"),
  quarterCount: $("#quarter-count"),
  experiment: {
    form: $("#experiment-form"),
    shock: $("#experiment-shock"),
    magnitude: $("#experiment-magnitude"),
    magnitudeLabel: $("#experiment-magnitude-label"),
    duration: $("#experiment-duration"),
    durationLabel: $("#experiment-duration-label"),
    sector: $("#experiment-sector"),
    sectorLabel: $("#experiment-sector-label"),
    status: $("#experiment-status"),
    open: $("#experiment-open"),
    submit: $("#experiment-form button[type='submit']"),
  },
};

const renderer = createCanvasRenderer(elements.canvas, {
  onSelect: (selection) => selectEvidence(selection),
  onHover: (hover, point) => renderTooltip(hover, point),
  onCamera: (camera) => { elements.zoomValue.value = `${Math.round(camera.scale * 100)}%`; },
});

let metadataIndex = createMetadataIndex(null, []);
let actorSearch = [];
let playTimer = null;
let experimentPollTimer = null;

function humanDate(value) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat("en", { month: "short", day: "numeric", year: "numeric" }).format(date) : "saved run";
}

function setStatus(text, kind = "neutral") {
  elements.status.textContent = text;
  elements.status.className = `status-pill ${kind}`;
}

function showLoading(detail) {
  elements.loading.hidden = false;
  elements.loadingDetail.textContent = detail;
  elements.empty.hidden = true;
}

function hideLoading() {
  elements.loading.hidden = true;
}

function showEmpty(title, copy, action = "Clear filters") {
  hideLoading();
  elements.empty.hidden = false;
  elements.emptyTitle.textContent = title;
  elements.emptyCopy.textContent = copy;
  elements.emptyAction.textContent = action;
  elements.emptyAction.dataset.action = "";
}

function renderRuns(runs, selected) {
  elements.run.replaceChildren();
  for (const run of runs) {
    const option = document.createElement("option");
    option.value = run.run_id;
    const name = run.display_name || run.name || `${run.dataset_id} · ${run.scenario}`;
    const trace = payloadBoolean(run.cashflows_available) ? ` · ${run.cashflow_quarters} recorded states` : " · aggregate only";
    option.textContent = `${name}${trace} · ${humanDate(run.created_at)}`;
    option.selected = run.run_id === selected;
    elements.run.append(option);
  }
}

function runLabel(run, fallback = "Saved run") {
  if (!run) return fallback;
  return run.display_name || run.name || `${run.dataset_id} · ${run.scenario}`;
}

function renderCompareRuns(runs, state) {
  elements.compare.replaceChildren();
  const empty = document.createElement("option");
  empty.value = "";
  empty.textContent = "Compare…";
  empty.selected = !state.compare;
  elements.compare.append(empty);
  for (const run of runs) {
    if ((run.run_id === state.run && run.run_id !== state.compare) || !payloadBoolean(run.cashflows_available)) continue;
    const option = document.createElement("option");
    option.value = run.run_id;
    option.textContent = runLabel(run);
    option.selected = run.run_id === state.compare;
    elements.compare.append(option);
  }
  if (state.compare && !runs.some((run) => run.run_id === state.compare)) {
    const unavailable = document.createElement("option");
    unavailable.value = state.compare;
    unavailable.textContent = `Unavailable run ${state.compare}`;
    unavailable.selected = true;
    elements.compare.append(unavailable);
  }
  elements.clearComparison.hidden = !state.compare;
}

function renderLayerControls(state, model = null) {
  const active = new Set(state.layers);
  const all = active.size === 0;
  elements.layers.replaceChildren();
  for (const [id, definition] of Object.entries(LAYERS).sort((a, b) => a[1].order - b[1].order)) {
    const wrapper = document.createElement("div");
    wrapper.className = "layer-chip";
    const button = document.createElement("button");
    button.type = "button";
    button.dataset.layer = id;
    button.style.setProperty("--layer-color", definition.color);
    button.setAttribute("aria-pressed", String(all || active.has(id)));
    const capabilities = model?.capabilities || state.manifest?.capabilities || {};
    const capabilityAvailable = id === "capacity"
      ? payloadBoolean(capabilities.capacity_counterfactual ?? capabilities.potential_demand_signals)
      : id === "products" || id === "foreign"
        ? payloadBoolean(capabilities.sector_network ?? capabilities.business_counterparties)
        : payloadBoolean(capabilities.institution_flows);
    const available = !model || capabilityAvailable || model.edges.some((edge) => edge.layer === id) || active.has(id);
    button.disabled = !available && state.status === "ready";
    button.title = available ? definition.label : "This returned query has no relationships in this layer";
    const swatch = document.createElement("i");
    const label = document.createElement("span");
    label.textContent = definition.label;
    button.append(swatch, label);
    if (model) {
      const layerEdges = model.edges.filter((edge) => edge.layer === id);
      const domains = new Set(layerEdges.map((edge) => edge.scaleDomainId || [edge.measureKind, edge.units, edge.recognition, edge.valuationBasis].join("|")));
      const amount = document.createElement("small");
      amount.textContent = domains.size === 1 && layerEdges.length
        ? `${state.comparison ? "Δ " : ""}${formatMoney(layerEdges.reduce((sum, edge) => sum + Number(edge.amount || 0), 0), layerEdges[0].units)}`
        : layerEdges.length ? `${layerEdges.length.toLocaleString()} relationships` : "";
      if (amount.textContent) button.append(amount);
    }
    const solo = document.createElement("button");
    solo.type = "button";
    solo.dataset.soloLayer = id;
    solo.className = "layer-solo";
    solo.textContent = "Solo";
    solo.title = `Show only ${definition.label}`;
    solo.disabled = button.disabled;
    wrapper.append(button, solo);
    elements.layers.append(wrapper);
  }
}

function descriptorFor(state, model) {
  if (state.altitude === "sectors") return sectorsDescriptor(model, state.focus);
  if (state.altitude === "firms") return firmsDescriptor(model, state.focus);
  return economyDescriptor(model);
}

function comparisonExplorerModel(comparison, state) {
  const domainCoverage = comparison.domains.map((domain) => domain.coverage).filter(Boolean);
  const only = domainCoverage.length === 1 ? domainCoverage[0] : null;
  const countMatching = domainCoverage.reduce((sum, domain) => sum + Number(domain.count_matching || 0), 0);
  const countReturned = domainCoverage.reduce((sum, domain) => sum + Number(domain.count_returned || 0), 0);
  return {
    ...comparison,
    schema: "comparison-v1",
    edges: comparison.edges,
    coverage: {
      count_total: countMatching,
      count_matching: countMatching,
      count_returned: countReturned,
      amount_total: only ? Number(only.amount_matching || 0) : null,
      amount_matching: only ? Number(only.amount_matching || 0) : null,
      amount_returned: only ? Number(only.amount_returned || 0) : null,
      amount_compatible: Boolean(only),
      domain_count: domainCoverage.length,
      target: state.coverage,
      legacy_amount_unknown: false,
    },
    scaleDomains: { ...comparison.scaleDomains, ...comparison.sharedScaleDomains },
    diagnostics: comparison.diagnostics || {},
    stocks: {},
    rollups: [],
    transactionTotals: {},
    realization: state.manifest?.realization || {},
    timing: {},
    observability: {},
    capabilities: state.manifest?.capabilities || {},
    comparison,
  };
}

function renderBreadcrumbs(descriptor) {
  elements.breadcrumbs.replaceChildren();
  descriptor.breadcrumbs.forEach((crumb, index) => {
    if (index) {
      const separator = document.createElement("i");
      separator.textContent = "›";
      elements.breadcrumbs.append(separator);
    }
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = crumb.label;
    button.addEventListener("click", () => requestState({ altitude: crumb.altitude, focus: crumb.focus || null, question: null }, `Loading ${crumb.label}…`, true));
    elements.breadcrumbs.append(button);
  });
}

function renderActorOptions(model) {
  const firms = store.getState().manifest?.firm_directory
    || model.nodes.filter((node) => node.kind === "firm" || node.id.startsWith("firm:"));
  actorSearch = metadataSearchOptions(metadataIndex, firms);
  elements.actorOptions.replaceChildren();
  for (const optionData of actorSearch) {
    const option = document.createElement("option");
    option.value = optionData.value;
    option.dataset.id = optionData.id;
    elements.actorOptions.append(option);
  }
}

function renderReady(state) {
  const { model, scene } = state;
  const comparison = state.comparison || null;
  hideLoading();
  elements.empty.hidden = comparison || scene.edges.length > 0 || state.quarter === 0;
  if (!comparison && !scene.edges.length && state.quarter !== 0) {
    showEmpty("No relationships match this state", "The run loaded correctly, but no recorded relationship matches the selected layers, actor, and question.");
  }
  const descriptor = descriptorFor(state, model);
  elements.questionNote.textContent = comparison
    ? "The map shows Run B minus Run A for stable relationship IDs. Counts and value coverage remain separated by compatible measure."
    : state.question && QUESTIONS[state.question]
    ? QUESTIONS[state.question].note
    : "Choose a question or explore freely. Every claim is tied to the selected run and quarter.";
  renderBreadcrumbs(descriptor);
  const productDirection = state.direction === "product";
  const directionCopy = productDirection
    ? "Product-market arrows point from seller to buyer; other payments retain their recorded payer-to-recipient direction."
    : "Arrows follow each relationship's recorded money or payment direction.";
  const coverageCopy = comparison ? comparisonCoverageText(comparison) : coverageText(model.coverage);
  const comparisonCopy = comparison
    ? `${comparison.badge.label}. Mint solid relationships increased, mint long-dash relationships were added, coral solid relationships decreased, and coral short-dash relationships were removed.`
    : directionCopy;
  const lodCopy = scene.omittedEdges > 0
    ? `${scene.edges.length.toLocaleString()} relationships are drawn at this altitude; ${scene.omittedEdges.toLocaleString()} additional returned relationships remain available in the table${comparison ? "." : " and export."}`
    : "All returned relationships are drawn.";
  elements.canvasSummary.textContent = `${model.period}. ${descriptor.summary} ${coverageCopy} ${lodCopy} ${comparisonCopy}`;
  elements.directionToggle.setAttribute("aria-pressed", String(productDirection));
  elements.directionToggle.querySelector("span").textContent = productDirection ? "Product direction" : "Money direction";
  elements.period.textContent = comparison?.shock?.position === "onset" ? `⚡ ${model.period}` : model.period;
  const realization = model.realization || {};
  elements.realization.textContent = comparison
    ? `${comparison.badge.label} · ${comparison.realizationScope === "representative" ? "representative realization" : comparison.realizationScope}`
    : state.quarter === 0
    ? "Opening stock snapshot · no transaction arrows"
    : `Selected realization ${Number(realization.index || 1)}${realization.seed != null ? ` · seed ${Number(realization.seed)}` : ""}${realization.ensemble_size != null ? ` · ensemble ${Number(realization.ensemble_size)}` : ""}`;
  const quarters = normalizedQuarters(state.manifest);
  elements.quarter.min = String(Math.min(...quarters));
  elements.quarter.max = String(Math.max(...quarters));
  elements.quarter.value = String(state.quarter);
  elements.quarterCount.value = `${quarters.indexOf(Number(state.quarter)) + 1} / ${quarters.length}`;
  elements.coverageRange.value = String(Math.round(state.coverage * 100));
  elements.coverageValue.value = `${Math.round(state.coverage * 100)}%`;
  elements.coverageCopy.textContent = coverageCopy;
  elements.export.hidden = Boolean(comparison);
  if (!comparison) elements.export.href = cashflowExportURL(state, "csv");
  elements.clearFocus.hidden = !state.focus;
  elements.play.textContent = state.playing ? "Ⅱ" : "▶";
  elements.play.setAttribute("aria-label", state.playing ? "Pause recorded quarters" : "Play recorded quarters");
  for (const button of $$("[data-altitude]")) button.setAttribute("aria-pressed", String(button.dataset.altitude === state.altitude));
  for (const button of $$("[data-question]")) button.setAttribute("aria-pressed", String(button.dataset.question === state.question));
  renderLayerControls(state, model);
  renderActorOptions(model);
  const passed = renderReconciliation(elements.accounting, model);
  if (comparison) {
    setStatus(comparison.badge.kind === "paired" ? "Paired comparison" : "Descriptive comparison", comparison.badge.kind === "paired" ? "pass" : "warn");
  } else {
    setStatus(passed === true ? "Accounts reconcile" : passed === false ? "Accounting warning" : model.schema === "v1" ? "Legacy trace" : "Trace ready", passed === true ? "pass" : passed === false ? "fail" : "warn");
  }
  const tableResult = renderRelationshipTable(elements.table, model, {
    filter: state.tableFilter,
    page: state.tablePage,
    onSelect: selectEvidence,
  });
  if (tableResult.page !== state.tablePage) store.dispatch({ type: "MERGE", patch: { tablePage: tableResult.page } });
  const activeScaleDomains = Object.values(model.scaleDomains).filter((domain) => domain.max > 0);
  const stable = activeScaleDomains.length > 0 && activeScaleDomains.every((domain) => domain.stable === true);
  elements.scaleBadge.textContent = comparison
    ? stable
      ? "Run-wide shared A/B measure scales · square-root width"
      : "Current-view A/B scale · shared within this comparison only; not stable across quarters"
    : stable ? "Run-wide compatible-measure scales · square-root width" : "Legacy/current-query scale · widths are not cross-quarter comparable";
  renderer.setScene(scene, {
    fit: state.cameraIntent === "fit-scene",
    scaleDomains: model.scaleDomains,
    reducedMotion: state.motionReduced,
  });
  renderer.setSelection(state.selection);
  renderer.setPlaying(state.playing);
  if (state.cameraIntent) store.dispatch({ type: "CAMERA_COMMITTED" });
  renderInspector(elements.inspector, state.selection, model, state);
  const runA = state.runs.find((run) => run.run_id === state.run);
  const runB = state.runs.find((run) => run.run_id === state.compare);
  renderComparisonPanel(elements.comparison, comparison, {
    runALabel: runLabel(runA, state.run),
    runBLabel: runLabel(runB, state.compare),
    onSelect: selectEvidence,
  });
  if (comparison && state.selection) elements.comparison.hidden = true;
  if (state.selection) renderer.setReservedRight(340);
  else renderer.setReservedRight(comparison ? 445 : 0);
}

function normalizedQuarters(manifest) {
  const quarters = (manifest?.quarters || []).map(Number).filter(Number.isFinite).sort((a, b) => a - b);
  if (manifest && manifest.initial_period_has_flows === false && !quarters.includes(0) && String(manifest.schema_version || "").includes("v2")) quarters.unshift(0);
  return quarters.length ? quarters : [0];
}

async function loadRun(runId, { preserveRequestedState = true } = {}) {
  const runInfo = store.getState().runs.find((run) => run.run_id === runId) || null;
  store.dispatch({
    type: "SET_RUN",
    run: runId,
    runInfo,
    preserveFocus: preserveRequestedState,
    preserveRequestedState,
  });
  replaceURLState(store.getState());
  renderRuns(store.getState().runs, runId);
  renderCompareRuns(store.getState().runs, store.getState());
  showLoading("Loading run capabilities and dataset identities…");
  try {
    const [loadedManifest, spec] = await Promise.all([getManifest(runId), getRunSpec(runId)]);
    let manifest = loadedManifest;
    const manifestQuarters = normalizedQuarters(manifest);
    if (!Array.isArray(manifest.firm_directory) && manifestQuarters.some((quarter) => quarter > 0)) {
      try {
        const directoryPayload = await getFirmDirectory(runId, manifestQuarters.filter((quarter) => quarter > 0).at(-1));
        manifest = { ...manifest, firm_directory: directoryPayload.firms || [] };
      } catch {
        manifest = { ...manifest, firm_directory: [] };
      }
    }
    const metadata = await getSectorMetadata(manifest.dataset_id || spec.dataset_id);
    const current = store.getState();
    if (current.run !== runId) return;
    metadataIndex = createMetadataIndex(metadata, manifest.firm_directory || []);
    const quarters = normalizedQuarters(manifest);
    const requested = current.quarter;
    const quarter = requested != null && quarters.includes(Number(requested)) ? Number(requested) : quarters.at(-1);
    let altitude = current.altitude;
    if (!explicitEntry && !current.focus) altitude = "firms";
    store.dispatch({
      type: "MERGE",
      patch: {
        manifest,
        metadata,
        runSpec: spec,
        runInfo,
        quarter,
        altitude,
        requestRevision: current.requestRevision + 1,
        status: "loading-quarter",
        statusDetail: `Loading ${manifest.periods?.[quarters.indexOf(quarter)] || "recorded state"}…`,
        cameraIntent: "fit-scene",
      },
    });
    renderExperimentSectors(metadata);
    updateExperimentFields();
    elements.datasetLabel.textContent = `${metadata.dataset_id} · ${metadata.classification} · ${store.getState().compare ? "synchronized comparison" : "selected realization"}`;
    replaceURLState(store.getState());
    await loadQuarter();
  } catch (error) {
    if (error?.name === "AbortError") return;
    if (error instanceof ApiError && error.status === 404) {
      setStatus("Aggregate-only run", "warn");
      showEmpty("This historical run has no transaction trace", "Its aggregate simulation results remain available in the main workspace. Exact firm or sector relationships cannot be reconstructed honestly.", "Open results");
      elements.emptyAction.dataset.action = "results";
      store.dispatch({ type: "LOAD_ERROR", message: "Network capability unavailable for this historical run", error });
      return;
    }
    failLoad(error, store.getState().requestRevision);
  }
}

async function loadQuarter() {
  const requested = store.getState();
  const revision = requested.requestRevision;
  showLoading(requested.statusDetail || "Loading recorded economic relationships…");
  try {
    let payload;
    let comparison = null;
    let current;
    let model;
    if (requested.compare) {
      const context = await getComparisonContext(requested);
      current = store.getState();
      if (current.requestRevision !== revision) return;
      const comparisonFirmMap = new Map([
        ...(context.manifestA?.firm_directory || []),
        ...(context.manifestB?.firm_directory || []),
      ].map((firm) => [String(firm.id), firm]));
      const comparisonMetadataIndex = createMetadataIndex(current.metadata, [...comparisonFirmMap.values()]);
      comparison = adaptComparison(context.payload, current, comparisonMetadataIndex, {
        specA: context.specA,
        specB: context.specB,
        manifestA: context.manifestA,
        manifestB: context.manifestB,
      });
      payload = context.payload;
      model = comparisonExplorerModel(comparison, current);
    } else {
      payload = await getQuarter(requested);
      current = store.getState();
      if (current.requestRevision !== revision) return;
      const firms = current.manifest?.firm_directory || payload.firms || [];
      metadataIndex = createMetadataIndex(current.metadata, firms);
      model = adaptQuarter(payload, current, metadataIndex, current.manifest);
    }
    if (current.requestRevision !== revision) return;

    if (current.focus && current.focus !== "all" && !model.nodesById.has(current.focus)) {
      elements.questionNote.textContent = `The actor “${current.focus}” is unavailable at this scale, so the invalid focus was removed.`;
      requestState({ focus: null, selected: null }, "Removing an unavailable actor focus…", true);
      return;
    }

    if (!comparison && current.altitude === "firms" && !current.focus && explicitEntry === false) {
      const focus = defaultFirmFocus(model);
      if (focus) {
        requestState({ focus }, "Loading the deterministically selected largest employer…", true);
        return;
      }
    }
    const scene = buildLayout(model, current, metadataIndex);
    const selectedId = current.selected || current.selection?.id || null;
    const exactSelectedEdge = selectedId ? model.edges.find((edge) => edge.id === selectedId) : null;
    const selectedEdge = exactSelectedEdge || (selectedId
      ? model.edges
        .filter((edge) => edge.rollupId === selectedId || edge.parentIds?.includes(selectedId))
        .sort((a, b) => b.amount - a.amount || a.id.localeCompare(b.id))[0]
      : null);
    const selectedNode = selectedId ? model.nodesById.get(selectedId) : null;
    const selection = selectedEdge
      ? { type: "edge", ...selectedEdge }
      : selectedNode
        ? { type: "node", ...selectedNode }
        : null;
    store.dispatch({
      type: "LOAD_READY",
      revision,
      patch: {
        payload,
        model,
        scene,
        comparison,
        selection,
        selected: selection?.id || null,
      },
    });
    const ready = store.getState();
    renderReady(ready);
    if (ready.selection?.type === "edge" && !ready.comparison) {
      loadSelectionHistory(ready.selection);
    }
    replaceURLState(ready);
    prefetchAdjacent(ready);
    if (ready.playing) schedulePlayback();
  } catch (error) {
    if (error?.name === "AbortError") return;
    failLoad(error, revision);
  }
}

function failLoad(error, revision) {
  const message = error instanceof ApiError ? error.message : error?.message || "Unknown Explorer error";
  store.dispatch({ type: "LOAD_ERROR", revision, message, error });
  setStatus("Load failed", "fail");
  showEmpty("Unable to load this economic state", `${message}. The last valid scene is preserved where possible.`, "Retry");
  elements.emptyAction.dataset.action = "retry";
}

function requestState(patch, detail = "Updating the Explorer…", fit = false) {
  stopPlayback();
  const current = store.getState();
  store.dispatch({
    type: "MERGE",
    patch: {
      ...patch,
      selection: null,
      status: "loading-quarter",
      statusDetail: detail,
      requestRevision: current.requestRevision + 1,
      tablePage: 0,
      cameraIntent: fit ? "fit-scene" : current.cameraIntent,
      error: null,
    },
  });
  renderer.setSelection(null);
  replaceURLState(store.getState());
  loadQuarter();
}

function prefetchAdjacent(state) {
  const quarters = normalizedQuarters(state.manifest);
  const index = quarters.indexOf(Number(state.quarter));
  for (const quarter of [quarters[index - 1], quarters[index + 1]]) {
    if (quarter == null) continue;
    if (state.compare) {
      getComparison(state, {
        scope: `comparison-prefetch-${quarter}`,
        patch: { quarter },
      }).catch(() => null);
    } else {
      prefetchQuarter(state, quarter);
    }
  }
}

function stopPlayback() {
  if (playTimer) clearTimeout(playTimer);
  playTimer = null;
  if (store.getState().playing) store.dispatch({ type: "SET_PLAYING", playing: false });
  renderer.setPlaying(false);
}

function schedulePlayback() {
  if (playTimer) clearTimeout(playTimer);
  if (!store.getState().playing) return;
  playTimer = setTimeout(() => {
    const state = store.getState();
    if (!state.playing || state.status !== "ready") return;
    const quarters = normalizedQuarters(state.manifest);
    const index = quarters.indexOf(Number(state.quarter));
    const next = quarters[(index + 1) % quarters.length];
    store.dispatch({ type: "SET_QUARTER", quarter: next, fit: false });
    replaceURLState(store.getState());
    loadQuarter();
  }, 1250);
}

function selectEvidence(selection) {
  store.dispatch({
    type: "MERGE",
    patch: { selection: selection || null, selected: selection?.id || null },
  });
  renderer.setSelection(selection);
  const state = store.getState();
  replaceURLState(state);
  renderInspector(elements.inspector, selection, state.model, state);
  if (state.comparison) elements.comparison.hidden = Boolean(selection);
  renderer.setReservedRight(selection ? 340 : state.comparison ? 445 : 0);
  if (selection?.type === "edge" && !state.comparison) {
    loadSelectionHistory(selection);
  }
}

async function loadSelectionHistory(selection) {
  const requested = store.getState();
  if (!selection?.id || requested.comparison || Array.isArray(selection.history)) return;
  const run = requested.run;
  const edgeId = selection.id;
  try {
    const history = await getEdgeHistory(
      requested,
      edgeId,
      normalizedQuarters(requested.manifest),
    );
    const current = store.getState();
    if (current.run !== run || current.selection?.id !== edgeId || current.comparison) return;
    const updated = { ...current.selection, history };
    store.dispatch({ type: "MERGE", patch: { selection: updated } });
    renderInspector(elements.inspector, updated, current.model, store.getState());
  } catch (error) {
    const current = store.getState();
    if (current.run !== run || current.selection?.id !== edgeId || current.comparison) return;
    const updated = { ...current.selection, historyError: error.message || "request failed" };
    store.dispatch({ type: "MERGE", patch: { selection: updated } });
    renderInspector(elements.inspector, updated, current.model, store.getState());
  }
}

function renderTooltip(hover, point = {}) {
  if (!hover) {
    elements.tooltip.hidden = true;
    return;
  }
  elements.tooltip.replaceChildren();
  const title = document.createElement("strong");
  title.textContent = hover.type === "edge" ? hover.label : hover.label || hover.id;
  elements.tooltip.append(title);
  if (hover.type === "edge") {
    const amount = document.createElement("span");
    amount.className = "amount";
    amount.textContent = hover.deltaClass
      ? `Δ ${hover.delta > 0 ? "+" : ""}${formatMoney(hover.delta, hover.units)}`
      : formatMoney(hover.amount, hover.units);
    const route = document.createElement("div");
    route.className = "meta";
    route.textContent = hover.deltaClass
      ? `${hover.sourceLabel} → ${hover.targetLabel} · ${hover.deltaClass} · A ${formatMoney(hover.amountA, hover.units)} · B ${formatMoney(hover.amountB, hover.units)}`
      : `${hover.sourceLabel} → ${hover.targetLabel} · ${LAYERS[hover.layer]?.label || hover.layer}`;
    elements.tooltip.append(amount, route);
  } else {
    const meta = document.createElement("div");
    meta.className = "meta";
    meta.textContent = hover.kind === "firm" ? "Synthetic model firm" : hover.kind === "sector" ? "Dataset-scoped sector" : "Economic institution";
    elements.tooltip.append(meta);
  }
  elements.tooltip.hidden = false;
  const box = elements.tooltip.getBoundingClientRect();
  elements.tooltip.style.left = `${Math.min(innerWidth - box.width - 9, (point.clientX || 0) + 13)}px`;
  elements.tooltip.style.top = `${Math.min(innerHeight - box.height - 9, (point.clientY || 0) + 13)}px`;
}

function defaultFocuses(state) {
  return {
    defaultFirm: state.focus?.startsWith("firm:") ? state.focus : defaultFirmFocus(state.model),
    defaultSector: state.focus?.startsWith("sector:") ? state.focus : defaultSectorFocus(state.model),
    capabilities: state.model?.capabilities || state.manifest?.capabilities || {},
  };
}

function focusForAltitude(state, altitude) {
  if (altitude === "economy") return null;
  const focus = state.focus && state.focus !== "all" ? state.focus : null;
  if (!focus) return null;
  const firms = state.manifest?.firm_directory || [];
  if (altitude === "sectors" && focus.startsWith("firm:")) {
    const firm = firms.find((item) => String(item.id) === focus);
    return firm?.sector == null ? null : `sector:${Number(firm.sector)}`;
  }
  if (altitude === "firms" && focus.startsWith("sector:")) {
    const sector = Number(focus.slice(7));
    const candidates = firms
      .filter((firm) => Number(firm.sector) === sector)
      .sort((a, b) => Number(b.metrics?.employment || 0) - Number(a.metrics?.employment || 0)
        || String(a.id).localeCompare(String(b.id), undefined, { numeric: true }));
    return candidates[0]?.id ? String(candidates[0].id) : null;
  }
  return focus;
}

function activateQuestion(question) {
  const state = store.getState();
  if (!state.model) return;
  if (state.comparison) {
    elements.questionNote.textContent = "Question presets are single-run evidence journeys. Exit comparison before opening one.";
    return;
  }
  const result = questionPatch(question, state, defaultFocuses(state));
  elements.questionNote.textContent = result.note;
  if (!result.supported) {
    for (const button of $$("[data-question]")) button.setAttribute("aria-pressed", String(button.dataset.question === question));
    return;
  }
  requestState({ ...result.patch, parent: null, selected: null }, `Opening “${QUESTIONS[question].title}” …`, true);
}

function findActor(query) {
  const normalized = String(query || "").trim().toLowerCase();
  if (!normalized) return null;
  const exact = actorSearch.find((option) => option.value.toLowerCase() === normalized);
  if (exact) return exact;
  const contained = actorSearch.find((option) => option.value.toLowerCase().includes(normalized));
  if (contained) return contained;
  if (/^\d+$/.test(normalized)) return { id: `firm:${Number(normalized)}`, type: "firm" };
  return null;
}

function renderExperimentSectors(metadata) {
  elements.experiment.sector.replaceChildren();
  for (const sector of metadata?.sectors || []) {
    const option = document.createElement("option");
    option.value = String(sector.index);
    option.textContent = `${sector.code} · ${sector.short_label || sector.label}`;
    elements.experiment.sector.append(option);
  }
}

function updateExperimentFields() {
  const type = elements.experiment.shock.value;
  const durationVisible = type === "interest_rate" || type === "consumption";
  const sectorVisible = type === "sector_productivity";
  const settings = {
    interest_rate: { label: "Annual rate change (percentage points)", min: -89.75, max: 100, step: .25, value: 1 },
    productivity: { label: "Economy-wide productivity multiplier", min: .01, max: 10, step: .01, value: .95 },
    consumption: { label: "Consumption multiplier", min: .01, max: 10, step: .01, value: .95 },
    sector_productivity: { label: "Selected-sector productivity multiplier", min: .01, max: 10, step: .01, value: .95 },
  }[type];
  elements.experiment.magnitudeLabel.textContent = settings.label;
  elements.experiment.magnitude.min = String(settings.min);
  elements.experiment.magnitude.max = String(settings.max);
  elements.experiment.magnitude.step = String(settings.step);
  elements.experiment.magnitude.value = String(settings.value);
  elements.experiment.duration.hidden = !durationVisible;
  elements.experiment.durationLabel.hidden = !durationVisible;
  elements.experiment.sector.hidden = !sectorVisible;
  elements.experiment.sectorLabel.hidden = !sectorVisible;
  const horizon = Number(store.getState().runSpec?.sim?.T || 1);
  elements.experiment.duration.max = String(Math.max(1, horizon));
  elements.experiment.duration.value = String(Math.min(4, Math.max(1, horizon)));
  elements.experiment.submit.disabled = false;
  elements.experiment.status.textContent = "Paired eligibility will be verified fail-closed after both runs complete. Same-mode replay is evaluated under the comparison's declared numeric tolerance.";
  elements.experiment.open.hidden = true;
}

function experimentShock() {
  const type = elements.experiment.shock.value;
  const magnitude = Number(elements.experiment.magnitude.value);
  if (type === "interest_rate") {
    return {
      type,
      annual_rate: magnitude / 100,
      final_time: Number(elements.experiment.duration.value),
    };
  }
  if (type === "consumption") {
    return {
      type,
      multiplier: magnitude,
      final_time: Number(elements.experiment.duration.value),
    };
  }
  if (type === "sector_productivity") {
    return {
      type,
      multiplier: magnitude,
      sector: Number(elements.experiment.sector.value),
    };
  }
  return { type, multiplier: magnitude };
}

function comparisonHref(baseline, treatment) {
  const params = new URLSearchParams(location.search);
  params.set("run", baseline);
  params.set("compare", treatment);
  params.delete("selected");
  params.delete("parent");
  return `/explorer/?${params}`;
}

async function pollExperiment(baseline, treatment) {
  if (experimentPollTimer) clearTimeout(experimentPollTimer);
  try {
    const status = await getRunStatus(treatment, `experiment-status-${treatment}`);
    const progress = Math.max(0, Math.min(1, Number(status.progress || 0)));
    const terminalState = String(status.state || "").toLowerCase();
    if (["done", "complete", "completed"].includes(terminalState)) {
      elements.experiment.status.textContent = "Treatment complete. The comparison will synchronize quarter, scale, focus, and coverage.";
      elements.experiment.open.href = comparisonHref(baseline, treatment);
      elements.experiment.open.hidden = false;
      const runs = await getRuns();
      const done = runs.filter((run) => run.state === "done");
      store.dispatch({ type: "MERGE", patch: { runs: done } });
      renderRuns(done, store.getState().run);
      renderCompareRuns(done, store.getState());
      return;
    }
    if (["error", "failed", "cancelled", "canceled"].includes(terminalState)) {
      elements.experiment.status.textContent = `Treatment ${terminalState}: ${status.message || "worker error"}. Adjust the intervention or clone the baseline and retry.`;
      return;
    }
    elements.experiment.status.textContent = `${status.message || "Treatment running"} · ${Math.round(progress * 100)}%. Baseline and treatment specifications remain visible while this completes.`;
    experimentPollTimer = setTimeout(() => pollExperiment(baseline, treatment), 1500);
  } catch (error) {
    elements.experiment.status.textContent = `Unable to read treatment progress: ${error.message}`;
  }
}

async function launchExperiment(event) {
  event.preventDefault();
  if (!elements.experiment.form.reportValidity()) return;
  const state = store.getState();
  if (!state.run) return;
  elements.experiment.submit.disabled = true;
  elements.experiment.open.hidden = true;
  elements.experiment.status.textContent = "Validating the matched baseline and treatment specifications…";
  try {
    const shock = experimentShock();
    const experiment = await createExperiment({
      name: `${runLabel(state.runInfo, "Saved run")} · ${shock.type.replaceAll("_", " ")}`,
      baseline_run_id: state.run,
      intervention_diff: { shock },
    });
    const baseline = String(experiment.run_ids.baseline);
    const treatment = String(experiment.run_ids.treatment);
    elements.experiment.status.textContent = "Treatment queued with the baseline horizon, ensemble, seed schedule, and trace policy.";
    await pollExperiment(baseline, treatment);
  } catch (error) {
    elements.experiment.status.textContent = `Experiment was not launched: ${error.message}`;
  } finally {
    elements.experiment.submit.disabled = false;
  }
}

function wireEvents() {
  elements.run.addEventListener("change", () => {
    store.dispatch({ type: "MERGE", patch: { compare: null, comparison: null } });
    loadRun(elements.run.value, { preserveRequestedState: false });
  });
  elements.compare.addEventListener("change", () => {
    const compare = elements.compare.value || null;
    requestState({ compare, comparison: null, question: null, parent: null, selected: null }, compare ? "Joining complete edge tables for a synchronized comparison…" : "Returning to the selected run…", true);
    renderCompareRuns(store.getState().runs, store.getState());
  });
  elements.clearComparison.addEventListener("click", () => {
    requestState({ compare: null, comparison: null, parent: null, selected: null }, "Returning to the selected run…", true);
    renderCompareRuns(store.getState().runs, store.getState());
  });
  elements.cloneRun.addEventListener("click", () => {
    const state = store.getState();
    location.href = `/?open_run=${encodeURIComponent(state.run || "")}`;
  });
  elements.experiment.shock.addEventListener("change", updateExperimentFields);
  elements.experiment.form.addEventListener("submit", launchExperiment);
  elements.altitude.addEventListener("click", (event) => {
    const button = event.target.closest("[data-altitude]");
    if (!button) return;
    const altitude = button.dataset.altitude;
    const state = store.getState();
    requestState({ altitude, focus: focusForAltitude(state, altitude), question: null, parent: null, selected: null }, `Loading ${altitude} scale…`, true);
  });
  elements.layers.addEventListener("click", (event) => {
    const solo = event.target.closest("[data-solo-layer]");
    if (solo && !solo.disabled) {
      requestState({ layers: [solo.dataset.soloLayer], question: null }, `Showing only ${LAYERS[solo.dataset.soloLayer]?.label || solo.dataset.soloLayer}…`, false);
      return;
    }
    const button = event.target.closest("[data-layer]");
    if (!button || button.disabled) return;
    const layer = button.dataset.layer;
    const current = store.getState().layers;
    let next;
    if (!current.length) next = [layer];
    else if (current.includes(layer)) next = current.filter((item) => item !== layer);
    else next = [...current, layer];
    requestState({ layers: next, question: null }, "Applying economic layer filters…", false);
  });
  elements.layersAll.addEventListener("click", () => requestState({ layers: [], question: null }, "Restoring all economic layers…", false));
  elements.directionToggle.addEventListener("click", () => {
    const direction = store.getState().direction === "money" ? "product" : "money";
    requestState({ direction }, `Showing ${direction} direction…`, false);
  });
  elements.questions.addEventListener("click", (event) => {
    const button = event.target.closest("[data-question]");
    if (button) activateQuestion(button.dataset.question);
  });
  elements.actorForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const match = findActor(elements.actorQuery.value);
    if (!match) {
      elements.actorQuery.setCustomValidity("No matching sector or synthetic firm was found in this returned run state.");
      elements.actorQuery.reportValidity();
      return;
    }
    elements.actorQuery.setCustomValidity("");
    requestState({ altitude: match.type === "sector" ? "sectors" : "firms", focus: match.id, question: null, parent: null, selected: null }, `Loading ${match.value || match.id}…`, true);
  });
  elements.coverageRange.addEventListener("input", () => {
    elements.coverageValue.value = `${elements.coverageRange.value}%`;
  });
  elements.coverageRange.addEventListener("change", () => requestState({ coverage: Number(elements.coverageRange.value) / 100 }, "Applying value-coverage target…", false));
  elements.quarter.addEventListener("input", () => {
    stopPlayback();
    const quarter = Number(elements.quarter.value);
    store.dispatch({ type: "SET_QUARTER", quarter, fit: false });
    replaceURLState(store.getState());
    loadQuarter();
  });
  elements.play.addEventListener("click", () => {
    const playing = !store.getState().playing;
    store.dispatch({ type: "SET_PLAYING", playing });
    renderer.setPlaying(playing);
    renderReady(store.getState());
    if (playing) schedulePlayback();
    else stopPlayback();
  });
  $("#zoom-in").addEventListener("click", () => renderer.zoom(1.22));
  $("#zoom-out").addEventListener("click", () => renderer.zoom(.82));
  $("#fit-view").addEventListener("click", () => renderer.fit());
  elements.clearFocus.addEventListener("click", () => requestState({ focus: "all", question: null }, "Revealing wider economic context…", true));
  $("#close-inspector").addEventListener("click", () => {
    selectEvidence(null);
    elements.canvas.focus();
  });
  elements.table.filter.addEventListener("input", () => {
    const state = store.getState();
    store.dispatch({ type: "MERGE", patch: { tableFilter: elements.table.filter.value, tablePage: 0 } });
    renderRelationshipTable(elements.table, state.model, { filter: elements.table.filter.value, page: 0, onSelect: selectEvidence });
  });
  elements.table.prev.addEventListener("click", () => {
    const state = store.getState();
    const page = Math.max(0, state.tablePage - 1);
    store.dispatch({ type: "MERGE", patch: { tablePage: page } });
    renderRelationshipTable(elements.table, state.model, { filter: state.tableFilter, page, onSelect: selectEvidence });
  });
  elements.table.next.addEventListener("click", () => {
    const state = store.getState();
    const page = state.tablePage + 1;
    const result = renderRelationshipTable(elements.table, state.model, { filter: state.tableFilter, page, onSelect: selectEvidence });
    store.dispatch({ type: "MERGE", patch: { tablePage: result.page } });
  });
  elements.emptyAction.addEventListener("click", () => {
    const action = elements.emptyAction.dataset.action;
    if (action === "results") location.href = "/";
    else if (action === "retry") loadQuarter();
    else requestState({ layers: [], question: null }, "Clearing filters…", true);
  });
  elements.inspector.drill.addEventListener("click", () => {
    const state = store.getState();
    if (state.comparison) return;
    const selection = state.selection;
    if (!selection) return;
    if (selection.type === "edge") {
      if (state.altitude === "firms") return;
      const altitude = state.altitude === "economy" ? "sectors" : "firms";
      requestState({
        altitude,
        focus: null,
        parent: selection.id,
        selected: selection.id,
      }, "Loading the exact recorded children of this relationship…", true);
      return;
    }
    const altitude = selection.id.startsWith("firm:") ? "firms" : state.altitude === "economy" ? "sectors" : "firms";
    requestState({ altitude, focus: selection.id, parent: null, selected: null }, "Drilling into the selected actor…", true);
  });
  elements.inspector.rollup.addEventListener("click", () => {
    const state = store.getState();
    if (state.comparison) return;
    const selection = state.selection;
    const parentId = selection?.type === "edge"
      ? selection.rollupId || selection.parentIds?.[0] || null
      : null;
    requestState({
      altitude: state.altitude === "firms" ? "sectors" : "economy",
      focus: null,
      parent: null,
      selected: parentId,
    }, "Reconciling to the recorded parent relationship…", true);
  });
  addEventListener("popstate", () => {
    const parsed = parseURLState();
    const state = store.getState();
    if (parsed.run && parsed.run !== state.run) loadRun(parsed.run);
    else requestState(parsed, "Restoring the copied Explorer state…", true);
  });
}

async function boot() {
  wireEvents();
  renderLayerControls(store.getState());
  showLoading("Finding compatible traced runs…");
  try {
    const runs = await getRuns();
    const state = store.getState();
    const done = runs.filter((run) => run.state === "done");
    store.dispatch({ type: "MERGE", patch: { runs: done } });
    if (!done.length) {
      showEmpty("No completed simulations yet", "Run a simulation in the main workspace, then return to explore its recorded economy.", "Run a simulation");
      elements.emptyAction.dataset.action = "results";
      setStatus("No runs", "warn");
      return;
    }
    const requested = done.find((run) => run.run_id === state.run);
    const compatible = done.find((run) => payloadBoolean(run.cashflows_available));
    const selected = requested || compatible || done[0];
    renderRuns(done, selected.run_id);
    await loadRun(selected.run_id);
  } catch (error) {
    failLoad(error, null);
  }
}

boot();
