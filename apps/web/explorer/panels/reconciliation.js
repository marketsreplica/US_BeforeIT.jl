import { payloadBoolean } from "../model/edges.js";

function title(key) {
  return String(key).replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatResidual(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return "Unavailable";
  if (number === 0) return "0";
  return number.toExponential(3);
}

function appendRow(root, labelText, valueText, failed = false) {
  const row = document.createElement("div");
  row.className = "diagnostic-row";
  const label = document.createElement("span");
  label.textContent = labelText;
  const value = document.createElement("span");
  value.textContent = valueText;
  if (failed) value.style.color = "var(--coral)";
  row.append(label, value);
  root.append(row);
}

export function renderReconciliation(elements, model = {}) {
  const diagnostics = model.diagnostics || {};
  const tolerance = Number(diagnostics.tolerance);
  const rows = Object.entries(diagnostics)
    .filter(([key, value]) => key.endsWith("_residual") && Number.isFinite(Number(value)))
    .sort(([a], [b]) => a.localeCompare(b));
  const explicit = diagnostics.passed == null ? null : payloadBoolean(diagnostics.passed);
  const derived = rows.length > 0 && Number.isFinite(tolerance)
    ? rows.every(([, value]) => Math.abs(Number(value)) <= tolerance)
    : null;
  const passed = explicit ?? derived;
  elements.dot.className = passed === true ? "pass" : passed === false ? "fail" : "";
  elements.root.replaceChildren();
  const note = document.createElement("p");
  note.className = "inspector-explanation";
  note.textContent = rows.length
    ? `Residuals are checked against the run's declared tolerance of ${Number.isFinite(tolerance) ? tolerance.toExponential(3) : "an unavailable value"}. Definitions and independent checks are kept distinct in the trace.`
    : "Detailed accounting diagnostics are unavailable for this historical run.";
  elements.root.append(note);
  for (const [key, value] of rows) {
    const kind = diagnostics.identity_kinds?.[key];
    appendRow(
      elements.root,
      `${title(key)}${kind ? ` · ${title(kind)}` : ""}`,
      formatResidual(value),
      Number.isFinite(tolerance) && Math.abs(Number(value)) > tolerance,
    );
  }

  for (const rollup of model.rollups || []) {
    const components = Object.values(rollup.component_totals || {}).map(Number).filter(Number.isFinite);
    const componentTotal = components.reduce((sum, value) => sum + value, 0);
    const residual = Number(rollup.amount) - componentTotal;
    const details = document.createElement("details");
    const summary = document.createElement("summary");
    summary.textContent = `${rollup.label || title(rollup.id)} · components ${formatResidual(residual)} residual`;
    details.append(summary);
    for (const [component, value] of Object.entries(rollup.component_totals || {}).sort(([a], [b]) => a.localeCompare(b))) {
      appendRow(details, title(component), Number(value).toLocaleString(undefined, { maximumFractionDigits: 3 }));
    }
    appendRow(
      details,
      "Component sum → declared parent",
      `${componentTotal.toLocaleString(undefined, { maximumFractionDigits: 3 })} → ${Number(rollup.amount).toLocaleString(undefined, { maximumFractionDigits: 3 })}`,
      Number.isFinite(tolerance) && Math.abs(residual) > tolerance,
    );
    elements.root.append(details);
  }

  const stockEntries = Object.entries(model.stocks || {}).filter(([, stock]) => Number.isFinite(Number(stock?.open)) && Number.isFinite(Number(stock?.close)));
  if (stockEntries.length) {
    const details = document.createElement("details");
    const summary = document.createElement("summary");
    summary.textContent = "Opening → closing stock positions";
    details.append(summary);
    for (const [key, stock] of stockEntries) {
      const open = Number(stock.open);
      const close = Number(stock.close);
      appendRow(
        details,
        title(key),
        `${open.toLocaleString(undefined, { maximumFractionDigits: 2 })} → ${close.toLocaleString(undefined, { maximumFractionDigits: 2 })} (${close - open >= 0 ? "+" : ""}${(close - open).toLocaleString(undefined, { maximumFractionDigits: 2 })})`,
      );
    }
    const caveat = document.createElement("p");
    caveat.className = "inspector-explanation";
    caveat.textContent = "These are exact opening and closing positions. A stock-flow identity is claimed only where the diagnostic list supplies the corresponding classified-flow residual.";
    details.append(caveat);
    elements.root.append(details);
  }
  return passed;
}
