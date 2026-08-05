import assert from "node:assert/strict";
import test from "node:test";

import { formatComparisonValue } from "./comparison.js";

test("comparison values format compatible monetary units using their currency", () => {
  assert.equal(formatComparisonValue(1250, "million_usd_per_quarter"), "$1.25bn / quarter");
  assert.equal(formatComparisonValue(1250, "million_eur_per_quarter"), "€1.25bn / quarter");
});

test("comparison values retain non-monetary unit labels", () => {
  assert.equal(formatComparisonValue(0.25, "annual_rate_delta"), "0.25 Annual Rate Delta");
  assert.equal(formatComparisonValue(null, "million_usd"), "Not present");
});
