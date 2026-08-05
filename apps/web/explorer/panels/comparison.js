import { comparisonCoverageText, DELTA_CLASSES } from "../comparison.js";
import { formatMoney } from "../model/edges.js";
import { humanizeId } from "../metadata.js";

export const COMPARISON_CSS_CLASSES = Object.freeze([
  "comparison-panel",
  "comparison-panel__header",
  "comparison-panel__title",
  "comparison-badge",
  "comparison-badge--paired",
  "comparison-badge--descriptive",
  "comparison-context",
  "comparison-shock",
  "comparison-warning",
  "comparison-domain-list",
  "comparison-domain",
  "comparison-domain__counts",
  "comparison-spec-diff",
  "comparison-spec-diff__row",
  "comparison-delta-table",
  "comparison-delta",
  "comparison-delta--added",
  "comparison-delta--removed",
  "comparison-delta--increased",
  "comparison-delta--decreased",
  "comparison-delta--unchanged",
  "comparison-delta__value",
  "comparison-delta__value--positive",
  "comparison-delta__value--negative",
]);

function element(tag, className = "", text = "") {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== "") node.textContent = text;
  return node;
}

export function formatComparisonValue(value, units) {
  if (value == null || !Number.isFinite(Number(value))) return "Not present";
  if (/^million_[a-z]{3}(?:_|$)/i.test(String(units))) {
    return formatMoney(Number(value), units);
  }
  return `${new Intl.NumberFormat("en", { maximumFractionDigits: 3 }).format(Number(value))} ${humanizeId(units)}`.trim();
}

