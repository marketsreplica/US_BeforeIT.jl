const cache = new Map();
const controllers = new Map();
const CACHE_LIMIT = 18;

function cacheGet(key) {
  if (!cache.has(key)) return undefined;
  const value = cache.get(key);
  cache.delete(key);
  cache.set(key, value);
  return value;
}

function cacheSet(key, value) {
  if (cache.has(key)) cache.delete(key);
  cache.set(key, value);
  while (cache.size > CACHE_LIMIT) cache.delete(cache.keys().next().value);
}

export class ApiError extends Error {
  constructor(message, { status = 0, details = null, url = "" } = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.details = details;
    this.url = url;
  }
}

function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}

function abortScope(scope) {
  controllers.get(scope)?.abort();
  controllers.delete(scope);
}

export async function fetchJSON(url, { scope = "default", cacheKey = null, signal = null } = {}) {
  if (cacheKey) {
    const cached = cacheGet(cacheKey);
    if (cached !== undefined) return cached;
  }
  if (!signal) {
    abortScope(scope);
    const controller = new AbortController();
    controllers.set(scope, controller);
    signal = controller.signal;
  }
  let response;
  try {
    response = await fetch(url, {
      headers: { Accept: "application/json" },
      cache: "no-store",
      signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    throw new ApiError(`Unable to reach the local simulation server`, { url, details: error?.message });
  }
  let payload = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }
  if (!response.ok) {
    throw new ApiError(payload?.error || `Request failed with HTTP ${response.status}`, {
      status: response.status,
      details: payload?.details,
      url,
    });
  }
  const immutable = deepFreeze(payload);
  if (cacheKey) cacheSet(cacheKey, immutable);
  return immutable;
}

export async function postJSON(url, body, { scope = "write" } = {}) {
  abortScope(scope);
  const controller = new AbortController();
  controllers.set(scope, controller);
  let response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { Accept: "application/json", "Content-Type": "application/json" },
      body: JSON.stringify(body),
      cache: "no-store",
      signal: controller.signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    throw new ApiError("Unable to reach the local simulation server", { url, details: error?.message });
  } finally {
    if (controllers.get(scope) === controller) controllers.delete(scope);
  }
  let payload = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }
  if (!response.ok) {
    throw new ApiError(payload?.error || `Request failed with HTTP ${response.status}`, {
      status: response.status,
      details: payload?.details,
      url,
    });
  }
  return deepFreeze(payload);
}

export function cancelRequests(scope) {
  abortScope(scope);
}

export function clearRunCache(runId = null) {
  for (const key of cache.keys()) {
    if (!runId || key.includes(`:${runId}:`)) cache.delete(key);
  }
}

export function getRuns() {
  return fetchJSON("/api/runs", { scope: "runs" });
}

export function getRunStatus(runId, scope = "run-status") {
  return fetchJSON(`/api/runs/${encodeURIComponent(runId)}/status`, { scope });
}

export function createExperiment(request) {
  return postJSON("/api/experiments", request, { scope: "create-experiment" });
}

export function getManifest(runId) {
  return fetchJSON(`/api/runs/${encodeURIComponent(runId)}/cashflows`, {
    scope: "manifest",
    cacheKey: `manifest:${runId}:v2`,
  });
}

export function getRunSpec(runId) {
  return fetchJSON(`/api/runs/${encodeURIComponent(runId)}/spec`, {
    scope: "spec",
    cacheKey: `spec:${runId}:v2`,
  });
}

export function getSectorMetadata(datasetId) {
  return fetchJSON(`/api/datasets/${encodeURIComponent(datasetId)}/sector-metadata`, {
    scope: "metadata",
    cacheKey: `metadata:${datasetId}:v1`,
  });
}

export function getFirmDirectory(runId, quarter) {
  const params = new URLSearchParams({
    quarter: String(quarter),
    detail: "firm",
    level: "firm",
    limit: "1",
    sector_limit: "1",
    page_size: "1",
    coverage: "0.5",
  });
  return fetchJSON(`/api/runs/${encodeURIComponent(runId)}/cashflows?${params}`, {
    scope: "firm-directory",
    cacheKey: `firm-directory:${runId}:${quarter}`,
  });
}

export function quarterQuery(state, quarter = state.quarter) {
  const params = new URLSearchParams();
  const level = {
    economy: "macro",
    sectors: "sector",
    firms: "firm",
  }[state.altitude] || "macro";
  params.set("quarter", String(quarter));
  params.set("level", level);
  params.set("detail", state.altitude === "firms" ? "firm" : "sector");
  params.set("coverage", String(state.coverage));
  params.set("page_size", state.altitude === "firms" ? "1600" : "1000");
  params.set("limit", state.altitude === "firms" ? "1600" : "600");
  params.set("sector_limit", "1000");
  params.set("direction", state.direction || "money");
  if (state.layers?.length) params.set("layers", state.layers.join(","));
  if (state.focus && state.focus !== "all") {
    params.set("focus", state.focus);
    if (state.focus.startsWith("firm:")) params.set("firm_id", state.focus.slice(5));
  }
  if (state.parent) params.set("parent_id", state.parent);
  if (!state.layers?.length || state.layers.includes("capacity")) params.set("include_potential", "true");
  if (state.question) params.set("question", state.question);
  return params;
}

export function getQuarter(state, quarter = state.quarter, { scope = "quarter" } = {}) {
  const params = quarterQuery(state, quarter);
  const url = `/api/runs/${encodeURIComponent(state.run)}/cashflows?${params}`;
  const key = `quarter:${state.run}:${params.toString()}`;
  return fetchJSON(url, { scope, cacheKey: key });
}

export async function getEdgeHistory(state, edgeId, quarters) {
  const level = { economy: "macro", sectors: "sector", firms: "firm" }[state.altitude] || "macro";
  return Promise.all((quarters || []).map(async (quarter) => {
    const params = new URLSearchParams({
      quarter: String(quarter),
      level,
      detail: state.altitude === "firms" ? "firm" : "sector",
      edge_id: String(edgeId),
      coverage: "1",
      page_size: "2",
      limit: "2",
      sector_limit: "2",
      direction: "money",
      include_potential: "true",
    });
    const url = `/api/runs/${encodeURIComponent(state.run)}/cashflows?${params}`;
    const payload = await fetchJSON(url, {
      scope: `edge-history-${quarter}`,
      cacheKey: `edge-history:${state.run}:${edgeId}:${quarter}:${level}`,
    });
    const edge = payload.edges?.find((item) => String(item.id) === String(edgeId));
    return {
      quarter: Number(quarter),
      period: String(payload.period || `Quarter ${quarter}`),
      amount: edge ? Number(edge.amount || 0) : 0,
      present: Boolean(edge),
    };
  }));
}

export function prefetchQuarter(state, quarter) {
  if (quarter == null) return Promise.resolve(null);
  const params = quarterQuery(state, quarter);
  const url = `/api/runs/${encodeURIComponent(state.run)}/cashflows?${params}`;
  const key = `quarter:${state.run}:${params.toString()}`;
  const cached = cacheGet(key);
  if (cached !== undefined) return Promise.resolve(cached);
  const controller = new AbortController();
  return fetchJSON(url, { scope: `prefetch-${quarter}`, cacheKey: key, signal: controller.signal }).catch(() => null);
}

export function cashflowExportURL(state, format = "csv") {
  const params = quarterQuery(state);
  params.delete("page_size");
  params.delete("limit");
  params.delete("sector_limit");
  params.delete("coverage");
  params.set("format", format);
  return `/api/runs/${encodeURIComponent(state.run)}/cashflows/export?${params}`;
}
