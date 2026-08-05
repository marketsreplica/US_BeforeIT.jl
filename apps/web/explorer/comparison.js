import { fetchJSON } from "./api.js";
import { actorLabel, humanizeId } from "./metadata.js";

const LEVEL_BY_ALTITUDE = Object.freeze({
  economy: "macro",
  sectors: "sector",
  firms: "firm",
});

export const COMPARISON_SYNC_KEYS = Object.freeze([
  "quarter",
  "altitude",
  "layers",
  "focus",
  "direction",
  "coverage",
]);

export const DELTA_CLASSES = Object.freeze([
  "added",
  "removed",
  "increased",
  "decreased",
  "unchanged",
]);

const DELTA_CLASS_SET = new Set(DELTA_CLASSES);

export class ComparisonContractError extends Error {
  constructor(message, details = null) {
    super(message);
    this.name = "ComparisonContractError";
    this.details = details;
  }
}

function finite(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function nullableFinite(value) {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null);
}

function uniqueStrings(values) {
  const list = Array.isArray(values) ? values : values == null ? [] : [values];
  return [...new Set(list.map(String).map((value) => value.trim()).filter(Boolean))];
}

function safeRunId(value, name) {
  const id = String(value || "").trim();
  if (!id) throw new ComparisonContractError(`${name} is required for a comparison`);
  return id;
}

function normalizedAltitude(value) {
  return Object.hasOwn(LEVEL_BY_ALTITUDE, value) ? value : "economy";
}

/**
 * Return the one shared state slice used by both sides of a comparison.
 * There is deliberately no independent A/B quarter, altitude, layer, or focus state.
 */
export function comparisonStateSlice(state, patch = {}) {
  const merged = { ...state, ...patch };
  const altitude = normalizedAltitude(merged.altitude);
  return Object.freeze({
    runA: safeRunId(merged.run, "Baseline run"),
    runB: safeRunId(merged.compare, "Comparison run"),
    quarter: Math.max(0, Math.trunc(finite(merged.quarter))),
    altitude,
    level: LEVEL_BY_ALTITUDE[altitude],
    layers: uniqueStrings(merged.layers).sort(),
    focus: merged.focus && merged.focus !== "all" ? String(merged.focus) : null,
    direction: merged.direction === "product" ? "product" : "money",
    coverage: Math.max(0.5, Math.min(1, finite(merged.coverage, 0.85))),
    recognition: merged.recognition ? String(merged.recognition) : null,
    minAmount: merged.minAmount == null ? null : Math.max(0, finite(merged.minAmount)),
  });
}

export function comparisonQuery(state, patch = {}) {
  const synchronized = comparisonStateSlice(state, patch);
  const params = new URLSearchParams({
    run_a: synchronized.runA,
    run_b: synchronized.runB,
    quarter: String(synchronized.quarter),
    level: synchronized.level,
    direction: synchronized.direction,
    coverage: String(synchronized.coverage),
    include_unchanged: "true",
    limit: synchronized.level === "firm" ? "2000" : "5000",
  });
  if (synchronized.layers.length) params.set("layers", synchronized.layers.join(","));
  if (synchronized.focus) params.set("focus", synchronized.focus);
  if (synchronized.recognition) params.set("recognition", synchronized.recognition);
  if (synchronized.minAmount != null) params.set("min_amount", String(synchronized.minAmount));
  return params;
}

export function comparisonURL(state, patch = {}) {
  return `/api/compare/cashflows?${comparisonQuery(state, patch)}`;
}

export function getComparison(state, { scope = "comparison", patch = {} } = {}) {
  const params = comparisonQuery(state, patch);
  const key = `comparison:${params.toString()}`;
  return fetchJSON(`/api/compare/cashflows?${params}`, { scope, cacheKey: key });
}

/**
 * Fetch the comparison and both immutable run specifications. Separate request
 * scopes avoid the shared spec scope aborting one side while the other loads.
 */
