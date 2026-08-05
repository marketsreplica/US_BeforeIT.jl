import { evidenceLabels, formatMoney } from "../model/edges.js";

function matchesFilter(edge, query) {
  if (!query) return true;
  const haystack = [
    edge.label,
    edge.sourceLabel,
    edge.targetLabel,
    edge.layer,
    edge.purpose,
    edge.evidenceBasis,
    edge.recognition,
  ].join(" ").toLowerCase();
  return haystack.includes(query.toLowerCase());
}

export function relationshipTableCaption(matching, start, rowsShown, { comparison = false } = {}) {
  const range = matching ? `${start + 1}–${start + rowsShown}` : "none";
  const scope = comparison
    ? "This table contains returned comparison deltas only; comparison export is not available in this view."
    : "Export includes every server-matching relationship, not only this visual page.";
  return `${matching.toLocaleString()} returned relationships match this table query; showing ${range}. ${scope}`;
}

export function renderRelationshipTable(elements, model, { filter = "", onSelect, page = 0, pageSize = 75 } = {}) {
  const matching = (model?.edges || []).filter((edge) => matchesFilter(edge, filter));
  const pageCount = Math.max(1, Math.ceil(matching.length / pageSize));
  const safePage = Math.min(pageCount - 1, Math.max(0, Math.trunc(page)));
  const start = safePage * pageSize;
  const rows = matching.slice(start, start + pageSize);
  elements.body.replaceChildren();
  for (const edge of rows) {
    const row = document.createElement("tr");
    const relation = document.createElement("td");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "row-button";
    button.textContent = edge.label;
    button.addEventListener("click", () => onSelect?.({ type: "edge", ...edge }));
    button.addEventListener("focus", () => onSelect?.({ type: "edge", ...edge }));
    relation.append(button);
    const source = document.createElement("td");
    source.textContent = edge.sourceLabel;
    const target = document.createElement("td");
    target.textContent = edge.targetLabel;
    const amount = document.createElement("td");
    amount.textContent = formatMoney(edge.amount, edge.units);
    const evidence = document.createElement("td");
    evidence.textContent = evidenceLabels(edge).slice(0, 2).join(" · ");
    row.append(relation, source, target, amount, evidence);
    elements.body.append(row);
  }
  elements.count.textContent = `(${matching.length.toLocaleString()})`;
  elements.caption.textContent = relationshipTableCaption(matching.length, start, rows.length, {
    comparison: Boolean(model?.comparison),
  });
  elements.page.value = `Page ${safePage + 1} / ${pageCount}`;
  elements.prev.disabled = safePage === 0;
  elements.next.disabled = safePage >= pageCount - 1;
  return { page: safePage, pageCount, matching: matching.length };
}
