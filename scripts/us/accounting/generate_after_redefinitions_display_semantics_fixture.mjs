#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const configuredNodeModules = process.env.BEFOREIT_NODE_MODULES;
const artifactToolEntry =
  configuredNodeModules === undefined
    ? fileURLToPath(import.meta.resolve("@oai/artifact-tool"))
    : require.resolve("@oai/artifact-tool", {
        paths: [
          path.basename(configuredNodeModules) === "node_modules"
            ? path.dirname(configuredNodeModules)
            : configuredNodeModules,
        ],
      });
const { FileBlob, SpreadsheetFile } = await import(
  pathToFileURL(artifactToolEntry).href
);

const SOURCE_URL =
  "https://apps.bea.gov/industry/release/zip/" +
  "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip";
const ARCHIVE_URL =
  "https://apps.bea.gov/HistData/Files/Releases/Industry/2025/" +
  "GDP_by_Industry/Q2/Annual_September-25-2025/" +
  "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip";
const EXPECTED = {
  artifactToolVersion: "2.8.39",
  sourceZip: {
    bytes: 8_326_144,
    sha256:
      "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
  },
  producerUse: {
    member: "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    bytes: 1_163_798,
    sha256:
      "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
  },
  producerMake: {
    member: "IOMake_After_Redefinitions_PRO_Summary.xlsx",
    bytes: 598_989,
    sha256:
      "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
  },
  imports: {
    member: "ImportMatrices_After_Redefinitions_Summary.xlsx",
    bytes: 841_463,
    sha256:
      "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25",
  },
};

const HEADERS = [
  "record_id",
  "workbook_member",
  "workbook_sha256",
  "sheet",
  "cell_address",
  "record_kind",
  "semantic_class",
  "source_token",
  "exact_text_or_value",
];

