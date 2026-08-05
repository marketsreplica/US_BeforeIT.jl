import { sectorIdentity, numericActorId } from "../metadata.js";

function hash(text) {
  let value = 2166136261;
  for (const char of String(text)) {
    value ^= char.charCodeAt(0);
    value = Math.imul(value, 16777619);
  }
  return value >>> 0;
}

function jitter(id, amount = 10) {
  const value = hash(id);
  return { x: ((value & 0xff) / 255 - .5) * amount, y: (((value >> 8) & 0xff) / 255 - .5) * amount };
}

function nodeRadius(node, altitude) {
  if (altitude === "economy") return 31;
  if (node.kind === "firm") {
    const employment = Number(node.metrics?.employment) || 0;
    return Math.max(7, Math.min(19, 7 + Math.sqrt(employment) * .55));
  }
  if (node.kind === "sector") {
    const firms = Number(node.metrics?.firms) || 1;
    return Math.max(13, Math.min(27, 12 + Math.sqrt(firms) * 1.15));
  }
  if (String(node.id).startsWith("outside:")) return 9;
  return 18;
}

function cloneAt(node, x, y, altitude, extras = {}) {
  return { ...node, x, y, radius: nodeRadius(node, altitude), ...extras };
}

const ECONOMY_POSITIONS = Object.freeze({
  households: [-360, 130],
  "household:active-workers": [-420, 45],
  "household:inactive": [-410, 155],
  "household:firm-owners": [-330, 215],
  "household:bank-owner": [-250, 230],
  // Retain fixed placement for historical traces that used cohort:* aliases.
  "cohort:active_workers": [-420, 45],
  "cohort:inactive_households": [-410, 155],
  "cohort:firm_owners": [-330, 215],
  "cohort:bank_owner": [-250, 230],
  production: [-210, -75],
  "goods-market": [0, 0],
  government: [250, -145],
  bank: [275, 105],
  "central-bank": [465, 80],
  "outside-world": [460, -165],
});

function layoutEconomy(model) {
  const nodes = model.nodes.map((node, index) => {
    const position = ECONOMY_POSITIONS[node.id];
    if (position) return cloneAt(node, position[0], position[1], "economy");
    const angle = (index / Math.max(1, model.nodes.length)) * Math.PI * 2;
    return cloneAt(node, Math.cos(angle) * 410, Math.sin(angle) * 220, "economy");
  });
  return { nodes, edges: model.edges, focus: null, mode: "circuit" };
}

function isInstitution(node) {
  return !["sector", "firm", "outside_portal"].includes(String(node.kind)) &&
    !String(node.id).startsWith("sector:") && !String(node.id).startsWith("firm:") && !String(node.id).startsWith("outside:");
}

function incidentSubset(model, focusId) {
  const edges = model.edges.filter((edge) => edge.source === focusId || edge.target === focusId);
  const ids = new Set([focusId]);
  for (const edge of edges) {
    ids.add(edge.source);
    ids.add(edge.target);
  }
  return { edges, nodes: model.nodes.filter((node) => ids.has(node.id)) };
}

function verticalPositions(items, x, spacing = 68) {
  const count = items.length;
  return items.map((item, index) => ({ item, x, y: (index - (count - 1) / 2) * spacing }));
}

