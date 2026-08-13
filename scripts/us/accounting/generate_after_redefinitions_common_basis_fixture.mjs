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

const CURRENT_YEAR = 2024;
const BENCHMARK_YEAR = 2017;
const SOURCE_URL =
  "https://apps.bea.gov/industry/release/zip/" +
  "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip";
const EXPECTED = {
  artifactToolVersion: "2.8.39",
  zipSha256:
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
  zipBytes: 8_326_144,
  metadataSha256:
    "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878",
  producerUse: {
    member: "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    sha256:
      "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
    bytes: 1_163_798,
  },
  producerMake: {
    member: "IOMake_After_Redefinitions_PRO_Summary.xlsx",
    sha256:
      "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
    bytes: 598_989,
  },
  imports: {
    member: "ImportMatrices_After_Redefinitions_Summary.xlsx",
    sha256:
      "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25",
    bytes: 841_463,
  },
  purchaserUse: {
    member: "IOUse_After_Redefinitions_PUR_Summary.xlsx",
    sha256:
      "9d55530ec5cd4688855ef474c779d0dba5f2e1e74d4fcfcdc95cddc64c69262b",
    bytes: 129_070,
  },
  fixtureCells: 32_443,
  fixtureSha256:
    "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
  manifestSha256:
    "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
};

const HEADERS = [
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
  "source_cell_kind",
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

function scalar(sheet, address) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === 1 && values[0].length === 1,
    `${address} is not scalar`,
  );
  return values[0][0];
}

function row(sheet, address, expectedLength) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === 1 && values[0].length === expectedLength,
    `${address} has the wrong shape`,
  );
  return values[0];
}

function column(sheet, address, expectedLength) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === expectedLength &&
      values.every((entry) => entry.length === 1),
    `${address} has the wrong shape`,
  );
  return values.map((entry) => entry[0]);
}