export async function getComparisonContext(state, { scope = "comparison", patch = {}, includeSpecs = true } = {}) {
  const synchronized = comparisonStateSlice(state, patch);
  const comparisonPromise = getComparison(state, { scope, patch });
  if (!includeSpecs) {
    return {
      payload: await comparisonPromise,
      specA: null,
      specB: null,
      manifestA: null,
      manifestB: null,
      synchronized,
    };
  }
  const specAUrl = `/api/runs/${encodeURIComponent(synchronized.runA)}/spec`;
  const specBUrl = `/api/runs/${encodeURIComponent(synchronized.runB)}/spec`;
  const manifestAUrl = `/api/runs/${encodeURIComponent(synchronized.runA)}/cashflows`;
  const manifestBUrl = `/api/runs/${encodeURIComponent(synchronized.runB)}/cashflows`;
  const needsActorDirectories = synchronized.altitude !== "economy";
  const [payload, specA, specB, manifestA, manifestB] = await Promise.all([
    comparisonPromise,
    fetchJSON(specAUrl, {
      scope: `${scope}-spec-a`,
      cacheKey: `spec:${synchronized.runA}:v2`,
    }),
    fetchJSON(specBUrl, {
      scope: `${scope}-spec-b`,
      cacheKey: `spec:${synchronized.runB}:v2`,
    }),
    needsActorDirectories ? fetchJSON(manifestAUrl, {
      scope: `${scope}-manifest-a`,
      cacheKey: `manifest:${synchronized.runA}:v2`,
    }) : Promise.resolve(null),
    needsActorDirectories ? fetchJSON(manifestBUrl, {
      scope: `${scope}-manifest-b`,
      cacheKey: `manifest:${synchronized.runB}:v2`,
    }) : Promise.resolve(null),
  ]);
  return { payload, specA, specB, manifestA, manifestB, synchronized };
}

function explicitEligibility(compatibility) {
  return compatibility.eligible === true
    || compatibility.eligibility === true
    || compatibility.paired_eligible === true
    || compatibility.causal_eligible === true;
}

function compatibilityBadge(payload) {
  const compatibility = payload.compatibility && typeof payload.compatibility === "object"
    ? payload.compatibility
    : {};
  const paired = compatibility.paired === true && explicitEligibility(compatibility);
  const reasons = uniqueStrings(
    compatibility.reasons
    || compatibility.mismatches
    || compatibility.incompatibilities
    || payload.comparison?.reasons,
  );
  if (paired) {
    return {
      kind: "paired",
      label: "Paired controlled contrast",
      shortLabel: "Paired",
      allowsPairedLanguage: true,
      causalInterpretation: "controlled_simulation_contrast",
      explanation: "The server verified this pairing for a controlled run-level simulation contrast. It does not identify a unique causal path for any individual edge.",
      reasons,
    };
  }
  return {
    kind: "descriptive",
    label: "Descriptive difference",
    shortLabel: "Descriptive",
    allowsPairedLanguage: false,
    causalInterpretation: "none",
    explanation: compatibility.paired === true
      ? "The runs declare a pairing, but the server did not certify eligibility for this comparison. Differences are descriptive."
      : "The server did not certify these runs as an eligible paired treatment comparison. Differences are descriptive.",
    reasons,
  };
}

function numericTolerance(payload) {
  const candidate = firstDefined(
    payload.numeric_contract?.absolute_tolerance,
    payload.numeric_contract?.tolerance,
    payload.compatibility?.numeric_tolerance,
    payload.tolerance,
  );
  return Math.max(0, finite(candidate, 1e-9));
}

function stableId(raw) {
  return String(firstDefined(
    raw.stable_id,
    raw.semantic_id,
    raw.edge_id,
    raw.id,
    raw.edge_a?.stable_id,
    raw.edge_a?.semantic_id,
    raw.edge_a?.id,
    raw.edge_b?.stable_id,
    raw.edge_b?.semantic_id,
    raw.edge_b?.id,
  ) || "").trim();
}

function sideAmount(raw, side) {
  const isA = side === "a";
  const value = nullableFinite(firstDefined(
    isA ? raw.amount_a : raw.amount_b,
    isA ? raw.a_amount : raw.b_amount,
    isA ? raw.baseline_amount : raw.treatment_amount,
    isA ? raw.before_amount : raw.after_amount,
    isA ? raw.amount_before : raw.amount_after,
    isA ? raw.value_a : raw.value_b,
    isA ? raw.a?.amount : raw.b?.amount,
    isA ? raw.baseline?.amount : raw.treatment?.amount,
    isA ? raw.before?.amount : raw.after?.amount,
    isA ? raw.edge_a?.amount : raw.edge_b?.amount,
  ));
  if (value != null) return value;
  const explicitlyAbsent = isA
    ? raw.present_a === false || raw.edge_a === null
    : raw.present_b === false || raw.edge_b === null;
  return explicitlyAbsent ? 0 : null;
}