function layoutFocused(model, focusId, altitude) {
  const subset = incidentSubset(model, focusId);
  const focus = model.nodesById.get(focusId) || subset.nodes.find((node) => node.id === focusId);
  if (!focus) return null;
  const suppliers = [];
  const customers = [];
  const institutions = [];
  const both = new Set();
  const strength = new Map();
  for (const edge of subset.edges) {
    const counterpart = edge.source === focusId ? edge.target : edge.source;
    if (counterpart === focusId) continue;
    strength.set(counterpart, (strength.get(counterpart) || 0) + Math.abs(Number(edge.amount) || 0));
    const node = model.nodesById.get(counterpart);
    if (!node) continue;
    if (isInstitution(node) || String(node.id).startsWith("outside:")) {
      if (!institutions.some((item) => item.id === node.id)) institutions.push(node);
    } else if (edge.source === focusId) {
      if (customers.some((item) => item.id === node.id)) both.add(node.id);
      if (!suppliers.some((item) => item.id === node.id)) suppliers.push(node);
    } else {
      if (suppliers.some((item) => item.id === node.id)) both.add(node.id);
      if (!customers.some((item) => item.id === node.id)) customers.push(node);
    }
  }
  const byStrength = (a, b) => (strength.get(b.id) || 0) - (strength.get(a.id) || 0)
    || String(a.id).localeCompare(String(b.id), undefined, { numeric: true });
  suppliers.sort(byStrength);
  customers.sort(byStrength);
  institutions.sort(byStrength);

  const nodes = [cloneAt(focus, 0, 0, altitude, { role: "focus", radius: nodeRadius(focus, altitude) * 1.35 })];
  const maxSide = 10;
  const supplierVisible = suppliers.filter((node) => !both.has(node.id)).slice(0, maxSide);
  const customerVisible = customers.filter((node) => !both.has(node.id)).slice(0, maxSide);
  const bothVisible = [...both].map((id) => model.nodesById.get(id)).filter(Boolean).sort(byStrength).slice(0, 4);
  for (const { item, x, y } of verticalPositions(supplierVisible, -310, 58)) nodes.push(cloneAt(item, x, y, altitude, { role: "supplier" }));
  for (const { item, x, y } of verticalPositions(customerVisible, 310, 58)) nodes.push(cloneAt(item, x, y, altitude, { role: "customer" }));
  bothVisible.forEach((node, index) => {
    const angle = Math.PI * .2 + (index / Math.max(1, bothVisible.length - 1)) * Math.PI * .6;
    nodes.push(cloneAt(node, Math.cos(angle) * 205, -Math.sin(angle) * 205, altitude, { role: "mutual" }));
  });
  institutions.slice(0, 8).forEach((node, index) => {
    const angle = Math.PI * .1 + (index / Math.max(1, institutions.length - 1)) * Math.PI * .8;
    nodes.push(cloneAt(node, Math.cos(angle) * 245, Math.sin(angle) * 220 + 55, altitude, { role: "institution" }));
  });
  const visibleIds = new Set(nodes.map((node) => node.id));
  const edges = subset.edges.filter((edge) => visibleIds.has(edge.source) && visibleIds.has(edge.target));
  return { nodes, edges, focus: focusId, mode: "ego", omittedCounterparties: subset.nodes.length - nodes.length };
}