function matrix(sheet, address, expectedRows, expectedColumns) {
  const values = sheet.getRange(address).values;
  requireCondition(
    values.length === expectedRows &&
      values.every((entry) => entry.length === expectedColumns),
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
    typeof value === "number"
      ? value
      : Number(String(value).replaceAll(",", "").trim());
  requireCondition(Number.isFinite(converted), `${label} is not finite`);
  return converted;
}

function textVector(values, label) {
  return values.map((value, index) =>
    asText(value, `${label}[${index + 1}]`),
  );
}

function sourceCell(value, label) {
  if (value === "...") {
    return { value: 0, sourceCellKind: "selected_zero_not_shown" };
  }
  requireCondition(
    value !== null && value !== undefined && value !== "",
    `${label} is blank rather than an explicit source cell`,
  );
  const numeric = asNumber(value, label);
  requireCondition(Number.isInteger(numeric), `${label} is not a whole million`);
  return { value: numeric, sourceCellKind: "numeric" };
}

function sourceMatrix(values, label) {
  return values.map((valuesRow, rowIndex) =>
    valuesRow.map((value, columnIndex) =>
      sourceCell(value, `${label}[${rowIndex + 1},${columnIndex + 1}]`),
    ),
  );
}

function csvEscape(value) {
  const converted = String(value);
  return /[",\r\n]/u.test(converted)
    ? `"${converted.replaceAll('"', '""')}"`
    : converted;
}

function csvBytes(rows) {
  const text =
    `${HEADERS.join(",")}\n` +
    rows
      .map((fixtureRow) =>
        HEADERS.map((header) => csvEscape(fixtureRow[header])).join(","),
      )
      .join("\n") +
    "\n";
  return Buffer.from(text, "utf8");
}

function addMatrix(
  projections,
  output,
  {
    matrixId,
    year,
    sourceMember,
    sourceRanges,
    rowCodes,
    rowDescriptions,
    rowType,
    columnCodes,
    columnDescriptions,
    columnType,
    values,
  },
) {
  requireCondition(
    rowCodes.length === rowDescriptions.length,
    `${matrixId} row metadata differs`,
  );
  requireCondition(
    columnCodes.length === columnDescriptions.length,
    `${matrixId} column metadata differs`,
  );
  requireCondition(
    new Set(rowCodes).size === rowCodes.length,
    `${matrixId} row codes are not unique`,
  );
  requireCondition(
    new Set(columnCodes).size === columnCodes.length,
    `${matrixId} column codes are not unique`,
  );
  requireCondition(values.length === rowCodes.length, `${matrixId} rows differ`);
  requireCondition(
    values.every((valuesRow) => valuesRow.length === columnCodes.length),
    `${matrixId} columns differ`,
  );
  const projectionRows = [];
  for (let rowIndex = 0; rowIndex < rowCodes.length; rowIndex += 1) {
    for (
      let columnIndex = 0;
      columnIndex < columnCodes.length;
      columnIndex += 1
    ) {
      const cell = values[rowIndex][columnIndex];
      const outputRow = {
        matrix_id: matrixId,
        year,
        row_position: rowIndex + 1,
        row_code: rowCodes[rowIndex],
        row_description: rowDescriptions[rowIndex],
        row_type: rowType,
        column_position: columnIndex + 1,
        column_code: columnCodes[columnIndex],
        column_description: columnDescriptions[columnIndex],
        column_type: columnType,
        value: cell.value,
        source_cell_kind: cell.sourceCellKind,
      };
      output.push(outputRow);
      projectionRows.push(outputRow);
    }
  }
  projections.push({
    matrixId,
    year,
    sourceMember,
    sourceRanges,
    rowType,
    columnType,
    rowCount: rowCodes.length,
    columnCount: columnCodes.length,
    cellCount: projectionRows.length,
    projectionSha256: digest(csvBytes(projectionRows)),
  });
}

function numericValues(cells) {
  return cells.map((valuesRow) => valuesRow.map((cell) => cell.value));
}

function flatten(values) {
  return values.flat();
}

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

function rowSums(values) {
  return values.map(sum);
}

function columnSums(values) {
  return values[0].map((_, columnIndex) =>
    sum(values.map((valuesRow) => valuesRow[columnIndex])),
  );
}

function maximumAbsolute(values) {
  return Math.max(...values.map((value) => Math.abs(value)));
}

function countNegative(values) {
  return flatten(values).filter((value) => value < 0).length;
}

function aggregateRetailRows(values, sourceCodes, targetCodes) {
  const targetIndex = new Map(
    targetCodes.map((code, index) => [code, index]),
  );
  const result = targetCodes.map(() => Array(values[0].length).fill(0));
  for (let rowIndex = 0; rowIndex < sourceCodes.length; rowIndex += 1) {
    const sourceCode = sourceCodes[rowIndex];
    const targetCode = ["441", "445", "452", "4A0"].includes(sourceCode)
      ? "4A0"
      : sourceCode;
    const destination = targetIndex.get(targetCode);
    requireCondition(
      destination !== undefined,
      `retail aggregation lacks ${targetCode}`,
    );
    for (
      let columnIndex = 0;
      columnIndex < values[rowIndex].length;
      columnIndex += 1
    ) {
      result[destination][columnIndex] += values[rowIndex][columnIndex];
    }
  }
  return result;
}

function tomlString(value) {
  return JSON.stringify(String(value));
}

function tomlStringArray(values) {
  return `[${values.map(tomlString).join(", ")}]`;
}

async function render(workbook, outputDirectory, sheetName, range, filename) {
  const blob = await workbook.render({
    sheetName,
    range,
    scale: 1,
    format: "png",
  });
  await fs.writeFile(
    path.join(outputDirectory, filename),
    new Uint8Array(await blob.arrayBuffer()),
  );
}

if (process.argv.length !== 10) {
  fail(
    "usage: node generate_after_redefinitions_common_basis_fixture.mjs " +
      "SOURCE_ZIP SOURCE_METADATA_JSON " +
      "IOUse_After_Redefinitions_PRO_Summary.xlsx " +
      "IOMake_After_Redefinitions_PRO_Summary.xlsx " +
      "ImportMatrices_After_Redefinitions_Summary.xlsx " +
      "IOUse_After_Redefinitions_PUR_Summary.xlsx " +
      "OUTPUT_DIRECTORY QA_DIRECTORY",
  );
}

const [
  ,
  ,
  zipPath,
  metadataPath,
  producerUsePath,
  producerMakePath,
  importPath,
  purchaserUsePath,
  outputDirectory,
  qaDirectory,
] = process.argv;

const artifactToolVersion = await packageVersion(
  "@oai/artifact-tool",
  artifactToolEntry,
);
requireCondition(
  artifactToolVersion === EXPECTED.artifactToolVersion,
  `@oai/artifact-tool version changed: expected ${EXPECTED.artifactToolVersion}, got ${artifactToolVersion}`,
);

const [
  zipBytes,
  metadataBytes,
  producerUseBytes,
  producerMakeBytes,
  importBytes,
  purchaserUseBytes,
] = await Promise.all([
  fs.readFile(zipPath),
  fs.readFile(metadataPath),
  fs.readFile(producerUsePath),
  fs.readFile(producerMakePath),
  fs.readFile(importPath),
  fs.readFile(purchaserUsePath),
]);
requireCondition(
  zipBytes.length === EXPECTED.zipBytes &&
    digest(zipBytes) === EXPECTED.zipSha256,
  "source ZIP bytes changed",
);
requireCondition(
  digest(metadataBytes) === EXPECTED.metadataSha256,
  "source acquisition metadata bytes changed",
);
for (const [label, bytes, expected] of [
  ["producer-use", producerUseBytes, EXPECTED.producerUse],
  ["producer-make", producerMakeBytes, EXPECTED.producerMake],
  ["import", importBytes, EXPECTED.imports],
  ["purchaser-use", purchaserUseBytes, EXPECTED.purchaserUse],
]) {
  requireCondition(
    bytes.length === expected.bytes && digest(bytes) === expected.sha256,
    `${label} workbook member changed`,
  );
}

const metadata = JSON.parse(metadataBytes.toString("utf8"));
requireCondition(metadata.source_url === SOURCE_URL, "metadata source URL changed");
requireCondition(metadata.sha256 === EXPECTED.zipSha256, "metadata ZIP hash changed");
requireCondition(metadata.byte_count === EXPECTED.zipBytes, "metadata byte count changed");
requireCondition(metadata.http_status === 200, "metadata lacks HTTP 200");
requireCondition(
  metadata.forecast_origin_admissible === false,
  "metadata claims origin eligibility",
);
requireCondition(
  metadata.accounting_gate_effect === "NONE",
  "metadata claims an accounting-gate effect",
);
requireCondition(
  metadata.model_state_write === false &&
    metadata.model_write_effect === "NONE",
  "metadata claims a model-state write",
);

const [
  producerUseWorkbook,
  producerMakeWorkbook,
  importWorkbook,
  purchaserUseWorkbook,
] = await Promise.all([
  SpreadsheetFile.importXlsx(await FileBlob.load(producerUsePath)),
  SpreadsheetFile.importXlsx(await FileBlob.load(producerMakePath)),
  SpreadsheetFile.importXlsx(await FileBlob.load(importPath)),
  SpreadsheetFile.importXlsx(await FileBlob.load(purchaserUsePath)),
]);

function validateSheet(sheet, title, year) {
  requireCondition(asText(scalar(sheet, "A1"), "title") === title, `${title} changed`);
  requireCondition(
    asText(scalar(sheet, "A2"), "unit") === "(Millions of dollars)",
    `${title} unit changed`,
  );
  requireCondition(
    asText(scalar(sheet, "A3"), "publisher") ===
      "Bureau of Economic Analysis",
    `${title} publisher changed`,
  );
  requireCondition(asNumber(scalar(sheet, "A4"), "year") === year, `${title} year changed`);
}

const producerUse2024 = producerUseWorkbook.worksheets.getItem(
  String(CURRENT_YEAR),
);
const producerMake2024 = producerMakeWorkbook.worksheets.getItem(
  String(CURRENT_YEAR),
);
const import2024 = importWorkbook.worksheets.getItem(String(CURRENT_YEAR));
const producerUse2017 = producerUseWorkbook.worksheets.getItem(
  String(BENCHMARK_YEAR),
);
const purchaserUse2017 = purchaserUseWorkbook.worksheets.getItem(
  String(BENCHMARK_YEAR),
);
validateSheet(
  producerUse2024,
  "The Use of Commodities by Industries, After Redefinitions (Producers' Prices) - Summary",
  CURRENT_YEAR,
);
validateSheet(
  producerMake2024,
  "The Make of Commodities by Industries, After Redefinitions - Summary",
  CURRENT_YEAR,
);
validateSheet(
  import2024,
  "Import Matrix, After Redefinitions",
  CURRENT_YEAR,
);
validateSheet(
  producerUse2017,
  "The Use of Commodities by Industries, After Redefinitions (Producers' Prices) - Summary",
  BENCHMARK_YEAR,
);
validateSheet(
  purchaserUse2017,
  "The Use of Commodities by Industries, After Redefinitions (Purchasers' Prices) - Summary",
  BENCHMARK_YEAR,
);

function useAxes(sheet, lastCommodityRow) {
  return {
    commodities: textVector(
      column(sheet, `A8:A${lastCommodityRow}`, lastCommodityRow - 7),
      "commodity codes",
    ),
    commodityDescriptions: textVector(
      column(sheet, `B8:B${lastCommodityRow}`, lastCommodityRow - 7),
      "commodity descriptions",
    ),
    industries: textVector(row(sheet, "C6:BU6", 71), "industry codes"),
    industryDescriptions: textVector(
      row(sheet, "C7:BU7", 71),
      "industry descriptions",
    ),
    finalUses: textVector(row(sheet, "BW6:CP6", 20), "final-use codes"),
    finalUseDescriptions: textVector(
      row(sheet, "BW7:CP7", 20),
      "final-use descriptions",
    ),
  };
}

const axes2024 = useAxes(producerUse2024, 80);
const axesProducer2017 = useAxes(producerUse2017, 80);
const axesPurchaser2017 = useAxes(purchaserUse2017, 77);
requireCondition(
  JSON.stringify(axes2024) === JSON.stringify(axesProducer2017),
  "2017 and 2024 producer-use axes changed",
);
requireCondition(
  JSON.stringify(axes2024.industries) ===
    JSON.stringify(axesPurchaser2017.industries),
  "2017 purchaser industry codes differ",
);
requireCondition(
  JSON.stringify(axes2024.finalUses) ===
    JSON.stringify(axesPurchaser2017.finalUses),
  "2017 purchaser final-use codes differ",
);
requireCondition(
  new Set(axes2024.commodities).size === 73 &&
    new Set(axes2024.industries).size === 71 &&
    new Set(axes2024.finalUses).size === 20,
  "2024 axes are not unique",
);
requireCondition(
  axes2024.commodities.includes("Used") &&
    axes2024.commodities.includes("Other") &&
    axes2024.finalUses.includes("F030"),
  "required closure or inventory codes are absent",
);

const makeIndustries = textVector(
  column(producerMake2024, "A8:A78", 71),
  "make industry codes",
);
const makeIndustryDescriptions = textVector(
  column(producerMake2024, "B8:B78", 71),
  "make industry descriptions",
);
const makeCommodities = textVector(
  row(producerMake2024, "C6:BW6", 73),
  "make commodity codes",
);
const makeCommodityDescriptions = textVector(
  row(producerMake2024, "C7:BW7", 73),
  "make commodity descriptions",
);
requireCondition(
  JSON.stringify(makeIndustries) === JSON.stringify(axes2024.industries) &&
    JSON.stringify(makeIndustryDescriptions) ===
      JSON.stringify(axes2024.industryDescriptions),
  "make/use industry axes differ",
);
requireCondition(
  JSON.stringify(makeCommodities) === JSON.stringify(axes2024.commodities),
  "make/use commodity codes differ",
);

const importAxes = useAxes(import2024, 80);
requireCondition(
  JSON.stringify(importAxes.commodities) ===
      JSON.stringify(axes2024.commodities) &&
    JSON.stringify(importAxes.industries) ===
      JSON.stringify(axes2024.industries) &&
    JSON.stringify(importAxes.finalUses) ===
      JSON.stringify(axes2024.finalUses),
  "import/use code axes differ",
);

const U2024 = sourceMatrix(
  matrix(producerUse2024, "C8:BU80", 73, 71),
  "2024 producer intermediate use",
);
const F2024 = sourceMatrix(
  matrix(producerUse2024, "BW8:CP80", 73, 20),
  "2024 producer final use",
);
const VA2024 = sourceMatrix(
  matrix(producerUse2024, "C82:BU84", 3, 71),
  "2024 value added",
);
const V2024 = sourceMatrix(
  matrix(producerMake2024, "C8:BW78", 71, 73),
  "2024 producer make",
);
const producerCommodityControls = [
  column(producerUse2024, "BV8:BV80", 73),
  column(producerUse2024, "CQ8:CQ80", 73),
  column(producerUse2024, "CR8:CR80", 73),
].map((control) => control.map((value) => sourceCell(value, "producer commodity control")));
const producerCommodityControlCells = axes2024.commodities.map((_, rowIndex) =>
  producerCommodityControls.map((control) => control[rowIndex]),
);
const producerIndustryControlCells = [
  row(producerUse2024, "C81:BU81", 71),
  row(producerUse2024, "C85:BU85", 71),
  row(producerUse2024, "C86:BU86", 71),
].map((control, controlIndex) =>
  control.map((value, columnIndex) =>
    sourceCell(value, `producer industry control[${controlIndex + 1},${columnIndex + 1}]`),
  ),
);
const makeCommodityOutput = sourceMatrix(
  row(producerMake2024, "C79:BW79", 73).map((value) => [value]),
  "make commodity output",
);
const makeIndustryOutput = sourceMatrix(
  column(producerMake2024, "BX8:BX78", 71).map((value) => [value]),
  "make industry output",
);
const producerUseGrandControls = sourceMatrix(
  [
    [
      scalar(producerUse2024, "BV81"),
      ...row(producerUse2024, "BW86:CP86", 20),
      scalar(producerUse2024, "CQ85"),
      scalar(producerUse2024, "CR86"),
    ],
  ],
  "producer-use grand controls",
);
const producerMakeGrandControl = sourceMatrix(
  [[scalar(producerMake2024, "BX79")]],
  "producer-make grand control",
);
const benchmarkProducerGrandControl = sourceMatrix(
  [[scalar(producerUse2017, "CR86")]],
  "2017 producer-use grand control",
);
const benchmarkPurchaserGrandControl = sourceMatrix(
  [[scalar(purchaserUse2017, "CR83")]],
  "2017 purchaser-use grand control",
);
const importU2024 = sourceMatrix(
  matrix(import2024, "C8:BU80", 73, 71),
  "2024 import intermediate use",
);
const importF2024 = sourceMatrix(
  matrix(import2024, "BW8:CP80", 73, 20),
  "2024 import final use",
);
const importControls = axes2024.commodities.map((_, rowIndex) => [
  sourceCell(
    column(import2024, "BV8:BV80", 73)[rowIndex],
    `import intermediate control[${rowIndex + 1}]`,
  ),
  sourceCell(
    column(import2024, "CQ8:CQ80", 73)[rowIndex],
    `import final control[${rowIndex + 1}]`,
  ),
]);
const UProducer2017 = sourceMatrix(
  matrix(producerUse2017, "C8:BU80", 73, 71),
  "2017 producer intermediate use",
);
const FProducer2017 = sourceMatrix(
  matrix(producerUse2017, "BW8:CP80", 73, 20),
  "2017 producer final use",
);
const UPurchaser2017 = sourceMatrix(
  matrix(purchaserUse2017, "C8:BU77", 70, 71),
  "2017 purchaser intermediate use",
);
const FPurchaser2017 = sourceMatrix(
  matrix(purchaserUse2017, "BW8:CP77", 70, 20),
  "2017 purchaser final use",
);

const fixtureRows = [];
const projections = [];
const common2024 = {
  year: CURRENT_YEAR,
  rowCodes: axes2024.commodities,
  rowDescriptions: axes2024.commodityDescriptions,
  rowType: "Commodity",
};
const importCommon2024 = {
  year: CURRENT_YEAR,
  rowCodes: importAxes.commodities,
  rowDescriptions: importAxes.commodityDescriptions,
  rowType: "Commodity",
};
const industryColumns = {
  columnCodes: axes2024.industries,
  columnDescriptions: axes2024.industryDescriptions,
  columnType: "Industry",
};
const finalUseColumns = {
  columnCodes: axes2024.finalUses,
  columnDescriptions: axes2024.finalUseDescriptions,
  columnType: "FinalUse",
};
const importIndustryColumns = {
  columnCodes: importAxes.industries,
  columnDescriptions: importAxes.industryDescriptions,
  columnType: "Industry",
};
const importFinalUseColumns = {
  columnCodes: importAxes.finalUses,
  columnDescriptions: importAxes.finalUseDescriptions,
  columnType: "FinalUse",
};
for (const projection of [
  {
    matrixId: "producer_intermediate_use_2024",
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2024!A8:B80", "2024!C6:BU7", "2024!C8:BU80"],
    ...common2024,
    ...industryColumns,
    values: U2024,
  },
  {
    matrixId: "producer_final_use_2024",
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2024!A8:B80", "2024!BW6:CP7", "2024!BW8:CP80"],
    ...common2024,
    ...finalUseColumns,
    values: F2024,
  },
  {
    matrixId: "producer_value_added_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2024!A82:B84", "2024!C6:BU7", "2024!C82:BU84"],
    rowCodes: ["V001", "V002", "V003"],
    rowDescriptions: textVector(
      column(producerUse2024, "B82:B84", 3),
      "value-added descriptions",
    ),
    rowType: "ValueAdded",
    ...industryColumns,
    values: VA2024,
  },
  {
    matrixId: "producer_make_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerMake.member,
    sourceRanges: ["2024!A8:B78", "2024!C6:BW7", "2024!C8:BW78"],
    rowCodes: makeIndustries,
    rowDescriptions: makeIndustryDescriptions,
    rowType: "Industry",
    columnCodes: makeCommodities,
    columnDescriptions: makeCommodityDescriptions,
    columnType: "Commodity",
    values: V2024,
  },
  {
    matrixId: "producer_use_commodity_controls_2024",
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2024!A8:B80", "2024!BV8:BV80", "2024!CQ8:CR80"],
    ...common2024,
    columnCodes: ["T001", "T004", "T007"],
    columnDescriptions: [
      "Total Intermediate",
      "Total Final Uses (GDP)",
      "Total Commodity Output",
    ],
    columnType: "Control",
    values: producerCommodityControlCells,
  },
  {
    matrixId: "producer_use_industry_controls_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2024!C6:BU7", "2024!C81:BU81", "2024!C85:BU86"],
    rowCodes: ["T001", "V004", "T017"],
    rowDescriptions: [
      "Total Intermediate",
      "Total Value Added",
      "Total Industry Output",
    ],
    rowType: "Control",
    ...industryColumns,
    values: producerIndustryControlCells,
  },
  {
    matrixId: "producer_make_commodity_output_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerMake.member,
    sourceRanges: ["2024!C6:BW7", "2024!C79:BW79"],
    rowCodes: makeCommodities,
    rowDescriptions: makeCommodityDescriptions,
    rowType: "Commodity",
    columnCodes: ["T007"],
    columnDescriptions: ["Total Commodity Output"],
    columnType: "Control",
    values: makeCommodityOutput,
  },
  {
    matrixId: "producer_make_industry_output_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerMake.member,
    sourceRanges: ["2024!A8:B78", "2024!BX8:BX78"],
    rowCodes: makeIndustries,
    rowDescriptions: makeIndustryDescriptions,
    rowType: "Industry",
    columnCodes: ["T017"],
    columnDescriptions: ["Total Industry Output"],
    columnType: "Control",
    values: makeIndustryOutput,
  },
  {
    matrixId: "producer_make_grand_output_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerMake.member,
    sourceRanges: ["2024!BX79"],
    rowCodes: ["GrandTotal"],
    rowDescriptions: ["Grand Total"],
    rowType: "Control",
    columnCodes: ["T017"],
    columnDescriptions: ["Total Industry Output"],
    columnType: "Control",
    values: producerMakeGrandControl,
  },
  {
    matrixId: "producer_use_grand_controls_2024",
    year: CURRENT_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: [
      "2024!BV81",
      "2024!BW6:CP7",
      "2024!BW86:CP86",
      "2024!CQ85",
      "2024!CR86",
    ],
    rowCodes: ["GrandTotal"],
    rowDescriptions: ["Grand Total"],
    rowType: "Control",
    columnCodes: ["T001", ...axes2024.finalUses, "V004", "T007"],
    columnDescriptions: [
      "Total Intermediate",
      ...axes2024.finalUseDescriptions,
      "Total Value Added",
      "Total Industry Output",
    ],
    columnType: "Control",
    values: producerUseGrandControls,
  },
  {
    matrixId: "import_intermediate_use_2024",
    sourceMember: EXPECTED.imports.member,
    sourceRanges: ["2024!A8:B80", "2024!C6:BU7", "2024!C8:BU80"],
    ...importCommon2024,
    ...importIndustryColumns,
    values: importU2024,
  },
  {
    matrixId: "import_final_use_2024",
    sourceMember: EXPECTED.imports.member,
    sourceRanges: ["2024!A8:B80", "2024!BW6:CP7", "2024!BW8:CP80"],
    ...importCommon2024,
    ...importFinalUseColumns,
    values: importF2024,
  },
  {
    matrixId: "import_commodity_controls_2024",
    sourceMember: EXPECTED.imports.member,
    sourceRanges: ["2024!A8:B80", "2024!BV8:BV80", "2024!CQ8:CQ80"],
    ...importCommon2024,
    columnCodes: ["T001", "T004"],
    columnDescriptions: ["Total Intermediate", "Total Final Uses (GDP)"],
    columnType: "Control",
    values: importControls,
  },
  {
    matrixId: "benchmark_producer_intermediate_use_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2017!A8:B80", "2017!C6:BU7", "2017!C8:BU80"],
    rowCodes: axesProducer2017.commodities,
    rowDescriptions: axesProducer2017.commodityDescriptions,
    rowType: "Commodity",
    columnCodes: axesProducer2017.industries,
    columnDescriptions: axesProducer2017.industryDescriptions,
    columnType: "Industry",
    values: UProducer2017,
  },
  {
    matrixId: "benchmark_producer_final_use_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2017!A8:B80", "2017!BW6:CP7", "2017!BW8:CP80"],
    rowCodes: axesProducer2017.commodities,
    rowDescriptions: axesProducer2017.commodityDescriptions,
    rowType: "Commodity",
    columnCodes: axesProducer2017.finalUses,
    columnDescriptions: axesProducer2017.finalUseDescriptions,
    columnType: "FinalUse",
    values: FProducer2017,
  },
  {
    matrixId: "benchmark_purchaser_intermediate_use_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.purchaserUse.member,
    sourceRanges: ["2017!A8:B77", "2017!C6:BU7", "2017!C8:BU77"],
    rowCodes: axesPurchaser2017.commodities,
    rowDescriptions: axesPurchaser2017.commodityDescriptions,
    rowType: "Commodity",
    columnCodes: axesPurchaser2017.industries,
    columnDescriptions: axesPurchaser2017.industryDescriptions,
    columnType: "Industry",
    values: UPurchaser2017,
  },
  {
    matrixId: "benchmark_purchaser_final_use_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.purchaserUse.member,
    sourceRanges: ["2017!A8:B77", "2017!BW6:CP7", "2017!BW8:CP77"],
    rowCodes: axesPurchaser2017.commodities,
    rowDescriptions: axesPurchaser2017.commodityDescriptions,
    rowType: "Commodity",
    columnCodes: axesPurchaser2017.finalUses,
    columnDescriptions: axesPurchaser2017.finalUseDescriptions,
    columnType: "FinalUse",
    values: FPurchaser2017,
  },
  {
    matrixId: "benchmark_producer_grand_output_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.producerUse.member,
    sourceRanges: ["2017!CR86"],
    rowCodes: ["GrandTotal"],
    rowDescriptions: ["Grand Total"],
    rowType: "Control",
    columnCodes: ["T007"],
    columnDescriptions: ["Total Commodity Output"],
    columnType: "Control",
    values: benchmarkProducerGrandControl,
  },
  {
    matrixId: "benchmark_purchaser_grand_output_2017",
    year: BENCHMARK_YEAR,
    sourceMember: EXPECTED.purchaserUse.member,
    sourceRanges: ["2017!CR83"],
    rowCodes: ["GrandTotal"],
    rowDescriptions: ["Grand Total"],
    rowType: "Control",
    columnCodes: ["T007"],
    columnDescriptions: ["Total Commodity Output"],
    columnType: "Control",
    values: benchmarkPurchaserGrandControl,
  },
]) {
  addMatrix(projections, fixtureRows, projection);
}

