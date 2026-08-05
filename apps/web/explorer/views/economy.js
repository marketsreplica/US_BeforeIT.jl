export function economyDescriptor(model) {
  return {
    title: "Economy",
    subtitle: "Institutions and macro monetary circuit",
    breadcrumbs: [{ altitude: "economy", label: "Economy" }],
    summary: `${model.nodes.length.toLocaleString()} actors and ${model.edges.length.toLocaleString()} returned relationships in the macro circuit.`,
  };
}
