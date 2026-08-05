import assert from "node:assert/strict";
import test from "node:test";

import {
  activeViewCoverage,
  adaptQuarter,
  formatMoney,
} from "./edges.js";

test("active coverage retains server domains fully suppressed by the client view", () => {
  const coverage = activeViewCoverage({
    target: 0.85,
    by_domain: {
      visible: {
        count_total: 4,
        count_matching: 2,
        count_returned: 1,
        amount_total: 40,
        amount_matching: 20,
        amount_returned: 15,
      },
      suppressed: {
        count_total: 6,
        count_matching: 3,
        count_returned: 2,
        amount_total: 60,
        amount_matching: 30,
        amount_returned: 24,
      },
    },
  }, [{
    id: "visible-edge",
    amount: 15,
    scaleDomainId: "visible",
  }]);

  assert.deepEqual(Object.keys(coverage.by_domain), ["visible", "suppressed"]);
  assert.equal(coverage.domain_count, 2);
  assert.equal(coverage.count_total, 10);
  assert.equal(coverage.count_matching, 5);
  assert.equal(coverage.count_returned, 1);
  assert.equal(coverage.server_count_returned, 3);
  assert.equal(coverage.client_suppressed_count, 2);
  assert.equal(coverage.by_domain.suppressed.count_returned, 0);
  assert.equal(coverage.by_domain.suppressed.amount_returned, 0);
  assert.equal(coverage.by_domain.suppressed.client_suppressed_count, 2);
});

test("money formatting follows the currency encoded in edge units", () => {
  assert.equal(formatMoney(1250, "million_usd_per_quarter"), "$1.25bn / quarter");
  assert.equal(formatMoney(-18.5, "million_eur"), "−€18.5m");
  assert.equal(formatMoney(2, "million_gbp"), "£2m");
});

test("v2 edges inherit dataset units from the manifest when an edge omits units", () => {
  const result = adaptQuarter({
    api_schema_version: "quarter-ledger.v2",
    nodes: [
      { id: "government", label: "Government", kind: "institution" },
      { id: "households", label: "Households", kind: "institution" },
    ],
    edges: [{
      id: "benefit",
      source: "government",
      target: "households",
      amount: 10,
      layer: "fiscal",
    }],
  }, {
    altitude: "economy",
    direction: "money",
    layers: [],
    focus: "all",
    question: null,
    quarter: 1,
  }, {
    byIndex: new Map(),
    ordinalByFirm: new Map(),
  }, {
    units: {
      flow: "million_usd_per_quarter",
      stock: "million_usd",
    },
  });

  assert.equal(result.edges[0].units, "million_usd_per_quarter");
  assert.equal(formatMoney(result.edges[0].amount, result.edges[0].units), "$10m / quarter");
});
