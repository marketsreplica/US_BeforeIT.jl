#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const YEAR = 2024;
const DECIMAL_PLACES = 7;
const EXPECTED = {
  artifactToolVersion: "2.8.31",
  zipSha256: "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae",
  zipBytes: 8_486_511,
  metadataSha256: "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca",
  directSha256: "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439",
  directBytes: 1_263_634,
  marketSha256: "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2",
  marketBytes: 580_039,
  fixtureSha256: "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e",
  fixtureCells: 10_650,
};

const MANIFEST = `accounting_gate_effect = "NONE"
artifact_tool_version = "${EXPECTED.artifactToolVersion}"
coefficient_unit = "dimensionless producer-price after-redefinitions coefficient"
commodity_count = 73
direct_control_maximum_absolute_residual = 4.0000000001150227e-7
direct_control_tolerance = 3.85e-6
direct_matrix_id = "commodity_by_industry_direct"
direct_matrix_range = "2024!C8:BU80"
direct_workbook_member = "CxI_DR_Summary.xlsx"
direct_workbook_sha256 = "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439"
fixture_cell_count = 10650
fixture_sha256 = "d4df6c610caaca42a9579a4c868efbee6d5f5842467f392bd6a0e75ac8cd748e"
forecast_origin_admissible = false
generation_policy = "Extraction must fail unless the archived ZIP metadata, both workbook-member hashes, exact 2024 sheet selectors, rectangular dimensions, code/description axes, and published-precision controls match this approved current-vintage diagnostic."
industry_control_matrix_id = "industry_control_total"
industry_count = 71
market_share_control_maximum_absolute_residual = 3.0000000017516015e-7
market_share_control_tolerance = 3.6e-6
market_share_matrix_id = "industry_by_commodity_market_share"
market_share_matrix_range = "2024!C8:BW78"
market_share_workbook_member = "IxC_MS_Summary.xlsx"
market_share_workbook_sha256 = "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2"
model_state_write = false
negative_direct_cell_count = 5
negative_market_share_cell_count = 1
price_basis = "producers' prices"
projection = "Every numeric cell, positional code, and description in the 2024 direct-requirements, value-added, industry-total-control, and market-share ranges. Negative values and the explicit Used and Other commodities are preserved without clipping, balancing, or reordering."
promotion_status = "RESEARCH_ONLY_NOT_PROMOTED"
published_decimal_places = 7
retrieved_at_utc = "2026-08-06T02:17:13.662Z"
schema_version = "beforeit-us-official-direct-requirements-fixture.v1"
source_last_modified = "Wed, 11 Feb 2026 12:01:48 GMT"
source_metadata_sha256 = "f3f57a7209f7c6d9b0f76b041f17ae78e9da1d8644dbd7d6815471e740abfaca"
source_url = "https://apps.bea.gov/industry/release/zip/DIRECT%20REQUIREMENTS%20AND%20MARKET%20SHARE%20MATRICES.zip"
source_zip_byte_count = 8486511
source_zip_sha256 = "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
status = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
value_added_count = 3
value_added_matrix_id = "industry_value_added"
value_added_range = "2024!C81:BU83"
year = 2024
`;