fixtureRows.sort(
  (left, right) =>
    left.matrix_id.localeCompare(right.matrix_id) ||
    left.year - right.year ||
    left.row_position - right.row_position ||
    left.column_position - right.column_position,
);
projections.sort((left, right) => left.matrixId.localeCompare(right.matrixId));
requireCondition(
  fixtureRows.length === EXPECTED.fixtureCells,
  "fixture cell count changed",
);

const UValues2024 = numericValues(U2024);
const FValues2024 = numericValues(F2024);
const VAValues2024 = numericValues(VA2024);
const VValues2024 = numericValues(V2024);
const importUValues2024 = numericValues(importU2024);
const importFValues2024 = numericValues(importF2024);
const producerCommodityControlValues = numericValues(
  producerCommodityControlCells,
);
const producerIndustryControlValues = numericValues(
  producerIndustryControlCells,
);
const makeCommodityOutputValues = flatten(numericValues(makeCommodityOutput));
const makeIndustryOutputValues = flatten(numericValues(makeIndustryOutput));
const importControlValues = numericValues(importControls);
const producerUseGrandControlValues = flatten(
  numericValues(producerUseGrandControls),
);
const producerMakeGrandControlValue =
  numericValues(producerMakeGrandControl)[0][0];
const benchmarkProducerGrandControlValue =
  numericValues(benchmarkProducerGrandControl)[0][0];