function fail(message) {
  throw new Error(message);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

function digest(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

async function packageVersion(packageName, entryPath) {
  let directory = path.dirname(entryPath);
  while (true) {
    const candidate = path.join(directory, "package.json");
    try {
      const metadata = JSON.parse(await fs.readFile(candidate, "utf8"));
      if (metadata.name === packageName) return String(metadata.version);
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
    const parent = path.dirname(directory);
    if (parent === directory) {
      fail(`could not locate package metadata for ${packageName}`);
    }
    directory = parent;
  }
}

function scalar(sheet, address) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === 1 && values[0].length === 1,
    `${address} is not scalar`,
  );
  return values[0][0];
}

function exactText(sheet, address, expected, label) {
  const actual = scalar(sheet, address);
  requireCondition(actual === expected, `${label} changed`);
  return actual;
}

function exactToken(sheet, address, expected, label) {
  const actual = scalar(sheet, address);
  requireCondition(
    Object.is(actual, expected),
    `${label} changed: expected ${String(expected)}, got ${String(actual)}`,
  );
  return actual;
}

function exactNumber(sheet, address, expected, label) {
  const actual = scalar(sheet, address);
  const numeric =
    typeof actual === "number" ? actual : Number(String(actual).trim());
  requireCondition(
    Number.isFinite(numeric) && numeric === expected,
    `${label} changed: expected ${expected}, got ${String(actual)}`,
  );
  return numeric;
}

function csvEscape(value) {
  const converted = String(value);
  return /[",\r\n]/u.test(converted)
    ? `"${converted.replaceAll('"', '""')}"`
    : converted;
}

function csvBytes(records) {
  return Buffer.from(
    `${HEADERS.join(",")}\n` +
      records
        .map((record) =>
          HEADERS.map((header) => csvEscape(record[header])).join(","),
        )
        .join("\n") +
      "\n",
    "utf8",
  );
}

function tomlString(value) {
  return JSON.stringify(String(value));
}

function addRecord(records, workbook, sheet, address, options) {
  records.push({
    record_id: options.recordId,
    workbook_member: workbook.member,
    workbook_sha256: workbook.sha256,
    sheet,
    cell_address: address,
    record_kind: options.recordKind,
    semantic_class: options.semanticClass,
    source_token: options.sourceToken,
    exact_text_or_value: options.exactTextOrValue,
  });
}

async function renderRange(workbook, sheetName, range, outputPath) {
  const blob = await workbook.render({
    sheetName,
    range,
    scale: 1.5,
    format: "png",
  });
  await fs.writeFile(
    outputPath,
    new Uint8Array(await blob.arrayBuffer()),
  );
}

if (process.argv.length !== 9) {
  fail(
    "usage: node generate_after_redefinitions_display_semantics_fixture.mjs " +
      "SOURCE_ZIP IOUse_After_Redefinitions_PRO_Summary.xlsx " +
      "IOMake_After_Redefinitions_PRO_Summary.xlsx " +
      "ImportMatrices_After_Redefinitions_Summary.xlsx " +
      "OUTPUT_DIRECTORY QA_DIRECTORY SOURCE_RETRIEVED_AT_UTC",
  );
}

const [
  ,
  ,
  sourceZipPath,
  producerUsePath,
  producerMakePath,
  importPath,
  outputDirectory,
  qaDirectory,
  sourceRetrievedAtUtc,
] = process.argv;

const artifactToolVersion = await packageVersion(
  "@oai/artifact-tool",
  artifactToolEntry,
);
requireCondition(
  artifactToolVersion === EXPECTED.artifactToolVersion,
  `@oai/artifact-tool version changed: expected ${EXPECTED.artifactToolVersion}, got ${artifactToolVersion}`,
);

const [sourceZipBytes, producerUseBytes, producerMakeBytes, importBytes] =
  await Promise.all([
    fs.readFile(sourceZipPath),
    fs.readFile(producerUsePath),
    fs.readFile(producerMakePath),
    fs.readFile(importPath),
  ]);
for (const [label, bytes, expected] of [
  ["source ZIP", sourceZipBytes, EXPECTED.sourceZip],
  ["producer-use workbook", producerUseBytes, EXPECTED.producerUse],
  ["producer-make workbook", producerMakeBytes, EXPECTED.producerMake],
  ["import workbook", importBytes, EXPECTED.imports],
]) {
  requireCondition(
    bytes.length === expected.bytes && digest(bytes) === expected.sha256,
    `${label} bytes changed`,
  );
}
requireCondition(
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(
    sourceRetrievedAtUtc,
  ),
  "retrieval timestamp is not canonical UTC",
);

const [producerUseWorkbook, producerMakeWorkbook, importWorkbook] =
  await Promise.all([
    SpreadsheetFile.importXlsx(await FileBlob.load(producerUsePath)),
    SpreadsheetFile.importXlsx(await FileBlob.load(producerMakePath)),
    SpreadsheetFile.importXlsx(await FileBlob.load(importPath)),
  ]);
const producerUse2024 = producerUseWorkbook.worksheets.getItem("2024");
const producerMake2024 = producerMakeWorkbook.worksheets.getItem("2024");
const import2024 = importWorkbook.worksheets.getItem("2024");
const importReconciliation =
  importWorkbook.worksheets.getItem("Import Reconcilliation");

for (const [sheet, title] of [
  [
    producerUse2024,
    "The Use of Commodities by Industries, After Redefinitions " +
      "(Producers' Prices) - Summary",
  ],
  [
    producerMake2024,
    "The Make of Commodities by Industries, After Redefinitions - Summary",
  ],
  [import2024, "Import Matrix, After Redefinitions"],
]) {
  exactText(sheet, "A1", title, `${title} title`);
  exactText(
    sheet,
    "A2",
    "(Millions of dollars)",
    `${title} unit`,
  );
  exactText(
    sheet,
    "A3",
    "Bureau of Economic Analysis",
    `${title} publisher`,
  );
  exactNumber(sheet, "A4", 2024, `${title} year`);
}

const zeroNote = "Note. Selected data with zero values are not shown.";
const roundingNote = "Note. Detail may not add to total due to rounding.";
const importRoundingNote =
  "2 Totals from the import matrix may differ from the sum of values " +
  "in this table due to rounding.";
const importValuationNote =
  "Note: Imports in the import matrix are valued at domestic port value, " +
  "which is the value of imports when they enter the U.S. economy. " +
  "Domestic port value is the substitution value of imports relative to " +
  "domestically-produced goods and services and is calculated as total " +
  "imports from the use table, plus the value of transportation and " +
  "insurance services provided by domestic carriers to move imports from " +
  "the foreign port to the domestic port, plus customs duties.";

const records = [];
for (const item of [
  {
    workbook: EXPECTED.producerUse,
    sheetObject: producerUse2024,
    address: "A89",
    recordId: "PRODUCER_USE_2024_ZERO_VALUE_NOTE",
    semanticClass: "SELECTED_ELLIPSIS_IS_PUBLISHED_ZERO",
    exactTextOrValue: exactText(
      producerUse2024,
      "A89",
      zeroNote,
      "producer-use zero-value note",
    ),
  },
  {
    workbook: EXPECTED.producerUse,
    sheetObject: producerUse2024,
    address: "A90",
    recordId: "PRODUCER_USE_2024_ROUNDING_NOTE",
    semanticClass: "PUBLISHED_DETAIL_MAY_NOT_ADD_DUE_TO_ROUNDING",
    exactTextOrValue: exactText(
      producerUse2024,
      "A90",
      roundingNote,
      "producer-use rounding note",
    ),
  },
  {
    workbook: EXPECTED.producerMake,
    sheetObject: producerMake2024,
    address: "A83",
    recordId: "PRODUCER_MAKE_2024_ZERO_VALUE_NOTE",
    semanticClass: "SELECTED_ELLIPSIS_IS_PUBLISHED_ZERO",
    exactTextOrValue: exactText(
      producerMake2024,
      "A83",
      zeroNote,
      "producer-make zero-value note",
    ),
  },
  {
    workbook: EXPECTED.producerMake,
    sheetObject: producerMake2024,
    address: "A84",
    recordId: "PRODUCER_MAKE_2024_ROUNDING_NOTE",
    semanticClass: "PUBLISHED_DETAIL_MAY_NOT_ADD_DUE_TO_ROUNDING",
    exactTextOrValue: exactText(
      producerMake2024,
      "A84",
      roundingNote,
      "producer-make rounding note",
    ),
  },
]) {
  addRecord(records, item.workbook, "2024", item.address, {
    recordId: item.recordId,
    recordKind: "SOURCE_NOTE",
    semanticClass: item.semanticClass,
    sourceToken: "",
    exactTextOrValue: item.exactTextOrValue,
  });
}

for (const item of [
  {
    workbook: EXPECTED.producerUse,
    sheetObject: producerUse2024,
    address: "E8",
    recordId: "PRODUCER_USE_2024_ELLIPSIS_WITNESS",
  },
  {
    workbook: EXPECTED.producerMake,
    sheetObject: producerMake2024,
    address: "E8",
    recordId: "PRODUCER_MAKE_2024_ELLIPSIS_WITNESS",
  },
  {
    workbook: EXPECTED.imports,
    sheetObject: import2024,
    address: "E8",
    recordId: "IMPORT_2024_ELLIPSIS_WITNESS",
  },
]) {
  addRecord(records, item.workbook, "2024", item.address, {
    recordId: item.recordId,
    recordKind: "SOURCE_CELL_WITNESS",
    semanticClass:
      item.workbook === EXPECTED.imports
        ? "RELEASE_SCOPED_CORROBORATED_SELECTED_ZERO_DISPLAY_TOKEN"
        : "AUTHENTICATED_SELECTED_ZERO_DISPLAY_TOKEN",
    sourceToken: exactToken(
      item.sheetObject,
      item.address,
      "...",
      `${item.recordId} token`,
    ),
    exactTextOrValue: "...",
  });
}

for (const item of [
  {
    workbook: EXPECTED.producerUse,
    sheetObject: producerUse2024,
    address: "AP8",
    recordId: "PRODUCER_USE_2024_NUMERIC_ZERO_WITNESS",
  },
  {
    workbook: EXPECTED.producerMake,
    sheetObject: producerMake2024,
    address: "M10",
    recordId: "PRODUCER_MAKE_2024_NUMERIC_ZERO_WITNESS",
  },
  {
    workbook: EXPECTED.imports,
    sheetObject: import2024,
    address: "F8",
    recordId: "IMPORT_2024_NUMERIC_ZERO_WITNESS",
  },
]) {
  addRecord(records, item.workbook, "2024", item.address, {
    recordId: item.recordId,
    recordKind: "SOURCE_CELL_WITNESS",
    semanticClass: "EXPLICIT_NUMERIC_ZERO_DISPLAY_TOKEN",
    sourceToken: "0",
    exactTextOrValue: String(
      exactNumber(
        item.sheetObject,
        item.address,
        0,
        `${item.recordId} value`,
      ),
    ),
  });
}

addRecord(
  records,
  EXPECTED.imports,
  "Import Reconcilliation",
  "A17",
  {
    recordId: "IMPORT_RECONCILIATION_ROUNDING_NOTE",
    recordKind: "SOURCE_NOTE",
    semanticClass: "PUBLISHED_TOTAL_MAY_DIFFER_DUE_TO_ROUNDING",
    sourceToken: "",
    exactTextOrValue: exactText(
      importReconciliation,
      "A17",
      importRoundingNote,
      "import rounding note",
    ),
  },
);
addRecord(
  records,
  EXPECTED.imports,
  "Import Reconcilliation",
  "A18",
  {
    recordId: "IMPORT_RECONCILIATION_VALUATION_NOTE",
    recordKind: "SOURCE_NOTE",
    semanticClass: "DOMESTIC_PORT_SUBSTITUTION_VALUE",
    sourceToken: "",
    exactTextOrValue: exactText(
      importReconciliation,
      "A18",
      importValuationNote,
      "import valuation note",
    ),
  },
);

const importColumnA = import2024.getRange("A1:A80").values.flat();
requireCondition(
  !importColumnA.includes(zeroNote),
  "import workbook unexpectedly acquired the producer zero-value note",
);
records.sort((left, right) => left.record_id.localeCompare(right.record_id));
requireCondition(
  new Set(records.map((record) => record.record_id)).size === records.length,
  "display-evidence record identifiers are not unique",
);
requireCondition(records.length === 12, "display-evidence count changed");

const fixture = csvBytes(records);
const fixtureSha256 = digest(fixture);
const manifestText = [
  'schema_version = "beforeit-us-after-redefinitions-display-semantics-fixture.v1"',
  'classification = "CURRENT_VINTAGE_SOURCE_DISPLAY_EVIDENCE_NOT_SOLVER_ADMITTED"',
  'artifact_role = "AUTHENTICATED_SOURCE_NOTE_AND_TOKEN_EVIDENCE"',
  'promotion_status = "RESEARCH_ONLY_NOT_PROMOTED"',
  `source_url = ${tomlString(SOURCE_URL)}`,
  `source_archive_url = ${tomlString(ARCHIVE_URL)}`,
  `source_zip_sha256 = ${tomlString(EXPECTED.sourceZip.sha256)}`,
  `source_zip_byte_count = ${EXPECTED.sourceZip.bytes}`,
  `source_retrieved_at_utc = ${tomlString(sourceRetrievedAtUtc)}`,
  `artifact_tool_version = ${tomlString(artifactToolVersion)}`,
  `producer_use_workbook_sha256 = ${tomlString(EXPECTED.producerUse.sha256)}`,
  `producer_make_workbook_sha256 = ${tomlString(EXPECTED.producerMake.sha256)}`,
  `import_workbook_sha256 = ${tomlString(EXPECTED.imports.sha256)}`,
  `fixture_record_count = ${records.length}`,
  `fixture_sha256 = ${tomlString(fixtureSha256)}`,
  'producer_zero_note_status = "AUTHENTICATED_SAME_SHEET_NOTE"',
  'producer_selected_ellipsis_published_value_millions = 0.0',
  'producer_selected_ellipsis_structural_zero_status = "NOT_ESTABLISHED"',
  'producer_selected_ellipsis_variance_status = "NOT_ESTABLISHED"',
  'producer_rounding_rule_status = "EXACT_RULE_NOT_DOCUMENTED"',
  "import_same_sheet_zero_note_present = false",
  'import_ellipsis_semantics_status = "RELEASE_SCOPED_CORROBORATED_BY_SEPARATELY_PINNED_ITABLE_RECEIPT"',
  'import_rounding_status = "TOTAL_NONADDITIVITY_NOTE_AUTHENTICATED_EXACT_RULE_NOT_DOCUMENTED"',
  "solver_admissible = false",
  "structural_zero_approval_count = 0",
  "reliability_receipt_count = 0",
  "covariance_receipt_count = 0",
  "model_state_write = false",
  'accounting_gate_effect = "NONE"',
  'forecast_score_effect = "NONE"',
  "",
].join("\n");
const manifest = Buffer.from(manifestText, "utf8");

await fs.mkdir(outputDirectory, { recursive: true });
await fs.mkdir(qaDirectory, { recursive: true });
await Promise.all([
  fs.writeFile(path.join(outputDirectory, "display_semantics.csv"), fixture),
  fs.writeFile(path.join(outputDirectory, "manifest.toml"), manifest),
  renderRange(
    producerUseWorkbook,
    "2024",
    "A82:B90",
    path.join(qaDirectory, "producer_use_notes.png"),
  ),
  renderRange(
    producerMakeWorkbook,
    "2024",
    "A79:B84",
    path.join(qaDirectory, "producer_make_notes.png"),
  ),
  renderRange(
    importWorkbook,
    "Import Reconcilliation",
    "A14:AC18",
    path.join(qaDirectory, "import_reconciliation_notes.png"),
  ),
  renderRange(
    importWorkbook,
    "2024",
    "A1:J12",
    path.join(qaDirectory, "import_token_witnesses.png"),
  ),
]);

console.log(`fixture_sha256=${fixtureSha256}`);
console.log(`manifest_sha256=${digest(manifest)}`);
console.log(`fixture_records=${records.length}`);
