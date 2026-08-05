export function defaultSectorFocus(model) {
  const totals = new Map();
  for (const edge of model.edges || []) {
    for (const id of [edge.source, edge.target]) {
      if (String(id).startsWith("sector:")) totals.set(id, (totals.get(id) || 0) + edge.amount);
    }
  }
  return [...totals].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], undefined, { numeric: true }))[0]?.[0]
    || model.nodes.find((node) => node.id.startsWith("sector:"))?.id
    || null;
}

export function sectorsDescriptor(model, focus = null) {
  const node = focus ? model.nodesById.get(focus) : null;
  const breadcrumbs = [{ altitude: "economy", label: "Economy" }, { altitude: "sectors", label: "Sectors" }];
  if (node) breadcrumbs.push({ altitude: "sectors", focus: node.id, label: node.label });
  return {
    title: node?.label || "Named sectors",
    subtitle: node ? "Sector suppliers, customers, and institutions" : "Dataset-scoped sector communities",
    breadcrumbs,
    summary: `${model.nodes.filter((item) => item.kind === "sector").length.toLocaleString()} sectors and ${model.edges.length.toLocaleString()} returned relationships.`,
  };
}
