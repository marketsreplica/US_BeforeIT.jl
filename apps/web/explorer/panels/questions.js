import { payloadBoolean } from "../model/edges.js";

export const QUESTIONS = Object.freeze({
  "government-purchases": {
    title: "Where did government purchases go?",
    requiredCapability: "final_demand_counterparties",
    note: "Exact recorded destinations are shown at the seller basis. Taxes and later wage flows are separate economic relationships, not the same identifiable euros.",
  },
  "sector-suppliers": {
    title: "Who supplies this sector?",
    requiredCapability: "sector_network",
    note: "Money arrows point from the buying sector to suppliers. Intermediate purchases reconcile to turnover and input use, not one-for-one GDP.",
  },
  "firm-institutions": {
    title: "What does this firm pay institutions?",
    requiredCapability: "firm_network",
    note: "Firm wages, taxes, credit, principal, interest, deposits, and dividends remain distinct flows or stocks with their own timing and evidence.",
  },
  "capacity-response": {
    title: "Where could supply have responded?",
    requiredCapability: "capacity_counterfactual",
    note: "Dashed matches show a modelled response against unused productive capacity. They are non-cash and are not a general measure of unmet demand.",
  },
});

export function capabilityAvailable(capabilities, key) {
  const value = capabilities?.[key]
    ?? (key === "capacity_counterfactual" ? capabilities?.potential_demand_signals : null);
  if (value == null) return false;
  if (typeof value === "string") return !["false", "none", "unavailable", "not_retained_due_to_scale"].includes(value.toLowerCase());
  return payloadBoolean(value);
}

export function questionPatch(question, state, { defaultFirm = null, defaultSector = null, capabilities = {} } = {}) {
  const definition = QUESTIONS[question];
  if (!definition) return { patch: {}, note: "Unknown question." };
  const supported = capabilityAvailable(capabilities, definition.requiredCapability);
  if (!supported) {
    return {
      patch: { question, playing: false },
      note: `${definition.title} requires “${definition.requiredCapability.replace(/_/g, " ")}”, which this run does not contain. The existing aggregate view remains available without reconstructed transactions.`,
      supported: false,
    };
  }
  if (question === "government-purchases") {
    return { patch: { question, altitude: "sectors", focus: "government", layers: ["products"], playing: false }, note: definition.note, supported: true };
  }
  if (question === "sector-suppliers") {
    return { patch: { question, altitude: "sectors", focus: defaultSector, layers: ["products"], playing: false }, note: definition.note, supported: true };
  }
  if (question === "firm-institutions") {
    return { patch: { question, altitude: "firms", focus: defaultFirm, layers: ["income", "fiscal", "credit", "interest", "deposits", "stocks"], playing: false }, note: definition.note, supported: true };
  }
  return { patch: { question, altitude: "sectors", focus: defaultSector, layers: ["capacity"], playing: false }, note: definition.note, supported: true };
}