function deltaAmount(raw, amountA, amountB) {
  const explicit = nullableFinite(firstDefined(
    raw.delta_amount,
    raw.amount_delta,
    raw.change_amount,
    raw.delta,
    raw.difference,
  ));
  if (explicit != null) return explicit;
  if (amountA != null && amountB != null) return amountB - amountA;
  throw new ComparisonContractError(`Delta edge ${stableId(raw) || "(missing stable ID)"} has no numeric delta`);
}

function classifyDelta(amountA, amountB, delta, tolerance) {
  const aZero = amountA != null && Math.abs(amountA) <= tolerance;
  const bZero = amountB != null && Math.abs(amountB) <= tolerance;
  if (aZero && amountB != null && !bZero) return "added";
  if (bZero && amountA != null && !aZero) return "removed";
  if (delta > tolerance) return "increased";
  if (delta < -tolerance) return "decreased";
  return "unchanged";
}

function declaredDeltaClass(raw) {
  const value = String(firstDefined(raw.delta_class, raw.change_class, raw.status, raw.classification) || "").toLowerCase();
  return DELTA_CLASS_SET.has(value) ? value : null;
}

function edgeField(raw, name, ...aliases) {
  const names = [name, ...aliases];
  for (const key of names) {
    const value = firstDefined(
      raw[key],
      raw.edge_b?.[key],
      raw.treatment?.[key],
      raw.after?.[key],
      raw.edge_a?.[key],
      raw.baseline?.[key],
      raw.before?.[key],
    );
    if (value != null) return value;
  }
  return null;
}

function layerFor(raw) {
  return String(edgeField(raw, "layer", "category") || "products").toLowerCase();
}

function measureDomain(raw, layer) {
  const explicit = edgeField(raw, "measure_domain_id", "domain_id");
  if (explicit) return String(explicit);
  return [
    layer,
    String(edgeField(raw, "measure_kind") || "unspecified_measure"),
    String(edgeField(raw, "units") || "unspecified_units"),
    String(edgeField(raw, "recognition", "cash_recognition") || "unspecified_recognition"),
    String(edgeField(raw, "valuation_basis") || "unspecified_valuation"),
  ].join("|");
}

function rawDeltaRows(payload) {
  const rows = firstDefined(payload.edges, payload.deltas, payload.edge_deltas, payload.relationships);
  if (Array.isArray(rows)) return rows;
  const edgeSetsComplete = payload.complete_edge_sets === true || payload.query_applied_after_join === true;
  if (edgeSetsComplete && (Array.isArray(payload.edges_a) || Array.isArray(payload.edges_b))) {
    const joined = new Map();
    for (const edge of payload.edges_a || []) {
      const id = stableId(edge);
      if (!id) throw new ComparisonContractError("Baseline edge set contains an edge without a stable semantic ID");
      joined.set(id, { stable_id: id, edge_a: edge, edge_b: null });
    }
    for (const edge of payload.edges_b || []) {
      const id = stableId(edge);
      if (!id) throw new ComparisonContractError("Treatment edge set contains an edge without a stable semantic ID");
      const row = joined.get(id) || { stable_id: id, edge_a: null };
      row.edge_b = edge;
      joined.set(id, row);
    }
    return [...joined.values()];
  }
  throw new ComparisonContractError("Comparison response does not contain a joined delta edge table");
}

function rawNodes(payload, directoryNodes = []) {
  const candidates = [
    ...(Array.isArray(payload.nodes) ? payload.nodes : []),
    ...(Array.isArray(payload.nodes_a) ? payload.nodes_a : []),
    ...(Array.isArray(payload.nodes_b) ? payload.nodes_b : []),
    ...directoryNodes,
  ];
  const byId = new Map();
  for (const node of candidates) {
    if (!node?.id) continue;
    const id = String(node.id);
    const sector = node.sector == null && id.startsWith("sector:")
      ? nullableFinite(id.slice(7))
      : nullableFinite(node.sector);
    byId.set(id, {
      ...node,
      id,
      kind: String(node.kind || id.split(":")[0]),
      sector,
    });
  }
  return byId;
}

