import assert from "node:assert/strict";
import test from "node:test";

import { formatMetric } from "./inspector.js";

test("person metrics use the dataset representation multiplier", () => {
  assert.equal(formatMetric("employment", 29, 1000), "29,000");
  assert.equal(formatMetric("agents", 1, 1000), "1,000");
});

test("non-person counts and money are not population-scaled", () => {
  assert.equal(formatMetric("firms", 29, 1000), "29");
  assert.equal(formatMetric("match count", 29, 1000), "29");
  assert.equal(formatMetric("loans", 1200, 1000), "€1.2bn");
});

test("node money metrics follow the selected dataset units", () => {
  const units = {
    flow: "million_usd_per_quarter",
    stock: "million_usd",
  };
  assert.equal(formatMetric("loans", 1200, 1000, units), "$1.2bn");
  assert.equal(formatMetric("sales", 125, 1000, units), "$125m / quarter");
});
