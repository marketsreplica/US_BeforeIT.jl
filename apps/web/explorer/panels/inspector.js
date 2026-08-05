import { evidenceLabels, formatMoney } from "../model/edges.js";
import { isHouseholdCohortId } from "../metadata.js";
import { renderNodeStockFlow } from "./node-reconciliation.js";

function humanize(value) {
  return String(value || "")
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function formatMetric(key, value, personMultiplier = 1, monetaryUnits = null) {
  if (typeof value !== "number") return String(value ?? "—");
  if (/rate|share|ratio/i.test(key)) return `${(value * 100).toFixed(2)}%`;
  if (/employment|agents/i.test(key)) {
    const multiplier = Number(personMultiplier);
    const representedValue = value * (Number.isFinite(multiplier) && multiplier > 0 ? multiplier : 1);
    return Math.round(representedValue).toLocaleString();
  }
  if (/firms|count/i.test(key)) return Math.round(value).toLocaleString();
  if (/deposit|loan|equity|profit|sales|production|debt|position|revenue/i.test(key)) {
    const isStock = /deposit|loan|equity|debt|position/i.test(key);
    const units = typeof monetaryUnits === "string"
      ? monetaryUnits
      : monetaryUnits?.[isStock ? "stock" : "flow"];
    return formatMoney(value, units || (isStock ? "million_eur" : "million_eur_per_quarter"));
  }
  return new Intl.NumberFormat("en", { maximumFractionDigits: 2 }).format(value);
}

function fillDefinitionList(root, entries, { personMultiplier = 1, monetaryUnits = null } = {}) {
  root.replaceChildren();
  for (const [key, value] of entries) {
    const term = document.createElement("dt");
    term.textContent = String(key).toLowerCase() === "agents" ? "People" : humanize(key);
    const definition = document.createElement("dd");
    definition.textContent = formatMetric(key, value, personMultiplier, monetaryUnits);
    root.append(term, definition);
  }
}

function renderEdgeHistory(root, selection, isComparison) {
  if (!root) return;
  root.replaceChildren();
  if (!selection || selection.type !== "edge") {
    root.hidden = true;
    return;
  }
  root.hidden = false;
  const heading = document.createElement("strong");
  heading.textContent = "Recorded-quarter history";
  root.append(heading);
  if (isComparison) {
    const note = document.createElement("small");
    note.textContent = "A/B history is not claimed by this endpoint. Exit comparison to inspect the stable edge in one run.";
    root.append(note);
    return;
  }
  if (selection.historyError) {
    const note = document.createElement("small");
    note.textContent = `History unavailable: ${selection.historyError}`;
    root.append(note);
    return;
  }
  if (!Array.isArray(selection.history)) {
    const note = document.createElement("small");
    note.textContent = "Loading the same stable relationship ID across recorded quarters…";
    root.append(note);
    return;
  }
  const history = selection.history;
  if (!history.length) {
    const note = document.createElement("small");
    note.textContent = "No recorded quarters are available.";
    root.append(note);
    return;
  }
  const namespace = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(namespace, "svg");
  svg.setAttribute("viewBox", "0 0 260 58");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", history.map((point) => `${point.period}: ${formatMoney(point.amount, selection.units)}`).join("; "));
  const amounts = history.map((point) => Math.max(0, Number(point.amount) || 0));
  const maximum = Math.max(1e-12, ...amounts);
  const xFor = (index) => history.length === 1 ? 130 : 6 + index * (248 / (history.length - 1));
  const yFor = (amount) => 51 - Math.sqrt(amount / maximum) * 43;
  const polyline = document.createElementNS(namespace, "polyline");
  polyline.setAttribute("points", amounts.map((amount, index) => `${xFor(index)},${yFor(amount)}`).join(" "));
  svg.append(polyline);
  history.forEach((point, index) => {
    const circle = document.createElementNS(namespace, "circle");
    circle.setAttribute("cx", String(xFor(index)));
    circle.setAttribute("cy", String(yFor(amounts[index])));
    circle.setAttribute("r", point.present ? "3" : "2");
    const title = document.createElementNS(namespace, "title");
    title.textContent = `${point.period}: ${formatMoney(point.amount, selection.units)}${point.present ? "" : " · absent / zero"}`;
    circle.append(title);
    svg.append(circle);
  });
  const note = document.createElement("small");
  note.textContent = `${history[0].period} → ${history.at(-1).period} · square-root vertical scale · absent stable IDs shown as zero`;
  root.append(svg, note);
}

export function renderInspector(elements, selection, model, state) {
  const panel = elements.panel;
  if (!selection) {
    panel.hidden = true;
    return;
  }
  panel.hidden = false;
  const isEdge = selection.type === "edge";
  const inComparison = Boolean(state.comparison);
  const isComparison = Boolean(inComparison && isEdge && selection.deltaClass);
  renderEdgeHistory(elements.history, selection, isComparison);
  renderNodeStockFlow(elements.reconciliation, selection, model, state);
  elements.kicker.textContent = isComparison
    ? "Comparison delta receipt"
    : inComparison && !isEdge
      ? "Comparison actor · identity only"
      : isEdge
        ? "Relationship receipt"
        : "Selected actor";
  elements.title.textContent = isEdge ? selection.label : selection.label || selection.id;
  elements.subtitle.textContent = isEdge
    ? `${selection.sourceLabel || selection.source} → ${selection.targetLabel || selection.target}`
    : humanize(selection.kind || selection.id.split(":")[0]);

  elements.badges.replaceChildren();
  if (isEdge) {
    for (const label of evidenceLabels(selection)) {
      const badge = document.createElement("span");
      badge.textContent = label;
      elements.badges.append(badge);
    }
    const receiptMetrics = [
      ...(isComparison ? [
        ["run A", formatMoney(selection.amountA, selection.units)],
        ["run B", formatMoney(selection.amountB, selection.units)],
        ["delta B minus A", formatMoney(selection.delta, selection.units)],
        ["change class", humanize(selection.deltaClass)],
      ] : [["amount", formatMoney(selection.amount, selection.units)]]),
      ["quantity", selection.quantityAvailable ? selection.quantity : "Not retained"],
      ["match count", selection.matchCountAvailable ? selection.matchCount : "Not retained"],
      ["layer", humanize(selection.layer)],
      ["purpose", humanize(selection.purpose)],
      ["timing", humanize(selection.timing)],
      ["valuation basis", humanize(selection.valuationBasis)],
    ];
    if (selection.good != null) receiptMetrics.splice(3, 0, ["good index", Number(selection.good)]);
    if (selection.stage) receiptMetrics.splice(4, 0, ["transaction stage", humanize(selection.stage)]);
    if (selection.buyer_kind) receiptMetrics.push(["buyer class", humanize(selection.buyer_kind)]);
    if (selection.seller_kind) receiptMetrics.push(["seller class", humanize(selection.seller_kind)]);
    fillDefinitionList(elements.metrics, receiptMetrics);
    elements.explanation.textContent = isComparison
      ? `${selection.explanation || "Stable-ID difference between the synchronized runs."} This is a run-level simulated contrast, not a uniquely identified causal path for this edge.`
      : selection.explanation || defaultEdgeExplanation(selection);
    elements.path.textContent = isComparison
      ? "Comparison path: complete Run A and Run B edge sets → stable semantic-ID join → compatible-measure coverage → visible delta."
      : aggregationPath(selection, state);
    elements.drill.hidden = isComparison || state.altitude === "firms";
    elements.rollup.hidden = isComparison || state.altitude === "economy";
  } else if (inComparison) {
    fillDefinitionList(elements.metrics, [
      ["A/B node metrics", "Not provided by the comparison endpoint"],
      ["Stock–flow proof", "Suppressed without paired node snapshots"],
    ]);
    elements.explanation.textContent = "This actor is a stable endpoint used to lay out and label the paired relationship deltas. Its single-run directory metrics are not evidence about Run A versus Run B.";
    elements.path.textContent = "Comparison node evidence stops at identity and classification. Inspect either run separately for quarter-specific node metrics and deposit stock–flow reconciliation.";
    elements.drill.hidden = true;
    elements.rollup.hidden = true;
  } else {
    fillDefinitionList(elements.metrics, Object.entries(selection.metrics || {}), {
      personMultiplier: state.metadata?.person_multiplier,
      monetaryUnits: state.manifest?.units,
    });
    elements.explanation.textContent = actorExplanation(selection);
    elements.path.textContent = `This synthetic actor is shown in ${state.altitude} context for ${model.period}.`;
    elements.drill.hidden = selection.kind === "firm" || state.altitude === "firms";
    elements.rollup.hidden = state.altitude === "economy";
  }
}

function defaultEdgeExplanation(edge) {
  if (edge.layer === "capacity") return "A non-cash second-pass match against unused productive capacity. It is not an observed payment or a general unmet-demand measure.";
  if (edge.measureKind === "stock" || edge.layer === "stocks") return "A financial position measured at a recorded snapshot, not a quarterly payment.";
  if (edge.market === "business_goods") return "A recorded business-input relationship. Materials and capital goods were combined before seller matching in this model version.";
  if (edge.purpose === "household_final_demand") return "A recorded household final-demand receipt. Consumption and housing investment were combined before seller matching and cannot be separated exactly here.";
  return "The relationship is drawn from the selected run using the evidence and aggregation badges shown above.";
}

function actorExplanation(node) {
  if (node.kind === "firm") return "A synthetic model firm, not a real legal company. Its sector, transactions, and balance-sheet fields come from the selected realization.";
  if (node.kind === "sector") return "A dataset-scoped sector grouping. Sector relationships aggregate the model firms assigned to this classification.";
  if (node.id === "bank") return "The model's representative commercial-bank institution. It is distinct from firms in the financial-services sectors.";
  if (node.kind === "household_cohort" || isHouseholdCohortId(node.id)) {
    return "A synthetic household role cohort in this simulation, not an individual household or a demographic microdata record.";
  }
  return "An institution or aggregate actor in the selected simulated economy.";
}

function aggregationPath(edge, state) {
  const parts = [];
  if (state.altitude === "firms") parts.push("receipt / firm relationship");
  if (state.altitude !== "economy") parts.push("sector roll-up");
  parts.push(edge.rollupId ? humanize(edge.rollupId) : edge.parentIds?.length ? humanize(edge.parentIds[0]) : "related macro account");
  return `Aggregation path: ${parts.join(" → ")}. Intermediate business receipts reconcile to turnover and input use; only identified final demand reconciles to expenditure accounts.`;
}