function normalizeEdges(payload, metadataIndex, directoryNodes = []) {
  const tolerance = numericTolerance(payload);
  const nodesById = rawNodes(payload, directoryNodes);
  const seen = new Set();
  const edges = [];
  for (const raw of rawDeltaRows(payload)) {
    const id = stableId(raw);
    if (!id) throw new ComparisonContractError("Comparison edge is missing its stable semantic ID");
    if (seen.has(id)) throw new ComparisonContractError(`Comparison response repeats stable edge ID ${id}`);
    seen.add(id);
    const declaredClass = declaredDeltaClass(raw);
    let amountA = sideAmount(raw, "a");
    let amountB = sideAmount(raw, "b");
    if (amountA == null && declaredClass === "added") amountA = 0;
    if (amountB == null && declaredClass === "removed") amountB = 0;
    const delta = deltaAmount(raw, amountA, amountB);
    const computedClass = classifyDelta(amountA, amountB, delta, tolerance);
    if (declaredClass && declaredClass !== computedClass) {
      throw new ComparisonContractError(
        `Comparison edge ${id} is classified as ${declaredClass}, but its values imply ${computedClass}`,
        { id, declaredClass, computedClass, amountA, amountB, delta, tolerance },
      );
    }
    const source = String(edgeField(raw, "source", "display_source", "canonical_source") || "");
    const target = String(edgeField(raw, "target", "display_target", "canonical_target") || "");
    if (!source || !target) throw new ComparisonContractError(`Comparison edge ${id} has no stable source/target`);
    for (const actorId of [source, target]) {
      if (!nodesById.has(actorId)) {
        nodesById.set(actorId, {
          id: actorId,
          kind: actorId.split(":")[0],
          sector: actorId.startsWith("sector:") ? nullableFinite(actorId.slice(7)) : null,
          metrics: {},
        });
      }
    }
    const layer = layerFor(raw);
    const recognition = String(edgeField(raw, "recognition", "cash_recognition") || "unspecified");
    const measureKind = String(edgeField(raw, "measure_kind") || "unspecified");
    const units = String(edgeField(raw, "units") || "unspecified");
    const domainId = measureDomain(raw, layer);
    const rawParents = edgeField(raw, "parent_ids");
    edges.push({
      ...raw,
      id,
      stableId: id,
      source,
      target,
      layer,
      label: String(edgeField(raw, "label") || humanizeId(edgeField(raw, "purpose") || id)),
      purpose: String(edgeField(raw, "purpose") || "unspecified"),
      market: String(edgeField(raw, "market") || "comparison"),
      measureKind,
      recognition,
      units,
      valuationBasis: String(edgeField(raw, "valuation_basis") || "unspecified"),
      realizationScope: String(edgeField(raw, "realization_scope") || payload.realization_scope || "representative"),
      evidenceBasis: String(edgeField(raw, "evidence_basis", "provenance") || "comparison_endpoint"),
      aggregation: String(edgeField(raw, "aggregation") || "stable_id_join_before_coverage"),
      timing: String(edgeField(raw, "timing") || "quarterly_window"),
      directionSemantics: String(edgeField(raw, "direction_semantics") || "recorded_edge_direction"),
      explanation: String(edgeField(raw, "explanation") || "Run B minus run A for the same stable economic relationship."),
      quantity: finite(edgeField(raw, "quantity"), 0),
      quantityAvailable: edgeField(raw, "quantity") != null,
      matchCount: Math.max(0, Math.trunc(finite(edgeField(raw, "match_count"), 0))),
      matchCountAvailable: edgeField(raw, "match_count") != null,
      rollupId: edgeField(raw, "rollup_id") ? String(edgeField(raw, "rollup_id")) : null,
      componentId: edgeField(raw, "component_id") ? String(edgeField(raw, "component_id")) : null,
      parentIds: Array.isArray(rawParents) ? rawParents.map(String) : [],
      amountA,
      amountB,
      delta,
      amount: Math.abs(delta),
      signedValue: delta,
      deltaClass: computedClass,
      cssClass: `comparison-delta comparison-delta--${computedClass}`,
      measureDomainId: domainId,
      scaleDomainId: domainId,
      nonCash: recognition.includes("counterfactual") || layer === "capacity",
      stockNonCash: recognition.includes("stock_non_cash") || layer === "stocks",
    });
  }

  const normalizedNodes = [...nodesById.values()].map((node) => ({
    ...node,
    label: actorLabel(node.id, nodesById, metadataIndex),
    // Comparison responses are edge-centric. Directory nodes provide stable
    // identity and classification for layout only; their quarter-0 metrics
    // and account snapshots are not paired A/B evidence for this quarter.
    metrics: {},
    account_reconciliations: [],
    accountReconciliations: [],
    comparisonNodeEvidence: "identity_and_layout_only",
  }));
  const labeledById = new Map(normalizedNodes.map((node) => [node.id, node]));
  for (const edge of edges) {
    edge.sourceLabel = actorLabel(edge.source, labeledById, metadataIndex);
    edge.targetLabel = actorLabel(edge.target, labeledById, metadataIndex);
  }
  return { edges, nodes: normalizedNodes, nodesById: labeledById, tolerance };
}

