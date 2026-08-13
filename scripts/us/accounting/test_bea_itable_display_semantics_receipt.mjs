#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const GENERATOR = path.join(
  SCRIPT_DIRECTORY,
  "generate_bea_itable_display_semantics_receipt.mjs",
);
const RECEIPT = path.join(
  SCRIPT_DIRECTORY,
  "fixtures",
  "bea_after_redefinitions_display_semantics_approved",
  "itable_marker_receipt.json",
);
const CANONICAL_GRID = path.join(
  SCRIPT_DIRECTORY,
  "fixtures",
  "bea_after_redefinitions_display_semantics_approved",
  "itable_canonical_common_basis_grid.csv",
);
const EXPECTED = {
  canonicalGridBytes: 896_314,
  canonicalGridRows: 11_972,
  canonicalGridSha256:
    "2a7c2eb3a809ff9b2e9805569692a095adf590a959017d99911e7f11450ab4e8",
  receiptBytes: 14_650,
  receiptSha256:
    "b861625aaa54c6cce5d0bd0eaaef0ec874f23afc39d0ce1a15d76b36fa098957",
};

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

const receiptBytes = await fs.readFile(RECEIPT);
const canonicalGridBytes = await fs.readFile(CANONICAL_GRID);
requireCondition(
  canonicalGridBytes.length === EXPECTED.canonicalGridBytes,
  "iTable canonical-grid byte count changed",
);
requireCondition(
  crypto.createHash("sha256").update(canonicalGridBytes).digest("hex") ===
    EXPECTED.canonicalGridSha256,
  "iTable canonical-grid SHA-256 changed",
);
requireCondition(
  receiptBytes.length === EXPECTED.receiptBytes,
  "iTable marker receipt byte count changed",
);
requireCondition(
  crypto.createHash("sha256").update(receiptBytes).digest("hex") ===
    EXPECTED.receiptSha256,
  "iTable marker receipt SHA-256 changed",
);

const verification = spawnSync(
  process.execPath,
  [
    GENERATOR,
    "--verify-receipt",
    RECEIPT,
    "--canonical-grid",
    CANONICAL_GRID,
  ],
  {
    cwd: path.resolve(SCRIPT_DIRECTORY, "../../.."),
    encoding: "utf8",
  },
);
requireCondition(
  verification.status === 0,
  "offline receipt verification failed:\n" +
    `${verification.stdout}${verification.stderr}`,
);
requireCondition(
  verification.stdout.includes("offline_coordinate_verification=PASS"),
  "offline coordinate verification did not report PASS",
);
requireCondition(
  verification.stdout.includes(
    `canonical_grid_sha256=${EXPECTED.canonicalGridSha256}`,
  ) &&
    verification.stdout.includes(
      `canonical_grid_rows=${EXPECTED.canonicalGridRows}`,
    ),
  "offline verification returned the wrong canonical-grid digest/count",
);
requireCondition(
  verification.stdout.includes(
    `receipt_sha256=${EXPECTED.receiptSha256}`,
  ),
  "offline verification returned the wrong receipt SHA-256",
);

console.log("bea_itable_display_semantics_receipt_tests=PASS");
console.log(`canonical_grid_sha256=${EXPECTED.canonicalGridSha256}`);
console.log(`canonical_grid_rows=${EXPECTED.canonicalGridRows}`);
console.log(`receipt_sha256=${EXPECTED.receiptSha256}`);