const benchmarkPurchaserGrandControlValue =
  numericValues(benchmarkPurchaserGrandControl)[0][0];

requireCondition(
  sum(flatten(UValues2024)) === 21_438_569 &&
    countNegative(UValues2024) === 5,
  "2024 producer-use totals or signs changed",
);
requireCondition(
  sum(flatten(VValues2024)) === 50_736_552 &&
    countNegative(VValues2024) === 1,
  "2024 make totals or signs changed",
);
requireCondition(
  sum(flatten(importUValues2024)) + sum(flatten(importFValues2024)) === -44 &&
    countNegative(importUValues2024) + countNegative(importFValues2024) === 58,
  "2024 import totals or signs changed",
);
requireCondition(
  sum(FValues2024.map((valuesRow) => valuesRow[5])) === 53_545,
  "2024 F030 inventory total changed",
);
requireCondition(
  sum(importFValues2024.map((valuesRow) => valuesRow[5])) === 1_850,
  "2024 import F030 total changed",
);

const producerIntermediateRows = producerCommodityControlValues.map(
  (valuesRow) => valuesRow[0],
);
const producerFinalRows = producerCommodityControlValues.map(
  (valuesRow) => valuesRow[1],
);
const producerCommodityOutput = producerCommodityControlValues.map(
  (valuesRow) => valuesRow[2],
);
requireCondition(
  maximumAbsolute(
    rowSums(UValues2024).map(
      (value, index) => value - producerIntermediateRows[index],
    ),
  ) <= 5,
  "producer intermediate row controls changed",
);
requireCondition(
  maximumAbsolute(
    rowSums(FValues2024).map(
      (value, index) => value - producerFinalRows[index],
    ),
  ) <= 2,
  "producer final-use row controls changed",
);
requireCondition(
  maximumAbsolute(
    producerIntermediateRows.map(
      (value, index) =>
        value + producerFinalRows[index] - producerCommodityOutput[index],
    ),
  ) <= 1,
  "producer commodity-output controls changed",
);
requireCondition(
  maximumAbsolute(
    columnSums(UValues2024).map(
      (value, index) => value - producerIndustryControlValues[0][index],
    ),
  ) <= 6,
  "producer intermediate column controls changed",
);
requireCondition(
  maximumAbsolute(
    columnSums(VAValues2024).map(
      (value, index) => value - producerIndustryControlValues[1][index],
    ),
  ) <= 1,
  "producer value-added controls changed",
);
requireCondition(
  maximumAbsolute(
    producerIndustryControlValues[0].map(
      (value, index) =>
        value +
        producerIndustryControlValues[1][index] -
        producerIndustryControlValues[2][index],
    ),
  ) <= 1,
  "producer industry-output controls changed",
);
requireCondition(
  maximumAbsolute(
    columnSums(VValues2024).map(
      (value, index) => value - makeCommodityOutputValues[index],
    ),
  ) <= 1 &&
    maximumAbsolute(
      rowSums(VValues2024).map(
        (value, index) => value - makeIndustryOutputValues[index],
      ),
    ) <= 3,
  "make controls changed",
);
requireCondition(
  maximumAbsolute(
    producerCommodityOutput.map(
      (value, index) => value - makeCommodityOutputValues[index],
    ),
  ) <= 1 &&
    maximumAbsolute(
      producerIndustryControlValues[2].map(
        (value, index) => value - makeIndustryOutputValues[index],
      ),
    ) === 0,
  "producer use/make output controls changed",
);
requireCondition(
  maximumAbsolute(
    rowSums(importUValues2024).map(
      (value, index) => value - importControlValues[index][0],
    ),
  ) <= 7 &&
    maximumAbsolute(
      rowSums(importFValues2024).map(
        (value, index) => value - importControlValues[index][1],
      ),
    ) <= 2,
  "import controls changed",
);
requireCondition(
  producerUseGrandControlValues[0] === 21_438_542 &&
    sum(producerUseGrandControlValues.slice(1, 21)) === 29_298_013 &&
    producerUseGrandControlValues[6] === 53_546 &&
    producerUseGrandControlValues[21] === 29_298_013 &&
    producerUseGrandControlValues[22] === 50_736_555,
  "producer-use grand controls changed",
);
requireCondition(
  producerMakeGrandControlValue === 50_736_556 &&
    producerUseGrandControlValues[21] -
      sum(producerUseGrandControlValues.slice(1, 21)) ===
      0 &&
    sum(producerFinalRows) - producerUseGrandControlValues[21] === -2 &&
    producerMakeGrandControlValue - producerUseGrandControlValues[22] === 1,
  "producer use/make grand-output controls changed",
);
requireCondition(
  benchmarkProducerGrandControlValue === 34_468_130 &&
    benchmarkPurchaserGrandControlValue === 34_468_130,
  "2017 producer/purchaser grand-output controls changed",
);

