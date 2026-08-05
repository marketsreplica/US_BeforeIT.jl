import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const {
  formatMoneyMillions,
  monetaryPresentation,
  runSupportsExplorer,
} = require("./app.js");

test("dashboard money presentation preserves euro defaults", () => {
  assert.deepEqual(monetaryPresentation(null), {
    currency: "EUR",
    symbol: "€",
    flowUnits: "million_eur_per_quarter",
    stockUnits: "million_eur",
  });
  assert.equal(formatMoneyMillions(1250, null), "€1.25bn");
});

test("dashboard money presentation uses U.S. dataset metadata", () => {
  const metadata = {
    country: "US",
    currency: "USD",
    currency_symbol: "$",
    flow_units: "million_usd_per_quarter",
    stock_units: "million_usd",
  };
  assert.deepEqual(monetaryPresentation(metadata), {
    currency: "USD",
    symbol: "$",
    flowUnits: "million_usd_per_quarter",
    stockUnits: "million_usd",
  });
  assert.equal(formatMoneyMillions(-2500, metadata), "−$2.5bn");
});

test("completed summary exposes Explorer before run history refreshes", () => {
  assert.equal(
    runSupportsExplorer(
      { cashflows_available: true },
      { cashflows_available: false },
    ),
    true,
  );
  assert.equal(
    runSupportsExplorer(
      { cashflows_available: false },
      { cashflows_available: true },
    ),
    false,
  );
  assert.equal(
    runSupportsExplorer({}, { cashflows_available: true }),
    true,
  );
});