function serverCoverageByDomain(payload) {
  const raw = payload.coverage_by_domain || payload.coverage?.by_domain || payload.coverage || {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  if ("count_matching" in raw || "count_total" in raw) return { default: raw };
  return Object.fromEntries(
    Object.entries(raw).filter(([, value]) => value && typeof value === "object"),
  );
}

function summarizeDomains(edges, payload) {
  const coverage = serverCoverageByDomain(payload);
  const byDomain = new Map();
  for (const edge of edges) {
    if (!byDomain.has(edge.measureDomainId)) {
      byDomain.set(edge.measureDomainId, {
        id: edge.measureDomainId,
        layer: edge.layer,
        measureKind: edge.measureKind,
        units: edge.units,
        recognition: edge.recognition,
        valuationBasis: edge.valuationBasis,
        edges: [],
        counts: Object.fromEntries(DELTA_CLASSES.map((name) => [name, 0])),
      });
    }
    const domain = byDomain.get(edge.measureDomainId);
    domain.edges.push(edge);
    domain.counts[edge.deltaClass] += 1;
  }
  const onlyDomain = byDomain.size === 1 ? [...byDomain.values()][0] : null;
  for (const domain of byDomain.values()) {
    domain.coverage = coverage[domain.id]
      || (onlyDomain && coverage.default)
      || null;
    domain.changedCount = domain.edges.length - domain.counts.unchanged;
  }
  return [...byDomain.values()].sort((a, b) => a.layer.localeCompare(b.layer) || a.id.localeCompare(b.id));
}

function normalizeScaleEntry(domain, { stable = true } = {}) {
  return {
    min: Math.max(0, finite(domain?.min)),
    max: Math.max(0, finite(domain?.max)),
    mapping: String(domain?.mapping || "sqrt"),
    stable: domain?.stable == null ? stable : domain.stable === true,
    shared: domain?.shared == null ? true : domain.shared === true,
  };
}

function sharedScaleDomains(payload, domains) {
  const supplied = payload.shared_scale_domains || payload.scale_domains || {};
  const result = {};
  for (const domain of domains) {
    const sameLayer = domains.filter((candidate) => candidate.layer === domain.layer);
    const source = supplied[domain.id] || (sameLayer.length === 1 ? supplied[domain.layer] : null);
    if (source) {
      result[domain.id] = normalizeScaleEntry(source);
      continue;
    }
    const maximum = Math.max(
      0,
      ...domain.edges.flatMap((edge) => [Math.abs(edge.amountA || 0), Math.abs(edge.amountB || 0)]),
    );
    result[domain.id] = { min: 0, max: maximum, mapping: "sqrt", stable: false, shared: true };
  }
  return result;
}

function rendererScaleDomains(domains, sharedDomains) {
  const byLayer = new Map();
  for (const domain of domains) {
    if (!byLayer.has(domain.layer)) byLayer.set(domain.layer, []);
    byLayer.get(domain.layer).push(domain);
  }
  const safe = {};
  const ambiguousLayers = [];
  for (const [layer, layerDomains] of byLayer) {
    if (layerDomains.length === 1) safe[layer] = sharedDomains[layerDomains[0].id];
    else ambiguousLayers.push(layer);
  }
  return { safe, ambiguousLayers };
}

function hasOwn(object, key) {
  return Boolean(object && Object.prototype.hasOwnProperty.call(object, key));
}

function valueAt(item, ...keys) {
  return firstDefined(...keys.map((key) => item?.[key]));
}

function normalizeServerSpecDiff(raw, defaultKind = "server") {
  if (Array.isArray(raw)) {
    return raw.map((item, index) => ({
      path: String(valueAt(item, "path", "key", "field") || `change_${index + 1}`),
      before: valueAt(item, "before", "from", "a", "baseline"),
      after: valueAt(item, "after", "to", "b", "treatment"),
      classification: String(valueAt(item, "classification", "kind") || (item?.intervention === true ? "intervention" : defaultKind)),
      source: "server",
    }));
  }
  if (raw && typeof raw === "object") {
    return Object.entries(raw).map(([path, value]) => ({
      path,
      before: value && typeof value === "object" ? valueAt(value, "before", "from", "a", "baseline") : undefined,
      after: value && typeof value === "object" ? valueAt(value, "after", "to", "b", "treatment") : value,
      classification: String(valueAt(value, "classification", "kind") || defaultKind),
      source: "server",
    }));
  }
  return [];
}

function jsonEqual(a, b) {
  if (Object.is(a, b)) return true;
  try {
    return JSON.stringify(a) === JSON.stringify(b);
  } catch {
    return false;
  }
}

function descriptiveSpecDiff(a, b, path = "", result = []) {
  if (jsonEqual(a, b)) return result;
  const aObject = a && typeof a === "object" && !Array.isArray(a);
  const bObject = b && typeof b === "object" && !Array.isArray(b);
  if (aObject && bObject) {
    const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
    for (const key of keys) descriptiveSpecDiff(a[key], b[key], path ? `${path}.${key}` : key, result);
    return result;
  }
  result.push({
    path: path || "specification",
    before: a,
    after: b,
    classification: "client_descriptive",
    source: "client",
  });
  return result;
}

function runSpecDiff(payload, specA, specB) {
  if (hasOwn(payload, "run_spec_diff")) return normalizeServerSpecDiff(payload.run_spec_diff);
  if (hasOwn(payload, "spec_diff")) return normalizeServerSpecDiff(payload.spec_diff);
  if (hasOwn(payload, "intervention_diff")) return normalizeServerSpecDiff(payload.intervention_diff, "intervention");
  if (specA || specB) return descriptiveSpecDiff(specA || {}, specB || {});
  return [];
}

function shockContext(payload) {
  const raw = payload.shock_context || payload.comparison?.shock_context || payload.experiment?.intervention || {};
  const quarter = nullableFinite(firstDefined(
    raw.quarter,
    raw.shock_quarter,
    raw.onset_quarter,
    payload.shock_quarter,
    payload.comparison?.shock_quarter,
  ));
  const normalizedQuarter = quarter == null ? null : Math.max(0, Math.trunc(quarter));
  return {
    quarter: normalizedQuarter,
    label: String(firstDefined(raw.label, raw.name, raw.type, raw.shock_type) || "Intervention"),
    duration: nullableFinite(firstDefined(raw.duration, raw.duration_quarters)),
    magnitude: nullableFinite(firstDefined(raw.magnitude, raw.value)),
    units: raw.units ? String(raw.units) : null,
    explicit: normalizedQuarter != null,
  };
}

function shockPosition(selectedQuarter, shock) {
  if (shock.quarter == null) return "unknown";
  if (selectedQuarter < shock.quarter) return "before";
  if (selectedQuarter === shock.quarter) return "onset";
  return "after";
}

/**
 * Convert a server comparison response into a renderer/panel model.
 *
 * Pairing eligibility is never inferred from matching IDs or specs. Client-side
 * spec diffs are descriptive context only. Value coverage and summaries remain
 * separated by compatible measure domain.
 */
export function adaptComparison(
  payload,
  state,
  metadataIndex = null,
  { specA = null, specB = null, manifestA = null, manifestB = null } = {},
) {
  if (!payload || typeof payload !== "object") {
    throw new ComparisonContractError("Comparison response is not an object");
  }
  const synchronized = comparisonStateSlice(state);
  const directoryKey = synchronized.altitude === "firms"
    ? "firm_directory"
    : synchronized.altitude === "sectors"
      ? "sector_directory"
      : null;
  // Comparison responses are intentionally edge-centric. Reattach immutable
  // run directories so synthetic firms retain sector membership and sector
  // nodes retain dataset grouping/order in the deterministic layouts.
  const directoryNodes = directoryKey
    ? [
      ...(Array.isArray(manifestA?.[directoryKey]) ? manifestA[directoryKey] : []),
      ...(Array.isArray(manifestB?.[directoryKey]) ? manifestB[directoryKey] : []),
    ]
    : [];
  const normalized = normalizeEdges(payload, metadataIndex, directoryNodes);
  const domains = summarizeDomains(normalized.edges, payload);
  const sharedDomains = sharedScaleDomains(payload, domains);
  const rendererDomains = rendererScaleDomains(domains, sharedDomains);
  const badge = compatibilityBadge(payload);
  const shock = shockContext(payload);
  const changedEdges = normalized.edges.filter((edge) => edge.deltaClass !== "unchanged");
  const classCounts = Object.fromEntries(DELTA_CLASSES.map((name) => [
    name,
    normalized.edges.filter((edge) => edge.deltaClass === name).length,
  ]));

  return {
    schema: String(payload.api_schema_version || payload.schema_version || "cashflow-comparison"),
    runA: String(payload.run_a || synchronized.runA),
    runB: String(payload.run_b || synchronized.runB),
    quarter: synchronized.quarter,
    altitude: synchronized.altitude,
    level: synchronized.level,
    layers: synchronized.layers,
    focus: synchronized.focus,
    direction: synchronized.direction,
    badge,
    compatibility: payload.compatibility || {},
    nodes: normalized.nodes,
    nodesById: normalized.nodesById,
    allEdges: normalized.edges,
    edges: changedEdges,
    tolerance: normalized.tolerance,
    zeroDelta: changedEdges.length === 0,
    classCounts,
    domains,
    coverageByDomain: Object.fromEntries(domains.map((domain) => [domain.id, domain.coverage])),
    sharedScaleDomains: sharedDomains,
    scaleDomains: rendererDomains.safe,
    ambiguousScaleLayers: rendererDomains.ambiguousLayers,
    runSpecDiff: runSpecDiff(payload, specA, specB),
    shock: { ...shock, position: shockPosition(synchronized.quarter, shock) },
    period: String(payload.period || `Quarter ${synchronized.quarter}`),
    realizationScope: String(payload.realization_scope || payload.comparison?.realization_scope || "representative"),
    diagnostics: payload.diagnostics || {},
    warnings: uniqueStrings([
      ...(badge.reasons || []),
      ...(payload.warnings || []),
      ...(rendererDomains.ambiguousLayers.length ? [
        `Line widths in ${rendererDomains.ambiguousLayers.map(humanizeId).join(", ")} are scaled separately because those layers contain non-additive measures. Compare widths only within the same measure.`,
      ] : []),
    ]),
  };
}

export function comparisonCoverageText(model) {
  const domains = model?.domains || [];
  if (!domains.length) return "No comparison relationships were returned.";
  const returned = domains.reduce((sum, domain) => sum + domain.edges.length, 0);
  const matchingCounts = domains
    .map((domain) => nullableFinite(domain.coverage?.count_matching))
    .filter((value) => value != null);
  const matching = matchingCounts.length === domains.length
    ? matchingCounts.reduce((sum, value) => sum + value, 0)
    : null;
  const countText = matching == null
    ? `${returned.toLocaleString()} returned relationships`
    : `${returned.toLocaleString()} of ${matching.toLocaleString()} matching relationships`;
  if (domains.length === 1) {
    const coverage = domains[0].coverage;
    const matchingValue = nullableFinite(firstDefined(coverage?.amount_matching, coverage?.value_matching));
    const returnedValue = nullableFinite(firstDefined(coverage?.amount_returned, coverage?.value_returned));
    if (matchingValue != null && returnedValue != null) {
      const share = matchingValue > 0 ? returnedValue / matchingValue : 1;
      return `${countText}; ${Math.max(0, Math.min(1, share) * 100).toFixed(1)}% of changed-value magnitude in this compatible domain.`;
    }
    return `${countText}; value coverage is unavailable.`;
  }
  return `${countText}; value coverage is reported separately across ${domains.length.toLocaleString()} compatible measure domains and is never combined.`;
}
