export const DEFAULT_URL_STATE = Object.freeze({
  run: null,
  quarter: null,
  altitude: "economy",
  focus: null,
  selected: null,
  parent: null,
  layers: [],
  direction: "money",
  coverage: 0.85,
  view: "map",
  compare: null,
  question: null,
});

const ALTITUDES = new Set(["economy", "sectors", "firms"]);
const DIRECTIONS = new Set(["money", "product"]);
const VIEWS = new Set(["map", "table"]);
const ID_PATTERN = /^[a-z0-9][a-z0-9:_-]{0,255}$/i;

function boundedNumber(value, fallback, minimum, maximum) {
  if (value == null || value === "") return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(maximum, Math.max(minimum, number)) : fallback;
}

function safeId(value) {
  if (!value) return null;
  const text = String(value).trim();
  return ID_PATTERN.test(text) ? text : null;
}

export function parseURLState(search = globalThis.location?.search || "") {
  const params = new URLSearchParams(search);
  const quarterValue = params.get("q");
  const quarter = quarterValue == null ? null : Math.max(0, Math.trunc(Number(quarterValue)));
  const altitudeValue = params.get("altitude");
  const directionValue = params.get("direction");
  const viewValue = params.get("view");
  const layers = (params.get("layers") || "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item, index, all) => item && ID_PATTERN.test(item) && all.indexOf(item) === index);

  return {
    run: safeId(params.get("run")),
    quarter: Number.isFinite(quarter) ? quarter : null,
    altitude: ALTITUDES.has(altitudeValue) ? altitudeValue : DEFAULT_URL_STATE.altitude,
    focus: safeId(params.get("focus")),
    selected: safeId(params.get("selected")),
    parent: safeId(params.get("parent")),
    layers,
    direction: DIRECTIONS.has(directionValue) ? directionValue : DEFAULT_URL_STATE.direction,
    coverage: boundedNumber(params.get("coverage"), DEFAULT_URL_STATE.coverage, 0.5, 1),
    view: VIEWS.has(viewValue) ? viewValue : DEFAULT_URL_STATE.view,
    compare: safeId(params.get("compare")),
    question: safeId(params.get("question")),
  };
}

export function serializeURLState(state) {
  const params = new URLSearchParams();
  if (state.run) params.set("run", state.run);
  if (state.quarter != null) params.set("q", String(Math.max(0, Math.trunc(state.quarter))));
  if (state.altitude && state.altitude !== DEFAULT_URL_STATE.altitude) params.set("altitude", state.altitude);
  if (state.focus) params.set("focus", state.focus);
  if (state.selected) params.set("selected", state.selected);
  if (state.parent) params.set("parent", state.parent);
  if (state.layers?.length) params.set("layers", [...new Set(state.layers)].sort().join(","));
  if (state.direction && state.direction !== DEFAULT_URL_STATE.direction) params.set("direction", state.direction);
  if (Number.isFinite(state.coverage) && Math.abs(state.coverage - DEFAULT_URL_STATE.coverage) > 1e-9) {
    params.set("coverage", Number(state.coverage).toFixed(2).replace(/0+$/, "").replace(/\.$/, ""));
  }
  if (state.view && state.view !== DEFAULT_URL_STATE.view) params.set("view", state.view);
  if (state.compare) params.set("compare", state.compare);
  if (state.question) params.set("question", state.question);
  const query = params.toString();
  return query ? `?${query}` : "";
}

export function replaceURLState(state) {
  if (!globalThis.history || !globalThis.location) return;
  const next = `${globalThis.location.pathname}${serializeURLState(state)}${globalThis.location.hash || ""}`;
  globalThis.history.replaceState(null, "", next);
}

export function pushURLState(state) {
  if (!globalThis.history || !globalThis.location) return;
  const next = `${globalThis.location.pathname}${serializeURLState(state)}${globalThis.location.hash || ""}`;
  globalThis.history.pushState(null, "", next);
}
