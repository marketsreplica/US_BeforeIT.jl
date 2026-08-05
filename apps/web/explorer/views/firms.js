export function defaultFirmFocus(model) {
  const firms = model.nodes.filter((node) => node.kind === "firm" || node.id.startsWith("firm:"));
  firms.sort((a, b) => {
    const employment = (Number(b.metrics?.employment) || 0) - (Number(a.metrics?.employment) || 0);
    return employment || String(a.id).localeCompare(String(b.id), undefined, { numeric: true });
  });
  return firms[0]?.id || null;
}

export function firmsDescriptor(model, focus = null) {
  const node = focus && focus !== "all" ? model.nodesById.get(focus) : null;
  const breadcrumbs = [
    { altitude: "economy", label: "Economy" },
    { altitude: "sectors", label: node?.sector ? `Sector ${node.sector}` : "Sectors" },
    { altitude: "firms", label: focus === "all" ? "All firms" : node?.label || "Firms" },
  ];
  return {
    title: node?.label || (focus === "all" ? "Whole firm economy" : "Synthetic firms"),
    subtitle: node ? "One-hop production and institutional ego network" : "Firm communities and bundled relationships",
    breadcrumbs,
    summary: `${model.nodes.filter((item) => item.kind === "firm").length.toLocaleString()} returned synthetic firms and ${model.edges.length.toLocaleString()} relationships.`,
  };
}
