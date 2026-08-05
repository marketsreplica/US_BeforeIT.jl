import { formatMoney, LAYERS } from "../model/edges.js";

function finite(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function normalizeAccount(raw, fallbackUnits = "million_eur") {
  if (!raw || typeof raw !== "object") return null;
  const opening = finite(raw.opening_value ?? raw.openingValue);
  const change = finite(raw.recorded_change ?? raw.recordedChange);
  const closing = finite(raw.closing_value ?? raw.closingValue);
  const residual = finite(raw.reconciliation_residual ?? raw.reconciliationResidual ?? raw.residual);
  const tolerance = finite(raw.reconciliation_tolerance ?? raw.reconciliationTolerance ?? raw.tolerance);
  if ([opening, change, closing, residual, tolerance].some((value) => value == null)) return null;
  return {
    id: String(raw.account_id ?? raw.accountId ?? "deposit-account"),
    kind: String(raw.account_kind ?? raw.accountKind ?? "deposit_or_overdraft_position"),
    holder: String(raw.account_holder_node_id ?? raw.accountHolderNodeId ?? ""),
    counterparty: String(raw.account_counterparty_node_id ?? raw.accountCounterpartyNodeId ?? "bank"),
    level: String(raw.account_level ?? raw.accountLevel ?? "unknown"),
    aggregation: String(raw.account_aggregation ?? raw.accountAggregation ?? "unknown"),
    units: String(raw.account_units ?? raw.accountUnits ?? fallbackUnits),
    opening,
    change,
    closing,
    residual,
    tolerance,
    status: String(raw.reconciliation_status ?? raw.reconciliationStatus ?? (Math.abs(residual) <= tolerance ? "within_tolerance" : "outside_tolerance")),
    basis: String(raw.reconciliation_basis ?? raw.reconciliationBasis ?? "opening_plus_snapshot_derived_change_equals_closing"),
    evidence: String(raw.reconciliation_evidence_basis ?? raw.reconciliationEvidenceBasis ?? "exact_model_state_snapshots"),
    cashflowIdentitySupported: Boolean(raw.classified_cashflow_identity_supported ?? raw.classifiedCashflowIdentitySupported),
    explanation: String(raw.reconciliation_explanation ?? raw.reconciliationExplanation ?? ""),
  };
}

function accountsForNode(selection, model) {
  const rawAccounts = Array.isArray(selection?.account_reconciliations)
    ? selection.account_reconciliations
    : Array.isArray(selection?.accountReconciliations)
      ? selection.accountReconciliations
      : [];
  const candidates = [...rawAccounts];
  for (const edge of model?.edges || []) {
    const holder = String(edge.account_holder_node_id ?? edge.accountHolderNodeId ?? "");
    if (holder === selection?.id && (edge.account_id || edge.accountId)) candidates.push(edge);
  }
  const byId = new Map();
  const fallbackUnits = model?.units?.stock || model?.units?.stock_units || "million_eur";
  for (const candidate of candidates) {
    const account = normalizeAccount(candidate, fallbackUnits);
    if (account && account.holder === selection.id && !byId.has(account.id)) byId.set(account.id, account);
  }
  return [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
}

function recordedMoneyEndpoints(edge) {
  const signed = Number(edge.signedValue ?? edge.signed_value ?? edge.amount ?? 0);
  const canonicalSource = String(edge.canonicalSource ?? edge.canonical_source ?? edge.source ?? "");
  const canonicalTarget = String(edge.canonicalTarget ?? edge.canonical_target ?? edge.target ?? "");
  return signed >= 0
    ? [canonicalSource, canonicalTarget]
    : [canonicalTarget, canonicalSource];
}

function visibleCategoryFlows(nodeId, model) {
  const byLayer = new Map();
  for (const edge of model?.edges || []) {
    if (edge.legacy || String(edge.recognition || edge.cash_recognition || "") !== "realized_cash") continue;
    const [source, target] = recordedMoneyEndpoints(edge);
    if (source !== nodeId && target !== nodeId) continue;
    const layer = String(edge.layer || edge.category || "other");
    if (!byLayer.has(layer)) {
      byLayer.set(layer, {
        layer,
        inflow: 0,
        outflow: 0,
        count: 0,
        units: String(edge.units || model?.units?.flow || "million_eur_per_quarter"),
      });
    }
    const entry = byLayer.get(layer);
    const amount = Math.abs(Number(edge.amount ?? edge.signedValue ?? 0)) || 0;
    if (target === nodeId) entry.inflow += amount;
    if (source === nodeId) entry.outflow += amount;
    entry.count += 1;
  }
  return [...byLayer.values()].sort((a, b) => {
    const orderA = LAYERS[a.layer]?.order ?? 999;
    const orderB = LAYERS[b.layer]?.order ?? 999;
    return orderA - orderB || a.layer.localeCompare(b.layer);
  });
}

function queryScope(state, model, flowCount) {
  const reasons = [];
  if (Number(state?.coverage) < 0.999999) reasons.push(`${Math.round(Number(state.coverage) * 100)}% value-coverage target`);
  if (state?.focus && state.focus !== "all") reasons.push("actor focus");
  if (state?.parent) reasons.push("aggregation-path filter");
  if (state?.question) reasons.push("question preset");
  if (state?.layers?.length) reasons.push("layer selection");
  if (Number(model?.coverage?.client_suppressed_count) > 0) reasons.push("expanded parents suppressed");
  const matching = Number(model?.serverCoverage?.count_matching ?? model?.coverage?.count_matching);
  const returned = Number(model?.serverCoverage?.count_returned ?? model?.coverage?.server_count_returned ?? model?.coverage?.count_returned);
  if (Number.isFinite(matching) && Number.isFinite(returned) && returned < matching) reasons.push("server coverage or page truncation");
  const exact = model?.schema === "v2";
  return {
    exact,
    partial: reasons.length > 0,
    text: `${exact ? "Exact normalized" : "Legacy/adapted"} current-query context: ${flowCount.toLocaleString()} realized-cash relationship${flowCount === 1 ? "" : "s"} classified around this node${reasons.length ? `; scope is partial (${[...new Set(reasons)].join(", ")})` : "; no active query restriction was detected"}. These chips describe returned context only and are not terms in the deposit-stock identity.`,
  };
}

export function buildNodeStockFlowView(selection, model = {}, state = {}) {
  if (!selection || selection.type !== "node" || state.comparison) return null;
  const accounts = accountsForNode(selection, model);
  if (!accounts.length) return null;
  const categories = visibleCategoryFlows(selection.id, model);
  const relationshipCount = categories.reduce((sum, category) => sum + category.count, 0);
  return {
    accounts,
    categories,
    scope: queryScope(state, model, relationshipCount),
    openingSnapshot: Number(state.quarter) === 0,
  };
}

function signedMoney(value, units) {
  const formatted = formatMoney(value, units);
  return Number(value) > 0 ? `+${formatted}` : formatted;
}

function appendEquation(root, account) {
  const equation = document.createElement("div");
  equation.className = "node-reconciliation__equation";
  const terms = [
    ["Opening", formatMoney(account.opening, account.units)],
    ["+ recorded change", signedMoney(account.change, account.units)],
    ["= closing", formatMoney(account.closing, account.units)],
  ];
  for (const [label, value] of terms) {
    const term = document.createElement("span");
    const name = document.createElement("small");
    const amount = document.createElement("strong");
    name.textContent = label;
    amount.textContent = value;
    term.append(name, amount);
    equation.append(term);
  }
  root.append(equation);
}

export function renderNodeStockFlow(root, selection, model = {}, state = {}) {
  if (!root) return;
  if (selection?.type === "node" && state.comparison) {
    root.replaceChildren();
    root.hidden = false;
    const heading = document.createElement("h3");
    heading.textContent = "Node stock–flow proof unavailable";
    const note = document.createElement("p");
    note.className = "node-reconciliation__scope partial";
    note.textContent = "The comparison endpoint supplies paired relationship deltas, but no paired A/B node snapshots. Quarter-0 directory values are used only for actor identity and layout, so node metrics and deposit reconciliation are deliberately suppressed here.";
    root.append(heading, note);
    return;
  }
  const view = buildNodeStockFlowView(selection, model, state);
  root.replaceChildren();
  root.hidden = !view;
  if (!view) return;

  const heading = document.createElement("h3");
  heading.textContent = "Deposit stock–flow record";
  root.append(heading);
  for (const account of view.accounts) {
    const accountRoot = document.createElement("div");
    accountRoot.className = "node-reconciliation__account";
    appendEquation(accountRoot, account);
    const status = document.createElement("p");
    const passes = Math.abs(account.residual) <= account.tolerance && account.status === "within_tolerance";
    status.className = `node-reconciliation__status ${passes ? "pass" : "fail"}`;
    status.textContent = `${passes ? "Within tolerance" : "Outside tolerance"} · residual ${account.residual.toExponential(3)} · tolerance ${account.tolerance.toExponential(3)}`;
    const caveat = document.createElement("p");
    caveat.className = "node-reconciliation__caveat";
    caveat.textContent = `${view.openingSnapshot ? "Opening snapshot: the recorded change is zero by construction. " : ""}${account.explanation || "Exact opening and closing snapshots with their recorded signed difference."} No general cash-accounting identity is claimed.`;
    accountRoot.append(status, caveat);
    root.append(accountRoot);
  }

  const categoryTitle = document.createElement("h4");
  categoryTitle.textContent = "Current visible query · classified cash context";
  const chips = document.createElement("div");
  chips.className = "node-flow-chips";
  if (!view.categories.length) {
    const empty = document.createElement("span");
    empty.className = "node-flow-chip empty";
    empty.textContent = "No realized-cash relationships returned";
    chips.append(empty);
  } else {
    for (const category of view.categories) {
      const chip = document.createElement("span");
      chip.className = "node-flow-chip";
      chip.dataset.layer = category.layer;
      const label = document.createElement("strong");
      label.textContent = LAYERS[category.layer]?.label || category.layer.replace(/_/g, " ");
      const values = document.createElement("small");
      values.textContent = `in ${formatMoney(category.inflow, category.units)} · out ${formatMoney(category.outflow, category.units)} · ${category.count} returned`;
      chip.append(label, values);
      chips.append(chip);
    }
  }
  const scope = document.createElement("p");
  scope.className = `node-reconciliation__scope ${view.scope.partial ? "partial" : ""}`;
  scope.textContent = view.scope.text;
  root.append(categoryTitle, chips, scope);
}
