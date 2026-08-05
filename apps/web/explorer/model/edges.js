import { actorLabel, humanizeId } from "../metadata.js";

export const LAYERS = Object.freeze({
  products: { label: "Products & services", color: "#70d7e2", order: 1 },
  capacity: { label: "Potential supply response", color: "#b99cf3", order: 2, nonCash: true },
  income: { label: "Wages & dividends", color: "#f0c86e", order: 3 },
  fiscal: { label: "Taxes & benefits", color: "#ff937f", order: 4 },
  credit: { label: "Credit & principal", color: "#b58de6", order: 5 },
  interest: { label: "Interest", color: "#f08eb7", order: 6 },
  deposits: { label: "Deposits & saving", color: "#8eb5a9", order: 7 },
  stocks: { label: "Financial stocks", color: "#7aa9e8", order: 8 },
  foreign: { label: "Foreign transactions", color: "#80b8f4", order: 9 },
});

const LEGACY_CATEGORY_LAYER = Object.freeze({
  goods: "products",
  external: "foreign",
  income: "income",
  fiscal: "fiscal",
  credit: "credit",
  interest: "interest",
  deposits: "deposits",
});

const PURCHASE_MARKETS = new Set(["business_goods", "final_demand", "products", "retail"]);

function finite(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function bool(value) {
  return value === true || value === 1 || value === 1.0 || value === "true";
}

function layerFor(edge) {
  const raw = String(edge.layer || edge.category || "products").toLowerCase();
  if (LAYERS[raw]) return raw;
  if (LEGACY_CATEGORY_LAYER[raw]) return LEGACY_CATEGORY_LAYER[raw];
  if (raw.includes("counterfactual") || raw.includes("capacity")) return "capacity";
  if (raw.includes("stock")) return "stocks";
  if (raw.includes("deposit")) return "deposits";
  if (raw.includes("tax") || raw.includes("benefit") || raw.includes("fiscal")) return "fiscal";
  if (raw.includes("interest")) return "interest";
  if (raw.includes("credit") || raw.includes("principal")) return "credit";
  if (raw.includes("wage") || raw.includes("dividend") || raw.includes("income")) return "income";
  if (raw.includes("foreign") || raw.includes("external")) return "foreign";
  return "products";
}

function normalizedRecognition(edge, layer) {
  const value = String(edge.recognition || edge.cash_recognition || "").toLowerCase();
  if (value) return value;
  if (layer === "capacity") return "capacity_counterfactual";
  if (layer === "stocks") return "stock_non_cash";
  return "realized_cash";
}

function defaultMoneyUnits(layer, unitContext = null) {
  if (typeof unitContext === "string" && unitContext) return unitContext;
  const key = layer === "stocks" ? "stock" : "flow";
  const supplied = unitContext?.[key] || unitContext?.[`${key}_units`];
  if (supplied) return String(supplied);
  return layer === "stocks" ? "million_eur" : "million_eur_per_quarter";
}

function normalizeEdge(edge, { direction = "money", legacy = false, unitContext = null } = {}) {
  const layer = layerFor(edge);
  const canonicalSource = String(edge.canonical_source || edge.canonicalSource || edge.source || "unknown");
  const canonicalTarget = String(edge.canonical_target || edge.canonicalTarget || edge.target || "unknown");
  const signedValue = finite(edge.signed_value ?? edge.signedValue ?? edge.amount, 0);
  const rawSource = String(edge.display_source || edge.source || (signedValue >= 0 ? canonicalSource : canonicalTarget));
  const rawTarget = String(edge.display_target || edge.target || (signedValue >= 0 ? canonicalTarget : canonicalSource));
  const market = String(edge.market || (legacy ? "legacy_aggregate" : "institution"));
  const productDirection = direction === "product" && PURCHASE_MARKETS.has(market);
  const source = productDirection ? rawTarget : rawSource;
  const target = productDirection ? rawSource : rawTarget;
  const recognition = normalizedRecognition(edge, layer);
  const amount = Math.abs(finite(edge.amount ?? signedValue, 0));
  const label = String(edge.label || humanizeId(edge.purpose || edge.category || edge.id));
  const measureKind = String(edge.measure_kind || (layer === "stocks" ? "stock" : legacy ? "legacy_aggregate" : "cash_transaction"));
  const units = String(edge.units || defaultMoneyUnits(layer, unitContext));
  const level = String(edge.level || (legacy ? "legacy" : "unknown"));
  const measureDomainId = String(
    edge.measure_domain_id
      || edge.scale_domain_id
      || [level, layer, measureKind, units, recognition].join("|"),
  );
  return {
    ...edge,
    id: String(edge.id || `${layer}:${canonicalSource}:${canonicalTarget}`),
    source,
    target,
    canonicalSource,
    canonicalTarget,
    signedValue,
    amount,
    quantity: finite(edge.quantity, 0),
    quantityAvailable: edge.quantity != null,
    matchCount: Math.max(0, Math.trunc(finite(edge.match_count ?? edge.transaction_count, 0))),
    matchCountAvailable: edge.match_count != null || edge.transaction_count != null,
    label,
    layer,
    market,
    purpose: String(edge.purpose || "unspecified"),
    measureKind,
    recognition,
    units,
    measureDomainId,
    scaleDomainId: measureDomainId,
    directionSemantics: String(edge.direction_semantics || (productDirection ? "seller_to_buyer" : "buyer_to_seller")),
    evidenceBasis: String(edge.evidence_basis || edge.provenance || (legacy ? "legacy_trace_field" : "model_equation")),
    realizationScope: String(edge.realization_scope || (legacy ? "representative" : "representative")),
    aggregation: String(edge.aggregation || (legacy ? "legacy_response" : "exact_sum")),
    timing: String(edge.timing || "quarterly_window"),
    valuationBasis: String(edge.valuation_basis || (legacy ? "legacy_declared_basis" : "seller_price_basis")),
    explanation: String(edge.explanation || ""),
    rollupId: edge.rollup_id ? String(edge.rollup_id) : null,
    componentId: edge.component_id ? String(edge.component_id) : null,
    parentIds: Array.isArray(edge.parent_ids) ? edge.parent_ids.map(String) : [],
    nonCash: layer === "capacity" || recognition.includes("counterfactual"),
    stockNonCash: layer === "stocks" || recognition.includes("stock_non_cash"),
    legacy,
  };
}

function legacyRelationshipEdges(
  rows,
  {
    sector = false,
    includeCapacity = false,
    direction = "money",
    unitContext = null,
  } = {},
) {
  const edges = [];
  const flowUnits = defaultMoneyUnits("products", unitContext);
  for (const row of rows || []) {
    const realized = normalizeEdge({
      ...row,
      id: String(row.id),
      label: sector ? "Business inputs" : "Business input receipt",
      layer: "products",
      market: "business_goods",
      purpose: "business_inputs",
      measure_kind: "cash_transaction",
      cash_recognition: "realized_cash",
      evidence_basis: "transaction_event",
      realization_scope: "representative",
      aggregation: sector ? "firm_relationships_to_sector_pair" : "exact_sum",
      timing: "quarterly_window",
      units: flowUnits,
      valuation_basis: "seller_transaction_price",
    }, { direction, legacy: true });
    if (realized.amount > 0) edges.push(realized);
    const potential = finite(row.potential_amount, 0);
    if (includeCapacity && potential > 0) {
      edges.push(normalizeEdge({
        ...row,
        id: `capacity:${row.id}`,
        amount: potential,
        quantity: finite(row.potential_quantity, 0),
        transaction_count: finite(row.potential_match_count, 0),
        label: "Potential supply response",
        layer: "capacity",
        market: "business_goods",
        purpose: "capacity_counterfactual_match",
        measure_kind: "capacity_counterfactual",
        cash_recognition: "capacity_counterfactual",
        evidence_basis: "second_pass_capacity_match",
        aggregation: sector ? "firm_relationships_to_sector_pair" : "exact_sum",
        timing: "quarterly_window",
        units: flowUnits,
        valuation_basis: "matched_seller_price",
        explanation: "A second-pass match against unused productive capacity. This is not cash and is not proof of observed unmet demand.",
      }, { direction, legacy: true }));
    }
  }
  return edges;
}

function legacyMacroEdges(payload, direction, unitContext = null) {
  const flowUnits = defaultMoneyUnits("products", unitContext);
  return (payload.flows || []).map((flow) => normalizeEdge({
    ...flow,
    layer: LEGACY_CATEGORY_LAYER[flow.category] || flow.layer,
    market: flow.category === "goods" || flow.category === "external" ? "final_demand" : "institution",
    purpose: String(flow.id || "macro_flow").replace(/-/g, "_"),
    measure_kind: flow.layer === "balance_sheet" ? "stock_change" : "model_equation",
    cash_recognition: flow.layer === "balance_sheet" ? "stock_change_non_cash" : "realized_cash",
    evidence_basis: flow.provenance || "model_equation",
    realization_scope: "representative",
    aggregation: "macro_equation",
    timing: "quarterly_window",
    units: flowUnits,
    valuation_basis: "declared_macro_basis",
  }, { direction, legacy: true }));
}

function dedupeNodes(nodes) {
  const byId = new Map();
  for (const node of nodes || []) {
    if (!node?.id) continue;
    byId.set(String(node.id), { ...node, id: String(node.id), sector: node.sector == null ? null : Number(node.sector) });
  }
  return [...byId.values()];
}

function nodeSetFor(payload, altitude) {
  const institutions = payload.nodes || payload.institutions || [];
  const outside = payload.outside_portals || [];
  if (altitude === "economy") return dedupeNodes(institutions);
  if (altitude === "sectors") return dedupeNodes([...(payload.sectors || []), ...institutions, ...outside]);
  return dedupeNodes([...(payload.firms || []), ...institutions, ...outside]);
}

function inferLegacyCoverage(payload, altitude, edges) {
  const prefix = altitude === "sectors" ? "sector_relationship" : "relationship";
  if (altitude === "economy") {
    const amount = edges.reduce((sum, edge) => sum + edge.amount, 0);
    return {
      count_total: edges.length,
      count_matching: edges.length,
      count_returned: edges.length,
      amount_total: amount,
      amount_matching: amount,
      amount_returned: amount,
      amount_compatible: true,
      legacy_amount_unknown: false,
    };
  }
  return {
    count_total: Math.trunc(finite(payload[`${prefix}_count_total`] ?? payload[`${prefix}_count`], edges.length)),
    count_matching: Math.trunc(finite(payload[`${prefix}_count_matching`], edges.length)),
    count_returned: Math.trunc(finite(payload[`${prefix}_count_returned`], edges.length)),
    amount_total: null,
    amount_matching: null,
    amount_returned: edges.reduce((sum, edge) => sum + edge.amount, 0),
    amount_compatible: true,
    legacy_amount_unknown: true,
  };
}

function normalizeCoverage(payload, altitude, edges) {
  if (!payload.coverage) return inferLegacyCoverage(payload, altitude, edges);
  const coverage = payload.coverage;
  const allDomains = Object.entries(coverage)
    .filter(([, value]) => value && typeof value === "object" && "count_total" in value)
    .map(([id, value]) => ({ id, ...value }));
  const visibleDomainIds = new Set(edges.map((edge) => edge.scaleDomainId || edge.measureDomainId || [
    edge.level || "macro",
    edge.layer || "unknown",
    edge.measureKind || "unknown",
    edge.units || "unknown",
    edge.recognition || "unknown",
  ].join("|")));
  const domains = visibleDomainIds.size
    ? allDomains.filter((domain) => visibleDomainIds.has(domain.id))
    : allDomains;
  if (!domains.length && !Object.prototype.hasOwnProperty.call(coverage, "count_total") && edges.length === 0) {
    return {
      count_total: 0,
      count_matching: 0,
      count_returned: 0,
      amount_total: 0,
      amount_matching: 0,
      amount_returned: 0,
      amount_compatible: true,
      legacy_amount_unknown: false,
      domain_count: 0,
      target: finite(payload.query?.coverage, 1),
      by_domain: {},
    };
  }
  if (domains.length) {
    const active = domains.filter((domain) => finite(domain.count_matching) > 0 || finite(domain.count_returned) > 0);
    const only = active.length === 1 ? active[0] : null;
    return {
      count_total: domains.reduce((sum, domain) => sum + Math.trunc(finite(domain.count_total)), 0),
      count_matching: domains.reduce((sum, domain) => sum + Math.trunc(finite(domain.count_matching)), 0),
      count_returned: domains.reduce((sum, domain) => sum + Math.trunc(finite(domain.count_returned)), 0),
      amount_total: only ? finite(only.amount_total) : null,
      amount_matching: only ? finite(only.amount_matching) : null,
      amount_returned: only ? finite(only.amount_returned) : null,
      amount_compatible: Boolean(only),
      legacy_amount_unknown: false,
      domain_count: active.length,
      target: finite(payload.query?.coverage, 1),
      by_domain: Object.fromEntries(domains.map((domain) => [domain.id, domain])),
    };
  }
  return {
    count_total: Math.trunc(finite(coverage.count_total, 0)),
    count_matching: Math.trunc(finite(coverage.count_matching, 0)),
    count_returned: Math.trunc(finite(coverage.count_returned, edges.length)),
    amount_total: coverage.amount_total == null ? null : finite(coverage.amount_total),
    amount_matching: coverage.amount_matching == null ? null : finite(coverage.amount_matching),
    amount_returned: coverage.amount_returned == null ? null : finite(coverage.amount_returned),
    amount_compatible: coverage.amount_compatible !== false,
    legacy_amount_unknown: false,
  };
}

export function activeViewCoverage(serverCoverage, edges) {
  const visibleByDomain = new Map();
  for (const edge of edges) {
    const id = edge.scaleDomainId || edge.measureDomainId || [
      edge.level || "macro",
      edge.layer || "unknown",
      edge.measureKind || "unknown",
      edge.units || "unknown",
      edge.recognition || "unknown",
    ].join("|");
    if (!visibleByDomain.has(id)) visibleByDomain.set(id, { edges: [], amount: 0 });
    const entry = visibleByDomain.get(id);
    entry.edges.push(edge);
    entry.amount += Math.abs(finite(edge.amount));
  }

  const serverByDomain = serverCoverage?.by_domain || {};
  const serverDomainEntries = Object.entries(serverByDomain);
  // Keep domains that the server returned even when every relationship in
  // that domain is suppressed by the active client view. Otherwise the
  // aggregate disclosure silently loses the server-returned count and value.
  const activeDomainIds = [...new Set([
    ...serverDomainEntries.map(([id]) => id),
    ...visibleByDomain.keys(),
  ])];
  const flatServerFallback = serverDomainEntries.length === 0 && activeDomainIds.length <= 1
    ? serverCoverage
    : null;
  const byDomain = {};
  for (const id of activeDomainIds) {
    const visible = visibleByDomain.get(id) || { edges: [], amount: 0 };
    const server = serverByDomain[id] || flatServerFallback || {};
    const serverReturnedCount = Math.trunc(finite(server.count_returned, visible.edges.length));
    byDomain[id] = {
      ...server,
      id,
      count_total: Math.trunc(finite(server.count_total, server.count_matching ?? visible.edges.length)),
      count_matching: Math.trunc(finite(server.count_matching, visible.edges.length)),
      count_returned: visible.edges.length,
      amount_total: server.amount_total == null ? null : finite(server.amount_total),
      amount_matching: server.amount_matching == null ? null : finite(server.amount_matching),
      amount_returned: visible.amount,
      server_count_returned: serverReturnedCount,
      server_amount_returned: server.amount_returned == null ? null : finite(server.amount_returned),
      client_suppressed_count: Math.max(0, serverReturnedCount - visible.edges.length),
    };
  }

  const domains = Object.values(byDomain);
  const only = domains.length === 1 ? domains[0] : null;
  const serverReturned = domains.reduce((sum, domain) => sum + domain.server_count_returned, 0);
  return {
    count_total: domains.length
      ? domains.reduce((sum, domain) => sum + domain.count_total, 0)
      : Math.trunc(finite(serverCoverage?.count_total)),
    count_matching: domains.length
      ? domains.reduce((sum, domain) => sum + domain.count_matching, 0)
      : Math.trunc(finite(serverCoverage?.count_matching)),
    count_returned: edges.length,
    amount_total: only ? only.amount_total : null,
    amount_matching: only ? only.amount_matching : null,
    amount_returned: only ? only.amount_returned : null,
    amount_compatible: Boolean(only),
    legacy_amount_unknown: Boolean(serverCoverage?.legacy_amount_unknown),
    legacy_focus_partial: Boolean(serverCoverage?.legacy_focus_partial),
    domain_count: domains.length,
    target: serverCoverage?.target,
    by_domain: byDomain,
    server_count_returned: serverReturned || Math.trunc(finite(serverCoverage?.count_returned)),
    client_suppressed_count: Math.max(
      0,
      (serverReturned || Math.trunc(finite(serverCoverage?.count_returned))) - edges.length,
    ),
    active_view_recomputed: true,
  };
}

function scaleDomains(payload, manifest, edges) {
  const supplied = payload.scale_domains || manifest?.scale_domains || {};
  const result = {};
  for (const [domainId, domain] of Object.entries(supplied)) {
    if (!domain || typeof domain !== "object") continue;
    const maximum = finite(domain.max);
    result[domainId] = { min: 0, max: maximum, mapping: String(domain.mapping || "sqrt"), stable: true };
  }
  const byDomain = new Map();
  for (const edge of edges) {
    const domainId = edge.scaleDomainId;
    if (!byDomain.has(domainId)) byDomain.set(domainId, []);
    byDomain.get(domainId).push(edge);
  }
  for (const [domainId, domainEdges] of byDomain) {
    if (result[domainId]) continue;
    result[domainId] = {
      min: 0,
      max: Math.max(0, ...domainEdges.map((edge) => edge.amount)),
      mapping: "sqrt",
      stable: false,
    };
  }
  const domainsByLayer = new Map();
  for (const edge of edges) {
    if (!domainsByLayer.has(edge.layer)) domainsByLayer.set(edge.layer, new Set());
    domainsByLayer.get(edge.layer).add(edge.scaleDomainId);
  }
  for (const [layer, domainIds] of domainsByLayer) {
    if (domainIds.size === 1) result[layer] = result[[...domainIds][0]];
  }
  return result;
}

function questionFilter(edges, question) {
  if (!question) return edges;
  if (question === "government-purchases") {
    return edges.filter((edge) => edge.purpose === "government_purchase" || edge.id === "government-goods" || edge.source === "government");
  }
  if (question === "firm-institutions") {
    return edges.filter((edge) => edge.market === "institution" || !["products", "capacity", "foreign"].includes(edge.layer));
  }
  if (question === "capacity-response") return edges.filter((edge) => edge.layer === "capacity");
  return edges;
}

function suppressExpandedRollups(edges) {
  const expandedParents = new Set();
  for (const edge of edges) {
    if (edge.rollupId) expandedParents.add(edge.rollupId);
    for (const parentId of edge.parentIds || []) expandedParents.add(parentId);
  }
  return edges.filter((edge) => !expandedParents.has(edge.id));
}

export function adaptQuarter(payload, state, metadataIndex, manifest = null) {
  const isV2 = String(payload.api_schema_version || payload.schema_version || "").includes("v2") || Array.isArray(payload.edges);
  const unitContext = payload.units || manifest?.units || null;
  let edges;
  if (Array.isArray(payload.edges)) {
    edges = payload.edges.map((edge) => normalizeEdge(edge, {
      direction: state.direction,
      legacy: false,
      unitContext,
    }));
  } else if (state.altitude === "economy") {
    edges = legacyMacroEdges(payload, state.direction, unitContext);
  } else if (state.altitude === "sectors") {
    edges = legacyRelationshipEdges(payload.sector_relationships, {
      sector: true,
      includeCapacity: !state.layers?.length || state.layers.includes("capacity"),
      direction: state.direction,
      unitContext,
    });
  } else {
    edges = legacyRelationshipEdges(payload.relationships, {
      includeCapacity: !state.layers?.length || state.layers.includes("capacity"),
      direction: state.direction,
      unitContext,
    });
  }

  // Preserve the endpoint's complete returned-query accounting before the
  // client hides expanded parents or applies any presentation-only predicate.
  const serverCoverage = normalizeCoverage(payload, state.altitude, edges);

  const activeLayers = state.layers?.length ? new Set(state.layers) : null;
  if (activeLayers) edges = edges.filter((edge) => activeLayers.has(edge.layer));
  edges = questionFilter(edges, state.question);
  edges = suppressExpandedRollups(edges);
  const legacySectorFocus = !isV2 && state.altitude === "sectors" && state.focus && state.focus !== "all";
  if (state.focus && state.focus !== "all" && state.altitude !== "economy") {
    edges = edges.filter((edge) => edge.source === state.focus || edge.target === state.focus);
  }

  const nodes = nodeSetFor(payload, state.altitude);
  const nodesById = new Map(nodes.map((node) => [node.id, node]));
  for (const edge of edges) {
    for (const id of [edge.source, edge.target]) {
      if (!nodesById.has(id)) {
        nodesById.set(id, {
          id,
          label: humanizeId(id),
          kind: id.split(":")[0],
          sector: id.startsWith("sector:") ? Number(id.slice(7)) : null,
          metrics: {},
        });
      }
    }
  }
  const normalizedNodes = [...nodesById.values()].map((node) => ({
    ...node,
    label: actorLabel(node.id, nodesById, metadataIndex),
    metrics: node.metrics || {},
  }));
  const labeledById = new Map(normalizedNodes.map((node) => [node.id, node]));
  for (const edge of edges) {
    edge.sourceLabel = actorLabel(edge.source, labeledById, metadataIndex);
    edge.targetLabel = actorLabel(edge.target, labeledById, metadataIndex);
  }

  const coverage = activeViewCoverage(serverCoverage, edges);
  if (legacySectorFocus) {
    coverage.count_matching = edges.length;
    coverage.legacy_focus_partial = true;
  }

  return {
    schema: isV2 ? "v2" : "v1",
    nodes: normalizedNodes,
    nodesById: labeledById,
    edges,
    coverage,
    serverCoverage,
    coverageByLayer: payload.coverage_by_layer || {},
    scaleDomains: scaleDomains(payload, manifest, edges),
    diagnostics: payload.diagnostics || {},
    stocks: payload.stocks || {},
    rollups: payload.rollups || [],
    transactionTotals: payload.transaction_totals || {},
    units: unitContext,
    period: String(payload.period || manifest?.initial_period || `Quarter ${state.quarter}`),
    realization: payload.realization || manifest?.realization || {},
    timing: payload.timing || {},
    observability: payload.observability || {},
    capabilities: { ...(manifest?.capabilities || {}), ...(payload.capabilities || {}) },
  };
}

export function evidenceLabels(edge) {
  const labels = [];
  const basis = humanizeId(edge.evidenceBasis);
  const aggregation = humanizeId(edge.aggregation);
  const scope = humanizeId(edge.realizationScope);
  const recognition = humanizeId(edge.recognition);
  if (basis) labels.push(basis);
  if (aggregation && !aggregation.toLowerCase().includes("none")) labels.push(aggregation);
  if (scope) labels.push(scope);
  if (recognition) labels.push(recognition);
  return [...new Set(labels)];
}

export function currencySymbolForUnits(units = "million_eur_per_quarter") {
  const normalized = String(units).toLowerCase();
  if (normalized.includes("usd")) return "$";
  if (normalized.includes("eur")) return "€";
  if (normalized.includes("gbp")) return "£";
  if (normalized.includes("jpy")) return "¥";
  if (normalized.includes("chf")) return "CHF ";
  const currency = normalized.match(/(?:million|thousand)_([a-z]{3})(?:_|$)/)?.[1];
  return currency ? `${currency.toUpperCase()} ` : "€";
}

export function formatMoney(value, units = "million_eur_per_quarter") {
  const amount = finite(value);
  const sign = amount < 0 ? "−" : "";
  const magnitude = Math.abs(amount);
  const normalizedUnits = String(units).toLowerCase();
  const symbol = currencySymbolForUnits(normalizedUnits);
  const quarterly = normalizedUnits.includes("per_quarter") ? " / quarter" : "";
  if (magnitude >= 1000) {
    const billions = new Intl.NumberFormat("en", { maximumFractionDigits: 2 }).format(magnitude / 1000);
    return `${sign}${symbol}${billions}bn${quarterly}`;
  }
  const millions = new Intl.NumberFormat("en", { maximumFractionDigits: 2 }).format(magnitude);
  return `${sign}${symbol}${millions}m${quarterly}`;
}

export function coverageText(coverage) {
  if (!coverage) return "Coverage unavailable";
  const counts = `${coverage.count_returned.toLocaleString()} of ${coverage.count_matching.toLocaleString()} matching relationships`;
  const suppressed = Number(coverage.client_suppressed_count) > 0
    ? `; ${Number(coverage.client_suppressed_count).toLocaleString()} additional server-returned relationship${Number(coverage.client_suppressed_count) === 1 ? " was" : "s were"} hidden by the active view`
    : "";
  if (coverage.count_matching === 0 && !coverage.legacy_focus_partial) return "No matching relationships; no value is omitted";
  if (coverage.legacy_focus_partial) return `${coverage.count_returned.toLocaleString()} focus relationships found inside the legacy top-N response; complete focus coverage is unavailable`;
  if (coverage.legacy_amount_unknown || coverage.amount_matching == null || coverage.amount_returned == null) {
    if (!coverage.legacy_amount_unknown && coverage.domain_count > 1) {
      const target = Number.isFinite(coverage.target) ? ` at an ${Math.round(coverage.target * 100)}% target` : "";
      return `${counts}; value coverage is applied separately across ${coverage.domain_count.toLocaleString()} compatible measure domains${target}${suppressed}`;
    }
    return `${counts}; omitted value is unavailable for this legacy trace${suppressed}`;
  }
  const share = coverage.amount_matching > 0 ? coverage.amount_returned / coverage.amount_matching : 1;
  return `${counts} · ${(share * 100).toFixed(1)}% of matching value${suppressed}`;
}

export { bool as payloadBoolean };