function formatSpecValue(value) {
  if (value === undefined) return "Not set";
  if (value === null) return "null";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function deltaLabel(value) {
  return humanizeId(value || "unchanged");
}

function appendHeader(root, model, runALabel, runBLabel) {
  const header = element("header", "comparison-panel__header");
  const copy = element("div");
  const eyebrow = element("p", "eyebrow", "Synchronized run comparison");
  const title = element("h2", "comparison-panel__title", `${runALabel} → ${runBLabel}`);
  title.id = "comparison-title";
  copy.append(eyebrow, title);
  const badge = element(
    "span",
    `comparison-badge comparison-badge--${model.badge.kind}`,
    model.badge.label,
  );
  badge.title = model.badge.explanation;
  header.append(copy, badge);
  root.append(header);

  const context = element(
    "p",
    "comparison-context",
    `${model.period} · ${humanizeId(model.altitude)} · ${model.realizationScope === "representative"
      ? "representative-realization network"
      : humanizeId(model.realizationScope)}. ${model.badge.explanation}`,
  );
  root.append(context);
}

function appendShock(root, model) {
  const shock = element("section", "comparison-shock");
  const heading = element("strong", "", model.shock.label);
  let timing;
  if (!model.shock.explicit) {
    timing = "Shock-quarter context was not supplied by the comparison endpoint.";
  } else if (model.shock.position === "before") {
    timing = `Selected quarter is before the declared shock onset in quarter ${model.shock.quarter}.`;
  } else if (model.shock.position === "onset") {
    timing = `Selected quarter is the declared shock onset (quarter ${model.shock.quarter}).`;
  } else {
    timing = `Selected quarter is after the declared shock onset in quarter ${model.shock.quarter}.`;
  }
  const details = [];
  if (model.shock.magnitude != null) {
    details.push(`Magnitude ${model.shock.magnitude.toLocaleString()}${model.shock.units ? ` ${model.shock.units}` : ""}`);
  }
  if (model.shock.duration != null) details.push(`duration ${model.shock.duration.toLocaleString()} quarters`);
  const copy = element("span", "", `${timing}${details.length ? ` ${details.join(" · ")}.` : ""}`);
  shock.append(heading, copy);
  root.append(shock);
}

function appendWarnings(root, model) {
  const warnings = [...new Set(model.warnings || [])];
  for (const warning of warnings) {
    const row = element("p", "comparison-warning", warning);
    row.setAttribute("role", "note");
    root.append(row);
  }
}

function countPhrase(domain) {
  return DELTA_CLASSES
    .filter((name) => domain.counts[name] > 0)
    .map((name) => `${domain.counts[name].toLocaleString()} ${name}`)
    .join(" · ") || "No changes above tolerance";
}

function appendDomains(root, model) {
  const section = element("section");
  const heading = element("h3", "", "Delta coverage by compatible measure");
  const coverage = element("p", "comparison-context", comparisonCoverageText(model));
  const list = element("div", "comparison-domain-list");
  for (const domain of model.domains) {
    const card = element("article", "comparison-domain");
    const title = element("strong", "", `${humanizeId(domain.layer)} · ${humanizeId(domain.measureKind)}`);
    const basis = element(
      "span",
      "",
      `${humanizeId(domain.units)} · ${humanizeId(domain.recognition)} · ${humanizeId(domain.valuationBasis)}`,
    );
    const counts = element("span", "comparison-domain__counts", countPhrase(domain));
    const caveat = element("small", "", "Counts and value coverage apply only to this domain; values are not added to other measures.");
    card.append(title, basis, counts, caveat);
    list.append(card);
  }
  section.append(heading, coverage, list);
  root.append(section);
}

function appendSpecDiff(root, model) {
  const section = element("details", "comparison-spec-diff");
  const summary = element(
    "summary",
    "",
    `Run-spec difference (${model.runSpecDiff.length.toLocaleString()})`,
  );
  section.append(summary);
  if (!model.runSpecDiff.length) {
    section.append(element("p", "comparison-context", "No run-spec difference was returned."));
  }
  for (const change of model.runSpecDiff) {
    const row = element("div", "comparison-spec-diff__row");
    const path = element("strong", "", change.path);
    const values = element("span", "", `${formatSpecValue(change.before)} → ${formatSpecValue(change.after)}`);
    const classification = element(
      "small",
      "",
      change.source === "client"
        ? "Client-derived descriptive context; not pairing evidence"
        : humanizeId(change.classification),
    );
    row.append(path, values, classification);
    section.append(row);
  }
  root.append(section);
}

function appendDeltaTable(root, model, onSelect, maxRows) {
  const section = element("section");
  const heading = element("h3", "", `Changed relationships (${model.edges.length.toLocaleString()})`);
  const wrap = element("div", "table-wrap");
  const table = element("table", "comparison-delta-table");
  const caption = element(
    "caption",
    "",
    model.zeroDelta
      ? `No relationship changed beyond the declared tolerance of ${model.tolerance}.`
      : `Showing ${Math.min(maxRows, model.edges.length).toLocaleString()} of ${model.edges.length.toLocaleString()} changed relationships. Each row stays in its declared measure domain.`,
  );
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  for (const label of ["Relationship", "From → to", "Class", "Run A", "Run B", "Δ (B − A)"]) {
    const cell = element("th", "", label);
    cell.scope = "col";
    headRow.append(cell);
  }
  head.append(headRow);
  const body = document.createElement("tbody");
  const sorted = [...model.edges].sort(
    (a, b) => Math.abs(b.delta) - Math.abs(a.delta) || a.id.localeCompare(b.id),
  );
  for (const edge of sorted.slice(0, maxRows)) {
    const row = element("tr", edge.cssClass);
    row.dataset.edgeId = edge.id;
    const relationship = document.createElement("td");
    const button = element("button", "row-button", edge.label);
    button.type = "button";
    button.addEventListener("click", () => onSelect?.({ type: "edge", ...edge }));
    relationship.append(button);
    const actors = element("td", "", `${edge.sourceLabel} → ${edge.targetLabel}`);
    const classification = element("td", "", deltaLabel(edge.deltaClass));
    const before = element("td", "comparison-delta__value", formatComparisonValue(edge.amountA, edge.units));
    const after = element("td", "comparison-delta__value", formatComparisonValue(edge.amountB, edge.units));
    const deltaTone = edge.delta > 0
      ? "comparison-delta__value--positive"
      : edge.delta < 0
        ? "comparison-delta__value--negative"
        : "";
    const delta = element(
      "td",
      `comparison-delta__value ${deltaTone}`.trim(),
      `${edge.delta > 0 ? "+" : ""}${formatComparisonValue(edge.delta, edge.units)}`,
    );
    row.append(relationship, actors, classification, before, after, delta);
    body.append(row);
  }
  table.append(caption, head, body);
  wrap.append(table);
  section.append(heading, wrap);
  root.append(section);
}

/**
 * Render the complete comparison panel into one host element.
 *
 * Required markup:
 *   <section id="comparison-panel" class="comparison-panel"
 *            aria-labelledby="comparison-title" hidden></section>
 */
export function renderComparisonPanel(root, model, {
  runALabel = model?.runA || "Run A",
  runBLabel = model?.runB || "Run B",
  onSelect = null,
  maxRows = 100,
} = {}) {
  if (!root) return;
  root.replaceChildren();
  if (!model) {
    root.hidden = true;
    return;
  }
  root.hidden = false;
  root.classList.add("comparison-panel");
  root.setAttribute("aria-labelledby", "comparison-title");
  appendHeader(root, model, runALabel, runBLabel);
  appendShock(root, model);
  appendWarnings(root, model);
  appendDomains(root, model);
  appendSpecDiff(root, model);
  appendDeltaTable(root, model, onSelect, Math.max(1, Math.trunc(maxRows)));
}
