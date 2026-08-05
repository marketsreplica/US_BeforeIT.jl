export function createMetadataIndex(metadata, firms = []) {
  const sectors = Array.isArray(metadata?.sectors) ? metadata.sectors : [];
  const byIndex = new Map(sectors.map((sector) => [Number(sector.index), sector]));
  const byCode = new Map(sectors.map((sector) => [String(sector.code).toLowerCase(), sector]));
  const firmsBySector = new Map();
  for (const firm of firms) {
    const sector = Number(firm.sector);
    if (!firmsBySector.has(sector)) firmsBySector.set(sector, []);
    firmsBySector.get(sector).push(firm);
  }
  const ordinalByFirm = new Map();
  for (const members of firmsBySector.values()) {
    members.sort((a, b) => numericActorId(a.id) - numericActorId(b.id));
    members.forEach((firm, index) => ordinalByFirm.set(String(firm.id), index + 1));
  }
  return { metadata, byIndex, byCode, firmsBySector, ordinalByFirm };
}

export function numericActorId(id) {
  const value = Number(String(id ?? "").split(":").at(-1));
  return Number.isFinite(value) ? value : Number.MAX_SAFE_INTEGER;
}

export function sectorIdentity(index, metadataIndex) {
  const number = Number(index);
  const sector = metadataIndex?.byIndex?.get(number);
  return sector || {
    index: number,
    code: `S${String(number).padStart(3, "0")}`,
    label: `Dataset sector ${number}`,
    short_label: `Sector ${number}`,
    group_id: "OTHER",
    group_label: "Other sectors",
    group_color: "#8fa3a0",
  };
}

export function sectorLabel(index, metadataIndex, { short = true } = {}) {
  const sector = sectorIdentity(index, metadataIndex);
  const name = short ? sector.short_label || sector.label : sector.label;
  return `${sector.code} · ${name}`;
}

export function firmLabel(firm, metadataIndex, { long = false } = {}) {
  const sector = sectorIdentity(firm?.sector, metadataIndex);
  const ordinal = metadataIndex?.ordinalByFirm?.get(String(firm?.id)) ?? numericActorId(firm?.id);
  const number = Number.isFinite(ordinal) ? String(ordinal).padStart(3, "0") : "—";
  const sectorName = long ? sector.label : sector.short_label || sector.label;
  return `${sector.code} · ${sectorName} · Firm ${number}`;
}

const INSTITUTION_LABELS = Object.freeze({
  households: "Households",
  "household:active-workers": "Active-worker households",
  "household:inactive": "Inactive households",
  "household:firm-owners": "Firm-owner households",
  "household:bank-owner": "Bank-owner household",
  // Legacy aliases remain readable, but v2 traces use the household:* IDs above.
  "cohort:active_workers": "Active-worker households",
  "cohort:inactive_households": "Inactive households",
  "cohort:firm_owners": "Firm-owner households",
  "cohort:bank_owner": "Bank-owner household",
  production: "Production network",
  "goods-market": "Products & services market",
  government: "Government",
  bank: "Commercial bank",
  "central-bank": "Central bank",
  "outside-world": "Rest of world",
});

export function isHouseholdCohortId(id) {
  const key = String(id ?? "");
  return key.startsWith("household:") || key.startsWith("cohort:");
}

export function actorLabel(id, nodesById, metadataIndex) {
  const key = String(id ?? "");
  const node = nodesById?.get(key);
  if (node?.kind === "firm" || key.startsWith("firm:")) return firmLabel(node || { id: key, sector: node?.sector }, metadataIndex);
  if (node?.kind === "sector" || key.startsWith("sector:")) return sectorLabel(node?.sector ?? key.slice(7), metadataIndex);
  if (key.startsWith("outside:")) return `World market · ${sectorLabel(key.slice(8), metadataIndex)}`;
  return INSTITUTION_LABELS[key] || node?.label || humanizeId(key);
}

export function humanizeId(value) {
  return String(value || "")
    .replace(/^.*:/, "")
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function metadataSearchOptions(metadataIndex, firms = []) {
  const options = [];
  for (const sector of metadataIndex?.byIndex?.values?.() || []) {
    options.push({ value: `${sector.code} · ${sector.short_label || sector.label}`, id: `sector:${sector.index}`, type: "sector" });
  }
  for (const firm of firms) {
    options.push({ value: firmLabel(firm, metadataIndex), id: String(firm.id), type: "firm" });
  }
  return options;
}