const producer2017 = numericValues(UProducer2017).map((valuesRow, rowIndex) => [
  ...valuesRow,
  ...numericValues(FProducer2017)[rowIndex],
]);
const purchaser2017 = numericValues(UPurchaser2017).map(
  (valuesRow, rowIndex) => [
    ...valuesRow,
    ...numericValues(FPurchaser2017)[rowIndex],
  ],
);
const aggregatedProducer2017 = aggregateRetailRows(
  producer2017,
  axesProducer2017.commodities,
  axesPurchaser2017.commodities,
);
const valuationDifference2017 = purchaser2017.flatMap((valuesRow, rowIndex) =>
  valuesRow.map(
    (value, columnIndex) =>
      value - aggregatedProducer2017[rowIndex][columnIndex],
  ),
);
requireCondition(
  sum(flatten(aggregatedProducer2017)) === 34_468_125 &&
    sum(flatten(purchaser2017)) === 34_468_139 &&
    sum(valuationDifference2017.map(Math.abs)) === 8_169_470,
  "2017 producer/purchaser valuation totals changed",
);
requireCondition(
  maximumAbsolute(
    columnSums(purchaser2017).map(
      (value, index) => value - columnSums(aggregatedProducer2017)[index],
    ),
  ) <= 5 &&
    countNegative(aggregatedProducer2017) === 70 &&
    countNegative(purchaser2017) === 68,
  "2017 valuation controls or signs changed",
);

