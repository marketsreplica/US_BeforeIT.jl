import assert from "node:assert/strict";
import test from "node:test";

import { buildNodeStockFlowView } from "./node-reconciliation.js";

test("node stock-flow data inherits U.S. units when legacy fields omit them", () => {
  const selection = {
    id: "households",
    type: "node",
    account_reconciliations: [{
      account_id: "household-deposits",
      account_holder_node_id: "households",
      opening_value: 100,
      recorded_change: 5,
      closing_value: 105,
      reconciliation_residual: 0,
      reconciliation_tolerance: 1e-8,
    }],
  };
  const model = {
    schema: "v2",
    units: {
      flow: "million_usd_per_quarter",
      stock: "million_usd",
    },
    edges: [{
      source: "government",
      target: "households",
      canonicalSource: "government",
      canonicalTarget: "households",
      signedValue: 5,
      amount: 5,
      layer: "fiscal",
      recognition: "realized_cash",
      units: "million_usd_per_quarter",
    }],
  };

  const view = buildNodeStockFlowView(selection, model, {
    comparison: null,
    quarter: 1,
    coverage: 1,
    focus: "all",
    layers: [],
  });

  assert.equal(view.accounts[0].units, "million_usd");
  assert.equal(view.categories[0].units, "million_usd_per_quarter");
});