function fail(message) {
  throw new Error(message);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

async function packageVersion(packageName, entryPath) {
  let directory = path.dirname(entryPath);
  while (true) {
    const candidate = path.join(directory, "package.json");
    try {
      const packageMetadata = JSON.parse(await fs.readFile(candidate, "utf8"));
      if (packageMetadata.name === packageName) {
        return asText(packageMetadata.version, `${packageName} version`);
      }
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

function digest(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function scalar(sheet, address) {
  const values = sheet.getRange(address).values;
  requireCondition(values.length === 1 && values[0].length === 1, `${address} is not scalar`);
  return values[0][0];
}

function row(sheet, address, length) {
  const values = sheet.getRange(address).values;
  requireCondition(values.length === 1 && values[0].length === length, `${address} has the wrong shape`);
  return values[0];
}

function column(sheet, address, length) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === length && values.every((entry) => entry.length === 1),
    `${address} has the wrong shape`,
  );
  return values.map((entry) => entry[0]);
}

function matrix(sheet, address, rows, columns) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === rows && values.every((entry) => entry.length === columns),
    `${address} has the wrong shape`,
  );
  return values;
}

function asText(value, label) {
  requireCondition(value !== null && value !== undefined, `${label} is blank`);
  const converted = String(value).trim();
  requireCondition(converted.length > 0, `${label} is blank`);
  return converted;
}

function asNumber(value, label) {
  const converted =
    typeof value === "number" ? value : Number(String(value).replaceAll(",", "").trim());
  requireCondition(Number.isFinite(converted), `${label} is not finite`);
  return converted;
}

function textVector(values, label) {
  return values.map((value, index) => asText(value, `${label}[${index + 1}]`));
}

function numberMatrix(values, label) {
  return values.map((valuesRow, rowIndex) =>
    valuesRow.map((value, columnIndex) =>
      asNumber(value, `${label}[${rowIndex + 1},${columnIndex + 1}]`),
    ),
  );
}

function maximumAbsolute(values) {
  return Math.max(...values.map((value) => Math.abs(value)));
}

function csvEscape(value) {
  const converted = String(value);
  return /[",\r\n]/u.test(converted)
    ? `"${converted.replaceAll('"', '""')}"`
    : converted;
}

function fixtureValue(value) {
  return asNumber(value, "fixture value").toFixed(DECIMAL_PLACES);
}

function addMatrix(
  output,
  matrixId,
  rowCodes,
  rowDescriptions,
  rowType,
  columnCodes,
  columnDescriptions,
  columnType,
  values,
) {
  requireCondition(values.length === rowCodes.length, `${matrixId} row count differs`);
  requireCondition(
    values.every((valuesRow) => valuesRow.length === columnCodes.length),
    `${matrixId} column count differs`,
  );
  for (let rowIndex = 0; rowIndex < rowCodes.length; rowIndex += 1) {
    for (let columnIndex = 0; columnIndex < columnCodes.length; columnIndex += 1) {
      output.push({
        matrix_id: matrixId,
        year: YEAR,
        row_position: rowIndex + 1,
        row_code: rowCodes[rowIndex],
        row_description: rowDescriptions[rowIndex],
        row_type: rowType,
        column_position: columnIndex + 1,
        column_code: columnCodes[columnIndex],
        column_description: columnDescriptions[columnIndex],
        column_type: columnType,
        value: fixtureValue(values[rowIndex][columnIndex]),
      });
    }
  }
}

async function render(workbook, outputDirectory, sheetName, range, filename) {
  const blob = await workbook.render({ sheetName, range, scale: 1.5, format: "png" });
  await fs.writeFile(
    path.join(outputDirectory, filename),
    new Uint8Array(await blob.arrayBuffer()),
  );
}

if (process.argv.length !== 7) {
  fail(
    "usage: node generate_official_direct_requirements_fixture.mjs " +
      "SOURCE_ZIP SOURCE_METADATA_JSON CxI_DR_Summary.xlsx " +
      "IxC_MS_Summary.xlsx OUTPUT_DIRECTORY",
  );
}
const [, , zipPath, metadataPath, directPath, marketPath, outputDirectory] =
  process.argv;
const artifactToolVersion = await packageVersion(
  "@oai/artifact-tool",
  fileURLToPath(import.meta.resolve("@oai/artifact-tool")),
);
requireCondition(
  artifactToolVersion === EXPECTED.artifactToolVersion,
  `@oai/artifact-tool version changed: expected ${EXPECTED.artifactToolVersion}, got ${artifactToolVersion}`,
);
const [zipBytes, metadataBytes, directBytes, marketBytes] = await Promise.all([
  fs.readFile(zipPath),
  fs.readFile(metadataPath),
  fs.readFile(directPath),
  fs.readFile(marketPath),
]);
requireCondition(zipBytes.length === EXPECTED.zipBytes, "source ZIP byte count changed");
requireCondition(digest(zipBytes) === EXPECTED.zipSha256, "source ZIP SHA-256 changed");
requireCondition(
  digest(metadataBytes) === EXPECTED.metadataSha256,
  "source acquisition metadata SHA-256 changed",
);
requireCondition(
  directBytes.length === EXPECTED.directBytes &&
    digest(directBytes) === EXPECTED.directSha256,
  "direct-requirements workbook member changed",
);
requireCondition(
  marketBytes.length === EXPECTED.marketBytes &&
    digest(marketBytes) === EXPECTED.marketSha256,
  "market-share workbook member changed",
);
const metadata = JSON.parse(metadataBytes.toString("utf8"));
requireCondition(metadata.sha256 === EXPECTED.zipSha256, "metadata does not bind the ZIP");
requireCondition(metadata.http_status === 200, "metadata does not record HTTP 200");
requireCondition(metadata.forecast_origin_admissible === false, "metadata claims origin eligibility");
requireCondition(metadata.accounting_gate_effect === "NONE", "metadata claims a gate effect");
requireCondition(
  metadata.expected_members?.["CxI_DR_Summary.xlsx"] === EXPECTED.directSha256 &&
    metadata.expected_members?.["IxC_MS_Summary.xlsx"] === EXPECTED.marketSha256,
  "metadata member hashes changed",
);

const directWorkbook = await SpreadsheetFile.importXlsx(await FileBlob.load(directPath));
const marketWorkbook = await SpreadsheetFile.importXlsx(await FileBlob.load(marketPath));
const directSheet = directWorkbook.worksheets.getItem(String(YEAR));
const marketSheet = marketWorkbook.worksheets.getItem(String(YEAR));
requireCondition(
  asText(scalar(directSheet, "A1"), "direct title") ===
    "Direct Total Requirements, After Redefinitions - Summary",
  "direct title changed",
);
requireCondition(
  asText(scalar(directSheet, "A2"), "direct price basis") === "(in producers' prices)",
  "direct price basis changed",
);
requireCondition(
  asText(scalar(directSheet, "A3"), "direct publisher") ===
    "Bureau of Economic Analysis",
  "direct publisher changed",
);
requireCondition(asNumber(scalar(directSheet, "A4"), "direct year") === YEAR, "direct year changed");
requireCondition(
  asText(scalar(marketSheet, "A1"), "market title") ===
    "Market Share Matrix, After Redefinitions - Summary",
  "market title changed",
);
requireCondition(
  asText(scalar(marketSheet, "A2"), "market price basis") === "(in producers' prices)",
  "market price basis changed",
);
requireCondition(
  asText(scalar(marketSheet, "A3"), "market publisher") ===
    "Bureau of Economic Analysis",
  "market publisher changed",
);
requireCondition(asNumber(scalar(marketSheet, "A4"), "market year") === YEAR, "market year changed");

const industryCodes = textVector(row(directSheet, "C6:BU6", 71), "industry codes");
const industryDescriptions = textVector(
  row(directSheet, "C7:BU7", 71),
  "industry descriptions",
);
const commodityCodes = textVector(
  column(directSheet, "A8:A80", 73),
  "commodity codes",
);
const commodityDescriptions = textVector(
  column(directSheet, "B8:B80", 73),
  "commodity descriptions",
);
const directValues = numberMatrix(
  matrix(directSheet, "C8:BU80", 73, 71),
  "direct requirements",
);
const valueAddedCodes = textVector(
  column(directSheet, "A81:A83", 3),
  "value-added codes",
);
const valueAddedDescriptions = textVector(
  column(directSheet, "B81:B83", 3),
  "value-added descriptions",
);
const valueAddedValues = numberMatrix(
  matrix(directSheet, "C81:BU83", 3, 71),
  "value added",
);
requireCondition(asText(scalar(directSheet, "B84"), "total label") === "Total", "total label changed");
const industryControls = row(directSheet, "C84:BU84", 71).map((value, index) =>
  asNumber(value, `industry controls[${index + 1}]`),
);

const marketCommodityCodes = textVector(
  row(marketSheet, "C6:BW6", 73),
  "market commodity codes",
);
const marketCommodityDescriptions = textVector(
  row(marketSheet, "C7:BW7", 73),
  "market commodity descriptions",
);
const marketIndustryCodes = textVector(
  column(marketSheet, "A8:A78", 71),
  "market industry codes",
);
const marketIndustryDescriptions = textVector(
  column(marketSheet, "B8:B78", 71),
  "market industry descriptions",
);
const marketValues = numberMatrix(
  matrix(marketSheet, "C8:BW78", 71, 73),
  "market shares",
);
requireCondition(
  JSON.stringify(industryCodes) === JSON.stringify(marketIndustryCodes) &&
    JSON.stringify(industryDescriptions) === JSON.stringify(marketIndustryDescriptions),
  "industry axes differ between workbooks",
);
requireCondition(
  JSON.stringify(commodityCodes) === JSON.stringify(marketCommodityCodes) &&
    JSON.stringify(commodityDescriptions) === JSON.stringify(marketCommodityDescriptions),
  "commodity axes differ between workbooks",
);
requireCondition(new Set(industryCodes).size === 71, "industry codes are not unique");
requireCondition(new Set(commodityCodes).size === 73, "commodity codes are not unique");
requireCondition(
  JSON.stringify(valueAddedCodes) === JSON.stringify(["V001", "V002", "V003"]),
  "value-added codes changed",
);
requireCondition(
  commodityCodes.includes("Other") && commodityCodes.includes("Used"),
  "explicit Other/Used commodities are missing",
);

const directControlResiduals = industryCodes.map((_, columnIndex) => {
  const direct = directValues.reduce(
    (sum, valuesRow) => sum + valuesRow[columnIndex],
    0,
  );
  const valueAdded = valueAddedValues.reduce(
    (sum, valuesRow) => sum + valuesRow[columnIndex],
    0,
  );
  return direct + valueAdded - industryControls[columnIndex];
});
const marketControlResiduals = commodityCodes.map(
  (_, columnIndex) =>
    marketValues.reduce((sum, valuesRow) => sum + valuesRow[columnIndex], 0) - 1,
);
const directTolerance =
  ((directValues.length + valueAddedValues.length + 1) / 2) *
  10 ** -DECIMAL_PLACES;
const marketTolerance =
  ((marketValues.length + 1) / 2) * 10 ** -DECIMAL_PLACES;
requireCondition(
  maximumAbsolute(directControlResiduals) <= directTolerance,
  "direct input/value-added controls fail",
);
requireCondition(
  maximumAbsolute(marketControlResiduals) <= marketTolerance,
  "market-share controls fail",
);
requireCondition(
  directValues.flat().filter((value) => value < 0).length === 5,
  "direct negative-cell count changed",
);
requireCondition(
  marketValues.flat().filter((value) => value < 0).length === 1,
  "market-share negative-cell count changed",
);

const fixtureRows = [];
addMatrix(
  fixtureRows,
  "commodity_by_industry_direct",
  commodityCodes,
  commodityDescriptions,
  "Commodity",
  industryCodes,
  industryDescriptions,
  "Industry",
  directValues,
);
addMatrix(
  fixtureRows,
  "industry_value_added",
  valueAddedCodes,
  valueAddedDescriptions,
  "ValueAdded",
  industryCodes,
  industryDescriptions,
  "Industry",
  valueAddedValues,
);
addMatrix(
  fixtureRows,
  "industry_control_total",
  ["Total"],
  ["Total"],
  "Control",
  industryCodes,
  industryDescriptions,
  "Industry",
  [industryControls],
);
addMatrix(
  fixtureRows,
  "industry_by_commodity_market_share",
  industryCodes,
  industryDescriptions,
  "Industry",
  commodityCodes,
  commodityDescriptions,
  "Commodity",
  marketValues,
);
fixtureRows.sort((left, right) => {
  if (left.matrix_id !== right.matrix_id) {
    return left.matrix_id < right.matrix_id ? -1 : 1;
  }
  return (
    left.row_position - right.row_position ||
    left.column_position - right.column_position
  );
});
requireCondition(fixtureRows.length === EXPECTED.fixtureCells, "fixture cell count changed");

const headers = [
  "matrix_id",
  "year",
  "row_position",
  "row_code",
  "row_description",
  "row_type",
  "column_position",
  "column_code",
  "column_description",
  "column_type",
  "value",
];
const csv =
  `${headers.join(",")}\n` +
  fixtureRows
    .map((fixtureRow) =>
      headers.map((header) => csvEscape(fixtureRow[header])).join(","),
    )
    .join("\n") +
  "\n";
const fixtureBytes = Buffer.from(csv, "utf8");
requireCondition(
  digest(fixtureBytes) === EXPECTED.fixtureSha256,
  "canonical fixture SHA-256 changed",
);
await fs.mkdir(outputDirectory, { recursive: true });
await fs.writeFile(path.join(outputDirectory, "cells.csv"), fixtureBytes);
await fs.writeFile(path.join(outputDirectory, "manifest.toml"), MANIFEST, "utf8");

const qaDirectory = path.join(outputDirectory, "qa");
await fs.mkdir(qaDirectory, { recursive: true });
await Promise.all([
  render(directWorkbook, qaDirectory, String(YEAR), "A1:L14", "direct_top_left.png"),
  render(directWorkbook, qaDirectory, String(YEAR), "BK1:BU14", "direct_top_right.png"),
  render(directWorkbook, qaDirectory, String(YEAR), "A76:L84", "direct_bottom_left.png"),
  render(directWorkbook, qaDirectory, String(YEAR), "BK76:BU84", "direct_bottom_right.png"),
  render(marketWorkbook, qaDirectory, String(YEAR), "A1:L14", "market_top_left.png"),
  render(marketWorkbook, qaDirectory, String(YEAR), "BM1:BW14", "market_top_right.png"),
  render(marketWorkbook, qaDirectory, String(YEAR), "A70:L78", "market_bottom_left.png"),
  render(marketWorkbook, qaDirectory, String(YEAR), "BM70:BW78", "market_bottom_right.png"),
]);
const summary = {
  schema_version: "beforeit-us-official-direct-requirements-extraction.v1",
  year: YEAR,
  source_zip_sha256: EXPECTED.zipSha256,
  source_metadata_sha256: EXPECTED.metadataSha256,
  direct_workbook_sha256: EXPECTED.directSha256,
  market_share_workbook_sha256: EXPECTED.marketSha256,
  fixture_sha256: EXPECTED.fixtureSha256,
  fixture_cell_count: fixtureRows.length,
  direct_control_maximum_absolute_residual: maximumAbsolute(directControlResiduals),
  direct_control_tolerance: directTolerance,
  market_share_control_maximum_absolute_residual:
    maximumAbsolute(marketControlResiduals),
  market_share_control_tolerance: marketTolerance,
  negative_direct_cell_count: 5,
  negative_market_share_cell_count: 1,
};
await fs.writeFile(
  path.join(qaDirectory, "extraction_summary.json"),
  `${JSON.stringify(summary, null, 2)}\n`,
  "utf8",
);
process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