const fixtureBytes = csvBytes(fixtureRows);
requireCondition(
  digest(fixtureBytes) === EXPECTED.fixtureSha256,
  "canonical fixture SHA-256 changed",
);
const selectedZeroCount = fixtureRows.filter(
  (fixtureRow) =>
    fixtureRow.source_cell_kind === "selected_zero_not_shown",
).length;
const explicitNumericZeroCount = fixtureRows.filter(
  (fixtureRow) =>
    fixtureRow.source_cell_kind === "numeric" && fixtureRow.value === 0,
).length;
const negativeCellCount = fixtureRows.filter(
  (fixtureRow) => fixtureRow.value < 0,
).length;

const manifestLines = [
  'accounting_gate_effect = "NONE"',
  `artifact_tool_version = ${tomlString(artifactToolVersion)}`,
  `benchmark_year = ${BENCHMARK_YEAR}`,
  `explicit_numeric_zero_count = ${explicitNumericZeroCount}`,
  `fixture_cell_count = ${fixtureRows.length}`,
  `fixture_sha256 = ${tomlString(digest(fixtureBytes))}`,
  "forecast_origin_admissible = false",
  `import_workbook_member = ${tomlString(EXPECTED.imports.member)}`,
  `import_workbook_sha256 = ${tomlString(EXPECTED.imports.sha256)}`,
  'model_state_write = false',
  `negative_cell_count = ${negativeCellCount}`,
  `projection_count = ${projections.length}`,
  `producer_make_workbook_member = ${tomlString(EXPECTED.producerMake.member)}`,
  `producer_make_workbook_sha256 = ${tomlString(EXPECTED.producerMake.sha256)}`,
  `producer_use_workbook_member = ${tomlString(EXPECTED.producerUse.member)}`,
  `producer_use_workbook_sha256 = ${tomlString(EXPECTED.producerUse.sha256)}`,
  'promotion_status = "RESEARCH_ONLY_NOT_PROMOTED"',
  `purchaser_use_workbook_member = ${tomlString(EXPECTED.purchaserUse.member)}`,
  `purchaser_use_workbook_sha256 = ${tomlString(EXPECTED.purchaserUse.sha256)}`,
  'schema_version = "beforeit-us-after-redefinitions-common-basis-fixture.v1"',
  `selected_zero_not_shown_count = ${selectedZeroCount}`,
  `source_metadata_sha256 = ${tomlString(EXPECTED.metadataSha256)}`,
  `source_retrieved_at_utc = ${tomlString(metadata.acquired_at_utc)}`,
  `source_url = ${tomlString(SOURCE_URL)}`,
  `source_zip_byte_count = ${EXPECTED.zipBytes}`,
  `source_zip_sha256 = ${tomlString(EXPECTED.zipSha256)}`,
  'status = "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"',
  'unit = "millions of current dollars"',
  'use_price_basis_2017_benchmark = "producers and purchasers prices, separate source tables"',
  'use_price_basis_2024 = "producers prices"',
  `year = ${CURRENT_YEAR}`,
  "",
  'preservation_policy = "Every projected source cell is retained. BEA ellipsis markers are numeric zero with source_cell_kind=selected_zero_not_shown; published numeric zero remains source_cell_kind=numeric. Negative cells, F030, Other, and Used are not clipped, balanced, allocated, or dropped."',
  'scientific_role = "Current-vintage common-basis accounting diagnostic. The 2017 purchaser/producer pair is a historical valuation benchmark, not a 2024 allocator and not forecast-origin evidence."',
];
for (const projection of projections) {
  manifestLines.push(
    "",
    "[[projection]]",
    `cell_count = ${projection.cellCount}`,
    `column_count = ${projection.columnCount}`,
    `column_type = ${tomlString(projection.columnType)}`,
    `matrix_id = ${tomlString(projection.matrixId)}`,
    `projection_sha256 = ${tomlString(projection.projectionSha256)}`,
    `row_count = ${projection.rowCount}`,
    `row_type = ${tomlString(projection.rowType)}`,
    `source_member = ${tomlString(projection.sourceMember)}`,
    `source_ranges = ${tomlStringArray(projection.sourceRanges)}`,
    `year = ${projection.year}`,
  );
}
const manifestBytes = Buffer.from(`${manifestLines.join("\n")}\n`, "utf8");
requireCondition(
  digest(manifestBytes) === EXPECTED.manifestSha256,
  "canonical manifest SHA-256 changed",
);