function layoutSectorOverview(model, metadataIndex) {
  const sectorNodes = model.nodes.filter((node) => node.kind === "sector" || node.id.startsWith("sector:"));
  const institutionNodes = model.nodes.filter((node) => isInstitution(node));
  const groups = new Map();
  for (const node of sectorNodes) {
    const sector = sectorIdentity(node.sector, metadataIndex);
    const key = sector.group_id || "OTHER";
    if (!groups.has(key)) groups.set(key, { meta: sector, nodes: [] });
    groups.get(key).nodes.push(node);
  }
  const ordered = [...groups.values()].sort((a, b) => Number(a.meta.group_order || 99) - Number(b.meta.group_order || 99));
  const nodes = [];
  ordered.forEach((group, groupIndex) => {
    group.nodes.sort((a, b) => Number(a.sector) - Number(b.sector));
    const angle = (groupIndex / Math.max(1, ordered.length)) * Math.PI * 2 - Math.PI / 2;
    const centerX = Math.cos(angle) * 400;
    const centerY = Math.sin(angle) * 265;
    group.nodes.forEach((node, index) => {
      const localAngle = (index / Math.max(1, group.nodes.length)) * Math.PI * 2;
      const ring = 25 + Math.sqrt(group.nodes.length) * 12;
      const noise = jitter(node.id, 7);
      nodes.push(cloneAt(node, centerX + Math.cos(localAngle) * ring + noise.x, centerY + Math.sin(localAngle) * ring + noise.y, "sectors", {
        groupColor: group.meta.group_color,
        groupLabel: group.meta.group_label,
      }));
    });
  });
  institutionNodes.forEach((node, index) => {
    const angle = (index / Math.max(1, institutionNodes.length)) * Math.PI * 2 - Math.PI / 2;
    nodes.push(cloneAt(node, Math.cos(angle) * 155, Math.sin(angle) * 102, "sectors", { role: "institution" }));
  });
  const visibleIds = new Set(nodes.map((node) => node.id));
  const collapsed = new Map();
  for (const edge of model.edges) {
    const source = edge.source.startsWith("outside:") ? "outside-world" : edge.source;
    const target = edge.target.startsWith("outside:") ? "outside-world" : edge.target;
    if (!visibleIds.has(source) || !visibleIds.has(target)) continue;
    const domain = edge.scaleDomainId || [
      edge.layer,
      edge.measureKind,
      edge.units,
      edge.recognition,
      edge.valuationBasis,
    ].join("|");
    // Never collapse incompatible economic measures or opposing comparison
    // classes into one stroke. In particular, abs(delta) magnitudes cannot be
    // summed across increased/decreased rows without corrupting their meaning.
    const key = `${domain}:${edge.deltaClass || "single-run"}:${source}:${target}`;
    const existing = collapsed.get(key);
    if (existing) {
      existing.amount += edge.amount;
      if (Number.isFinite(existing.delta) && Number.isFinite(edge.delta)) existing.delta += edge.delta;
      if (Number.isFinite(existing.amountA) && Number.isFinite(edge.amountA)) existing.amountA += edge.amountA;
      if (Number.isFinite(existing.amountB) && Number.isFinite(edge.amountB)) existing.amountB += edge.amountB;
      existing.matchCount += edge.matchCount || 0;
      existing.componentEdges.push(edge.id);
    } else {
      collapsed.set(key, {
        ...edge,
        id: edge.source.startsWith("outside:") || edge.target.startsWith("outside:") ? `lod:${key}` : edge.id,
        source,
        target,
        sourceLabel: source === "outside-world" ? "Rest of world" : edge.sourceLabel,
        targetLabel: target === "outside-world" ? "Rest of world" : edge.targetLabel,
        aggregation: edge.source.startsWith("outside:") || edge.target.startsWith("outside:") ? "exact_sum_to_rest_of_world_portal" : edge.aggregation,
        componentEdges: [edge.id],
      });
    }
  }
  const edges = [...collapsed.values()]
    .sort((a, b) => b.amount - a.amount || a.id.localeCompare(b.id))
    .slice(0, 220);
  return { nodes, edges, focus: null, mode: "communities", omittedEdges: Math.max(0, model.edges.length - edges.length) };
}

function layoutFirmOverview(model, metadataIndex) {
  const firms = model.nodes.filter((node) => node.kind === "firm" || node.id.startsWith("firm:"));
  const bySector = new Map();
  for (const firm of firms) {
    const sector = Number(firm.sector);
    if (!bySector.has(sector)) bySector.set(sector, []);
    bySector.get(sector).push(firm);
  }
  const nodes = [];
  const sectors = [...bySector.keys()].sort((a, b) => a - b);
  sectors.forEach((sectorIndex, index) => {
    const sector = sectorIdentity(sectorIndex, metadataIndex);
    const angle = (index / Math.max(1, sectors.length)) * Math.PI * 2 - Math.PI / 2;
    const centerX = Math.cos(angle) * 430;
    const centerY = Math.sin(angle) * 290;
    const members = bySector.get(sectorIndex).sort((a, b) => numericActorId(a.id) - numericActorId(b.id));
    members.forEach((firm, memberIndex) => {
      const spiral = Math.sqrt(memberIndex + 1) * 9;
      const localAngle = memberIndex * 2.399963;
      nodes.push(cloneAt(firm, centerX + Math.cos(localAngle) * spiral, centerY + Math.sin(localAngle) * spiral, "firms", {
        groupColor: sector.group_color,
      }));
    });
  });
  const visibleIds = new Set(nodes.map((node) => node.id));
  const edges = model.edges
    .filter((edge) => visibleIds.has(edge.source) && visibleIds.has(edge.target))
    .sort((a, b) => b.amount - a.amount || a.id.localeCompare(b.id))
    .slice(0, 240);
  return { nodes, edges, focus: "all", mode: "whole-economy", omittedEdges: Math.max(0, model.edges.length - edges.length) };
}

export function buildLayout(model, state, metadataIndex) {
  if (state.altitude === "economy") return layoutEconomy(model);
  if (state.focus && state.focus !== "all") {
    const focused = layoutFocused(model, state.focus, state.altitude);
    if (focused) return focused;
  }
  if (state.altitude === "sectors") return layoutSectorOverview(model, metadataIndex);
  return layoutFirmOverview(model, metadataIndex);
}