await fs.mkdir(outputDirectory, { recursive: true });
await fs.mkdir(qaDirectory, { recursive: true });
await fs.writeFile(path.join(outputDirectory, "cells.csv"), fixtureBytes);
await fs.writeFile(path.join(outputDirectory, "manifest.toml"), manifestBytes);
await Promise.all([
  render(
    producerUseWorkbook,
    qaDirectory,
    String(CURRENT_YEAR),
    "A1:CR14",
    "producer_use_2024_top.png",
  ),
  render(
    producerUseWorkbook,
    qaDirectory,
    String(CURRENT_YEAR),
    "A76:CR86",
    "producer_use_2024_controls.png",
  ),
  render(
    producerMakeWorkbook,
    qaDirectory,
    String(CURRENT_YEAR),
    "A1:BX14",
    "producer_make_2024_top.png",
  ),
  render(
    purchaserUseWorkbook,
    qaDirectory,
    String(BENCHMARK_YEAR),
    "A1:CR14",
    "purchaser_use_2017_top.png",
  ),
]);

const summary = {
  schema_version: "beforeit-us-after-redefinitions-extraction.v1",
  year: CURRENT_YEAR,
  benchmark_year: BENCHMARK_YEAR,
  artifact_tool_version: artifactToolVersion,
  source_zip_sha256: EXPECTED.zipSha256,
  source_metadata_sha256: EXPECTED.metadataSha256,
  fixture_sha256: digest(fixtureBytes),
  manifest_sha256: digest(manifestBytes),
  fixture_cell_count: fixtureRows.length,
  selected_zero_not_shown_count: selectedZeroCount,
  explicit_numeric_zero_count: explicitNumericZeroCount,
  negative_cell_count: negativeCellCount,
  producer_intermediate_total: sum(flatten(UValues2024)),
  producer_symmetric_input_basis_total: sum(flatten(UValues2024)),
  f030_total: sum(FValues2024.map((valuesRow) => valuesRow[5])),
  import_total:
    sum(flatten(importUValues2024)) + sum(flatten(importFValues2024)),
  benchmark_producer_total: sum(flatten(aggregatedProducer2017)),
  benchmark_purchaser_total: sum(flatten(purchaser2017)),
  benchmark_absolute_cell_difference: sum(
    valuationDifference2017.map(Math.abs),
  ),
};
await fs.writeFile(
  path.join(qaDirectory, "extraction_summary.json"),
  `${JSON.stringify(summary, null, 2)}\n`,
  "utf8",
);
process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
