#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
let artifactToolApi = null;
let artifactToolEntry = null;

async function loadArtifactToolApi() {
  if (artifactToolApi === null) {
    const configuredNodeModules = process.env.BEFOREIT_NODE_MODULES;
    artifactToolEntry =
      configuredNodeModules === undefined
        ? fileURLToPath(import.meta.resolve("@oai/artifact-tool"))
        : require.resolve("@oai/artifact-tool", {
            paths: [
              path.basename(configuredNodeModules) === "node_modules"
                ? path.dirname(configuredNodeModules)
                : configuredNodeModules,
            ],
          });
    artifactToolApi = await import(pathToFileURL(artifactToolEntry).href);
  }
  return artifactToolApi;
}

const YEAR = 2017;
const SOURCE_URL =
  "https://apps.bea.gov/industry/release/zip/" +
  "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip";
const COMPONENT_CROSSWALK_URL =
  "https://apps.bea.gov/scb/issues/2018/08-august/pdf/" +
  "0818-industry-tables.pdf";
const EXPECTED = {
  artifactToolVersion: "2.8.39",
  independentOpenpyxlVersion: "3.1.5",
  openpyxlFallbackSha256:
    "91cbb1d62bb4c55963616b70eb4e2d8667c2917fedec1b708fc4c281dd529b01",
  sourceZip: {
    sha256:
      "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
    bytes: 8_326_144,
  },
  sourceMetadataSha256:
    "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878",
  componentCrosswalkSha256:
    "da7cba1018448321e6401dbe08614b73b3f0d9e65dfbd902a22b49cb95124ee0",
  componentCrosswalkDocument: {
    sha256:
      "c14a23ec44327fe8d8eb5d0e511234bbb30a3dccc5141087b1da6a5c4dd1c024",
    bytes: 219_021,
    pdfIndex: 14,
    printedPage: 15,
  },
  detailUse: {
    member: "IOUse_After_Redefinitions_PRO_Detail.xlsx",
    sha256:
      "ee0f977ccc6b884d3e3b912596e39c1036f513880531dda33be947e68fb03fe4",
    bytes: 2_113_284,
  },
  summaryUse: {
    member: "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    sha256:
      "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7",
    bytes: 1_163_798,
  },
  detailMake: {
    member: "IOMake_After_Redefinitions_PRO_Detail.xlsx",
    sha256:
      "96fb70a032e3ab81514231f49c2eae888b7ef8b741b00f352f2fc0fa8776db67",
    bytes: 1_472_556,
  },
  summaryMake: {
    member: "IOMake_After_Redefinitions_PRO_Summary.xlsx",
    sha256:
      "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
    bytes: 598_989,
  },
  fixtureCellCount: 3_644,
  fixtureSha256:
    "bb871c471b5bdc3dfea709749359717705167eff7e929bd9a2cc9071a21751e1",
};

const DETAIL_CODES = ["S00401", "S00402", "S00300", "S00900"];
const SUMMARY_CODES = ["Used", "Other"];
const FINAL_USE_CODES = [
  "F010",
  "F02S",
  "F02E",
  "F02N",
  "F02R",
  "F030",
  "F040",
  "F050",
  "F06C",
  "F06S",
  "F06E",
  "F06N",
  "F07C",
  "F07S",
  "F07E",
  "F07N",
  "F10C",
  "F10S",
  "F10E",
  "F10N",
];
const SUMMARY_INDUSTRY_CODES = [
  "111CA",
  "113FF",
  "211",
  "212",
  "213",
  "22",
  "23",
  "321",
  "327",
  "331",
  "332",
  "333",
  "334",
  "335",
  "3361MV",
  "3364OT",
  "337",
  "339",
  "311FT",
  "313TT",
  "315AL",
  "322",
  "323",
  "324",
  "325",
  "326",
  "42",
  "441",
  "445",
  "452",
  "4A0",
  "481",
  "482",
  "483",
  "484",
  "485",
  "486",
  "487OS",
  "493",
  "511",
  "512",
  "513",
  "514",
  "521CI",
  "523",
  "524",
  "525",
  "HS",
  "ORE",
  "532RL",
  "5411",
  "5415",
  "5412OP",
  "55",
  "561",
  "562",
  "61",
  "621",
  "622",
  "623",
  "624",
  "711AS",
  "713",
  "721",
  "722",
  "81",
  "GFGD",
  "GFGN",
  "GFE",
  "GSLG",
  "GSLE",
];
const HEADERS = [
  "projection_id",
  "year",
  "source_level",
  "source_table",
  "source_workbook_member",
  "source_sheet",
  "source_address",
  "row_position",
  "row_code",
  "row_description",
  "row_role",
  "row_summary_industry_code",
  "column_position",
  "column_code",
  "column_description",
  "column_role",
  "column_summary_industry_code",
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

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
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
    if (parent === directory) fail(`missing package metadata for ${packageName}`);
    directory = parent;
  }
}

function asText(value, label) {
  requireCondition(value !== null && value !== undefined, `${label} is blank`);
  const converted = String(value).trim();
  requireCondition(converted.length > 0, `${label} is blank`);
  return converted;
}

function sourceCell(value, label) {
  requireCondition(value !== undefined, `${label} is outside the source range`);
  if (value === null) {
    return { value: 0, sourceCellKind: "blank" };
  }
  if (value === "...") {
    return { value: 0, sourceCellKind: "ellipsis" };
  }
  requireCondition(
    value !== "",
    `${label} is an empty string rather than a native blank`,
  );
  const converted =
    typeof value === "number"
      ? value
      : Number(String(value).replaceAll(",", "").trim());
  requireCondition(Number.isFinite(converted), `${label} is not finite`);
  requireCondition(Number.isInteger(converted), `${label} is not a whole million`);
  return { value: converted, sourceCellKind: "numeric" };
}

function validateSourceMetadata(metadata) {
  requireCondition(
    metadata.schema_version === "beforeit-us-http-acquisition.v1",
    "source metadata schema changed",
  );
  requireCondition(metadata.source_url === SOURCE_URL, "source metadata URL changed");
  requireCondition(metadata.request_method === "GET", "source request method changed");
  requireCondition(metadata.http_status === 200, "source HTTP status changed");
  requireCondition(
    metadata.http_content_type === "application/x-zip-compressed",
    "source content type changed",
  );
  requireCondition(
    metadata.http_content_length === String(EXPECTED.sourceZip.bytes),
    "source content-length changed",
  );
  requireCondition(
    metadata.byte_count === EXPECTED.sourceZip.bytes &&
      metadata.expected_byte_count === EXPECTED.sourceZip.bytes,
    "source metadata byte count changed",
  );
  requireCondition(
    metadata.sha256 === EXPECTED.sourceZip.sha256 &&
      metadata.expected_sha256 === EXPECTED.sourceZip.sha256,
    "source metadata ZIP hash changed",
  );
  requireCondition(
    metadata.acquired_at_utc === "2026-08-06T05:03:02.322Z",
    "source acquisition timestamp changed",
  );
  requireCondition(
    metadata.http_etag === '"ebdebf1f182edc1:0"',
    "source ETag changed",
  );
  requireCondition(
    metadata.http_last_modified === "Thu, 25 Sep 2025 12:30:06 GMT",
    "source Last-Modified changed",
  );
  requireCondition(
    metadata.forecast_origin_admissible === false &&
      metadata.model_state_write === false &&
      metadata.accounting_gate_effect === "NONE",
    "source metadata admission boundary changed",
  );
  return metadata;
}

function validateComponentCrosswalk(crosswalk) {
  requireCondition(
    crosswalk.schema_version ===
      "beforeit-us-bea-special-component-crosswalk.v1",
    "component crosswalk schema changed",
  );
  requireCondition(
    crosswalk.source_document_url === COMPONENT_CROSSWALK_URL,
    "component crosswalk source URL changed",
  );
  requireCondition(
    crosswalk.source_document_sha256 ===
      EXPECTED.componentCrosswalkDocument.sha256 &&
      crosswalk.source_document_byte_count ===
        EXPECTED.componentCrosswalkDocument.bytes &&
      crosswalk.source_document_pdf_index ===
        EXPECTED.componentCrosswalkDocument.pdfIndex &&
      crosswalk.source_document_printed_page ===
        EXPECTED.componentCrosswalkDocument.printedPage,
    "component crosswalk source identity changed",
  );
  const mappings = crosswalk.mappings.map(
    ({ summary_code: summaryCode, detail_codes: detailCodes }) => ({
      summaryCode,
      detailCodes,
    }),
  );
  requireCondition(
    canonicalJson(mappings) ===
      canonicalJson([
        {
          summaryCode: "Used",
          detailCodes: ["S00401", "S00402"],
        },
        {
          summaryCode: "Other",
          detailCodes: ["S00300", "S00900"],
        },
      ]),
    "component crosswalk mappings changed",
  );
  return crosswalk;
}

if (process.argv.length === 3 && process.argv[2] === "--self-test") {
  requireCondition(sourceCell(null, "blank").sourceCellKind === "blank", "blank");
  requireCondition(
    sourceCell("...", "ellipsis").sourceCellKind === "ellipsis",
    "ellipsis",
  );
  requireCondition(sourceCell(0, "zero").sourceCellKind === "numeric", "zero");
  let outOfRangeRejected = false;
  try {
    sourceCell(undefined, "out-of-range");
  } catch {
    outOfRangeRejected = true;
  }
  requireCondition(outOfRangeRejected, "out-of-range source cell was not rejected");
  process.stdout.write("sourceCell native-kind self-test passed\n");
  process.exit(0);
}

function excelColumn(index) {
  let value = index + 1;
  let result = "";
  while (value > 0) {
    value -= 1;
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = Math.floor(value / 26);
  }
  return result;
}

function address(rowIndex, columnIndex) {
  return `${excelColumn(columnIndex)}${rowIndex + 1}`;
}

function sourceRange(rowEntries, columnEntries) {
  const rowIndices = rowEntries.map(({ index }) => index);
  const columnIndices = columnEntries.map(({ index }) => index);
  const first = address(Math.min(...rowIndices), Math.min(...columnIndices));
  const last = address(Math.max(...rowIndices), Math.max(...columnIndices));
  return `${YEAR}!${first}:${last}`;
}

function headerRows(...rowIndices) {
  return rowIndices.map((index) => ({ index }));
}

function axisColumns(...columnIndices) {
  return columnIndices.map((index) => ({ index }));
}

function csvEscape(value) {
  const converted = String(value);
  return /[",\r\n]/u.test(converted)
    ? `"${converted.replaceAll('"', '""')}"`
    : converted;
}

function csvBytes(rows) {
  const body = rows
    .map((fixtureRow) =>
      HEADERS.map((header) => csvEscape(fixtureRow[header])).join(","),
    )
    .join("\n");
  return Buffer.from(`${HEADERS.join(",")}\n${body}\n`, "utf8");
}

function tomlString(value) {
  return JSON.stringify(value);
}

function tomlStringArray(values) {
  return `[${values.map(tomlString).join(", ")}]`;
}

function canonicalFinalUseCode(code) {
  const converted = asText(code, "final-use code");
  return converted.endsWith("00") ? converted.slice(0, -2) : converted;
}

function findRow(values, code) {
  const index = values.findIndex(
    (candidate) => String(candidate[0] ?? "").trim() === code,
  );
  requireCondition(index >= 0, `missing row ${code}`);
  return index;
}

function findRowByDescription(values, description) {
  const candidates = values
    .map((row, index) => ({ index, value: String(row[1] ?? "").trim() }))
    .filter(({ value }) => value === description);
  requireCondition(
    candidates.length === 1,
    `missing or duplicate row description ${description}`,
  );
  return candidates[0].index;
}

function headerIndex(values, code) {
  const index = values[5].findIndex(
    (candidate) => String(candidate ?? "").trim() === code,
  );
  requireCondition(index >= 0, `missing column ${code}`);
  return index;
}

function textAt(values, row, column, label) {
  return asText(values[row][column], label);
}

function addProjection(
  fixtureRows,
  projections,
  {
    projectionId,
    sourceLevel,
    sourceTable,
    sourceMember,
    sourceRanges,
    values,
    rowEntries,
    columnEntries,
  },
) {
  const projectionRows = [];
  for (let rowPosition = 0; rowPosition < rowEntries.length; rowPosition += 1) {
    const rowEntry = rowEntries[rowPosition];
    for (
      let columnPosition = 0;
      columnPosition < columnEntries.length;
      columnPosition += 1
    ) {
      const columnEntry = columnEntries[columnPosition];
      const cell = sourceCell(
        values[rowEntry.index][columnEntry.index],
        `${projectionId}[${rowPosition + 1},${columnPosition + 1}]`,
      );
      const outputRow = {
        projection_id: projectionId,
        year: YEAR,
        source_level: sourceLevel,
        source_table: sourceTable,
        source_workbook_member: sourceMember,
        source_sheet: String(YEAR),
        source_address: address(rowEntry.index, columnEntry.index),
        row_position: rowPosition + 1,
        row_code: rowEntry.code,
        row_description: rowEntry.description,
        row_role: rowEntry.role,
        row_summary_industry_code: rowEntry.summaryIndustryCode ?? "",
        column_position: columnPosition + 1,
        column_code: columnEntry.code,
        column_description: columnEntry.description,
        column_role: columnEntry.role,
        column_summary_industry_code:
          columnEntry.summaryIndustryCode ?? "",
        value: cell.value,
        source_cell_kind: cell.sourceCellKind,
      };
      fixtureRows.push(outputRow);
      projectionRows.push(outputRow);
    }
  }
  projections.push({
    projectionId,
    sourceLevel,
    sourceTable,
    sourceMember,
    sourceRanges,
    rowCount: rowEntries.length,
    columnCount: columnEntries.length,
    cellCount: projectionRows.length,
    projectionSha256: digest(csvBytes(projectionRows)),
  });
}

async function readPinnedFile(
  sourceDirectory,
  specification,
  preextractedValues,
) {
  const sourcePath = path.join(sourceDirectory, specification.member);
  const bytes = await fs.readFile(sourcePath);
  requireCondition(
    bytes.length === specification.bytes,
    `${specification.member} byte count changed`,
  );
  requireCondition(
    digest(bytes) === specification.sha256,
    `${specification.member} SHA-256 changed`,
  );
  if (preextractedValues !== null) {
    const values = preextractedValues[specification.member];
    requireCondition(
      Array.isArray(values) && values.length > 0,
      `missing pre-extracted values for ${specification.member}`,
    );
    return values;
  }
  const { FileBlob, SpreadsheetFile } = await loadArtifactToolApi();
  const workbook = await SpreadsheetFile.importXlsx(
    await FileBlob.load(sourcePath),
  );
  return workbook.worksheets.getItem(String(YEAR)).getUsedRange().values;
}

if (process.argv.length !== 8) {
  fail(
    "usage: generate_after_redefinitions_2017_special_accounts_fixture.mjs " +
      "<source-directory> <source-zip> <source-metadata-json> " +
      "<component-crosswalk-json> <output-directory> <generation-receipt-json>",
  );
}
const [
  ,
  ,
  sourceDirectory,
  sourceZipPath,
  sourceMetadataPath,
  componentCrosswalkPath,
  outputDirectory,
  generationReceiptPath,
] = process.argv;
const preextractedValuesPath = process.env.BEFOREIT_PREEXTRACTED_VALUES_JSON;
const preextractedBundle =
  preextractedValuesPath === undefined
    ? null
    : JSON.parse(await fs.readFile(preextractedValuesPath, "utf8"));
if (preextractedBundle !== null) {
  requireCondition(
    preextractedBundle.generator_backend === "openpyxl" &&
      preextractedBundle.openpyxl_version ===
        EXPECTED.independentOpenpyxlVersion,
    "pre-extracted workbook backend or version changed",
  );
}
const preextractedValues = preextractedBundle?.workbooks ?? null;
const fallbackPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "extract_after_redefinitions_2017_special_accounts_values.py",
);
const generatorPath = fileURLToPath(import.meta.url);
const generatorSha256 = digest(await fs.readFile(generatorPath));
requireCondition(
  digest(await fs.readFile(fallbackPath)) === EXPECTED.openpyxlFallbackSha256,
  "openpyxl fallback extractor SHA-256 changed",
);

let readerBackend = "openpyxl";
let readerVersion = EXPECTED.independentOpenpyxlVersion;
if (preextractedValues === null) {
  await loadArtifactToolApi();
  readerBackend = "artifact_tool";
  readerVersion = await packageVersion(
    "@oai/artifact-tool",
    artifactToolEntry,
  );
  requireCondition(
    readerVersion === EXPECTED.artifactToolVersion,
    "artifact-tool version changed",
  );
}
const sourceMetadataBytes = await fs.readFile(sourceMetadataPath);
requireCondition(
  digest(sourceMetadataBytes) === EXPECTED.sourceMetadataSha256,
  "source metadata receipt SHA-256 changed",
);
const sourceMetadata = validateSourceMetadata(
  JSON.parse(sourceMetadataBytes.toString("utf8")),
);
const componentCrosswalkBytes = await fs.readFile(componentCrosswalkPath);
requireCondition(
  digest(componentCrosswalkBytes) === EXPECTED.componentCrosswalkSha256,
  "component crosswalk SHA-256 changed",
);
const componentCrosswalk = validateComponentCrosswalk(
  JSON.parse(componentCrosswalkBytes.toString("utf8")),
);
const sourceZipBytes = await fs.readFile(sourceZipPath);
requireCondition(
  sourceZipBytes.length === EXPECTED.sourceZip.bytes,
  "source ZIP byte count changed",
);
requireCondition(
  digest(sourceZipBytes) === EXPECTED.sourceZip.sha256,
  "source ZIP SHA-256 changed",
);
requireCondition(
  sourceMetadata.byte_count === sourceZipBytes.length &&
    sourceMetadata.sha256 === digest(sourceZipBytes),
  "source receipt does not describe the supplied ZIP bytes",
);

const detailUse = await readPinnedFile(
  sourceDirectory,
  EXPECTED.detailUse,
  preextractedValues,
);
const summaryUse = await readPinnedFile(
  sourceDirectory,
  EXPECTED.summaryUse,
  preextractedValues,
);
const detailMake = await readPinnedFile(
  sourceDirectory,
  EXPECTED.detailMake,
  preextractedValues,
);
const summaryMake = await readPinnedFile(
  sourceDirectory,
  EXPECTED.summaryMake,
  preextractedValues,
);

const detailIndustryColumnIndices = [];
for (let column = 2; column < headerIndex(detailUse, "T001"); column += 1) {
  detailIndustryColumnIndices.push(column);
}
requireCondition(
  detailIndustryColumnIndices.length === 402,
  "detail use must expose 402 industries",
);
const summaryIndustryColumnIndices = SUMMARY_INDUSTRY_CODES.map((code) =>
  headerIndex(summaryUse, code),
);
requireCondition(
  summaryIndustryColumnIndices.length === 71,
  "summary use must expose 71 industries",
);

const detailIndustryEntries = detailIndustryColumnIndices.map((index) => {
  const code = textAt(detailUse, 5, index, "detail industry code");
  return {
    index,
    code,
    description: textAt(detailUse, 4, index, `${code} description`),
    role: "Industry",
  };
});
requireCondition(
  new Set(detailIndustryEntries.map(({ code }) => code)).size === 402,
  "detail industry codes are not unique",
);

const summaryIndustryEntries = summaryIndustryColumnIndices.map((index) => {
  const code = textAt(summaryUse, 5, index, "summary industry code");
  return {
    index,
    code,
    description: textAt(summaryUse, 6, index, `${code} description`),
    role: "Industry",
    summaryIndustryCode: code,
  };
});
requireCondition(
  summaryIndustryEntries.map(({ code }) => code).join(",") ===
    SUMMARY_INDUSTRY_CODES.join(","),
  "summary industry order changed",
);

const detailSpecialUseRows = DETAIL_CODES.map((code) => {
  const index = findRow(detailUse, code);
  return {
    index,
    code,
    description: textAt(detailUse, index, 1, `${code} description`),
    role: "DetailedSpecialCommodity",
  };
});
const summarySpecialUseRows = SUMMARY_CODES.map((code) => {
  const index = findRow(summaryUse, code);
  return {
    index,
    code,
    description: textAt(summaryUse, index, 1, `${code} description`),
    role: "SummarySpecialCommodity",
  };
});

function finalUseEntries(values) {
  return FINAL_USE_CODES.map((code) => {
    const candidates = values[5]
      .map((value, index) => ({ value, index }))
      .filter(({ value }) => {
        if (value === null || value === undefined || value === "") return false;
        return canonicalFinalUseCode(value) === code;
      });
    requireCondition(candidates.length === 1, `missing or duplicate ${code}`);
    const index = candidates[0].index;
    return {
      index,
      code: asText(values[5][index], `${code} native code`),
      description: textAt(values, 4, index, `${code} description`),
      role: "FinalUse",
      summaryIndustryCode: code,
    };
  });
}
const detailFinalUseEntries = finalUseEntries(detailUse);
const summaryFinalUseEntries = FINAL_USE_CODES.map((code) => {
  const index = headerIndex(summaryUse, code);
  return {
    index,
    code,
    description: textAt(summaryUse, 6, index, `${code} description`),
    role: "FinalUse",
    summaryIndustryCode: code,
  };
});
const detailControlEntries = ["T001", "T004", "T007"].map((code) => {
  const index = headerIndex(detailUse, code);
  return {
    index,
    code,
    description: textAt(detailUse, 4, index, `${code} description`),
    role: "Control",
  };
});
const summaryControlDescriptions = new Map([
  ["T001", "Total Intermediate"],
  ["T004", "Total Final Uses (GDP)"],
  ["T007", "Total Commodity Output"],
]);
const summaryControlEntries = [...summaryControlDescriptions].map(
  ([code, description]) => {
    const index = summaryUse[6].findIndex(
      (value) => String(value ?? "").trim() === description,
    );
    requireCondition(index >= 0, `missing summary ${description}`);
    return { index, code, description, role: "Control" };
  },
);

const detailMakeIndustryRows = detailIndustryEntries.map((entry) => {
  const index = findRow(detailMake, entry.code);
  return {
    index,
    code: entry.code,
    description: textAt(detailMake, index, 1, `${entry.code} make description`),
    role: "Industry",
  };
});
const summaryMakeIndustryRows = summaryIndustryEntries.map((entry) => {
  const index = findRow(summaryMake, entry.code);
  return {
    index,
    code: entry.code,
    description: textAt(summaryMake, index, 1, `${entry.code} make description`),
    role: "Industry",
    summaryIndustryCode: entry.code,
  };
});
const detailMakeCommodityColumns = DETAIL_CODES.map((code) => {
  const index = headerIndex(detailMake, code);
  return {
    index,
    code,
    description: textAt(detailMake, 4, index, `${code} make description`),
    role: "DetailedSpecialCommodity",
  };
});
const summaryMakeCommodityColumns = SUMMARY_CODES.map((code) => {
  const index = headerIndex(summaryMake, code);
  return {
    index,
    code,
    description: textAt(summaryMake, 6, index, `${code} make description`),
    role: "SummarySpecialCommodity",
  };
});
const detailMakeOutputRowIndex = findRow(detailMake, "T007");
const summaryMakeOutputRowIndex = findRowByDescription(
  summaryMake,
  "Total Commodity Output",
);
requireCondition(
  summaryMakeOutputRowIndex === 78,
  "summary make Total Commodity Output moved from row 79",
);
const detailMakeOutputRows = [
  {
    index: detailMakeOutputRowIndex,
    code: "T007",
    description: "Total Commodity Output",
    role: "Control",
  },
];
const summaryMakeOutputRows = [
  {
    index: summaryMakeOutputRowIndex,
    code: "T007",
    description: "Total Commodity Output",
    role: "Control",
  },
];

const fixtureRows = [];
const projections = [];
for (const projection of [
  {
    projectionId: "detail_use_intermediate_2017",
    sourceLevel: "detail",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.detailUse.member,
    sourceRanges: [
      sourceRange(detailSpecialUseRows, axisColumns(0, 1)),
      sourceRange(headerRows(4, 5), detailIndustryEntries),
      sourceRange(detailSpecialUseRows, detailIndustryEntries),
    ],
    values: detailUse,
    rowEntries: detailSpecialUseRows,
    columnEntries: detailIndustryEntries,
  },
  {
    projectionId: "detail_use_final_2017",
    sourceLevel: "detail",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.detailUse.member,
    sourceRanges: [
      sourceRange(detailSpecialUseRows, axisColumns(0, 1)),
      sourceRange(headerRows(4, 5), detailFinalUseEntries),
      sourceRange(detailSpecialUseRows, detailFinalUseEntries),
    ],
    values: detailUse,
    rowEntries: detailSpecialUseRows,
    columnEntries: detailFinalUseEntries,
  },
  {
    projectionId: "detail_use_controls_2017",
    sourceLevel: "detail",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.detailUse.member,
    sourceRanges: [
      sourceRange(detailSpecialUseRows, axisColumns(0, 1)),
      ...detailControlEntries.flatMap((entry) => [
        sourceRange(headerRows(4, 5), [entry]),
        sourceRange(detailSpecialUseRows, [entry]),
      ]),
    ],
    values: detailUse,
    rowEntries: detailSpecialUseRows,
    columnEntries: detailControlEntries,
  },
  {
    projectionId: "summary_use_intermediate_2017",
    sourceLevel: "summary",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.summaryUse.member,
    sourceRanges: [
      sourceRange(summarySpecialUseRows, axisColumns(0, 1)),
      sourceRange(headerRows(5, 6), summaryIndustryEntries),
      sourceRange(summarySpecialUseRows, summaryIndustryEntries),
    ],
    values: summaryUse,
    rowEntries: summarySpecialUseRows,
    columnEntries: summaryIndustryEntries,
  },
  {
    projectionId: "summary_use_final_2017",
    sourceLevel: "summary",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.summaryUse.member,
    sourceRanges: [
      sourceRange(summarySpecialUseRows, axisColumns(0, 1)),
      sourceRange(headerRows(5, 6), summaryFinalUseEntries),
      sourceRange(summarySpecialUseRows, summaryFinalUseEntries),
    ],
    values: summaryUse,
    rowEntries: summarySpecialUseRows,
    columnEntries: summaryFinalUseEntries,
  },
  {
    projectionId: "summary_use_controls_2017",
    sourceLevel: "summary",
    sourceTable: "producer_use",
    sourceMember: EXPECTED.summaryUse.member,
    sourceRanges: [
      sourceRange(summarySpecialUseRows, axisColumns(0, 1)),
      ...summaryControlEntries.flatMap((entry) => [
        sourceRange(headerRows(5, 6), [entry]),
        sourceRange(summarySpecialUseRows, [entry]),
      ]),
    ],
    values: summaryUse,
    rowEntries: summarySpecialUseRows,
    columnEntries: summaryControlEntries,
  },
  {
    projectionId: "detail_make_components_2017",
    sourceLevel: "detail",
    sourceTable: "producer_make",
    sourceMember: EXPECTED.detailMake.member,
    sourceRanges: [
      sourceRange(detailMakeIndustryRows, axisColumns(0, 1)),
      sourceRange(headerRows(4, 5), detailMakeCommodityColumns),
      sourceRange(detailMakeIndustryRows, detailMakeCommodityColumns),
    ],
    values: detailMake,
    rowEntries: detailMakeIndustryRows,
    columnEntries: detailMakeCommodityColumns,
  },
  {
    projectionId: "detail_make_output_2017",
    sourceLevel: "detail",
    sourceTable: "producer_make",
    sourceMember: EXPECTED.detailMake.member,
    sourceRanges: [
      sourceRange(headerRows(4, 5), detailMakeCommodityColumns),
      sourceRange(detailMakeOutputRows, detailMakeCommodityColumns),
    ],
    values: detailMake,
    rowEntries: detailMakeOutputRows,
    columnEntries: detailMakeCommodityColumns,
  },
  {
    projectionId: "summary_make_components_2017",
    sourceLevel: "summary",
    sourceTable: "producer_make",
    sourceMember: EXPECTED.summaryMake.member,
    sourceRanges: [
      sourceRange(summaryMakeIndustryRows, axisColumns(0, 1)),
      sourceRange(headerRows(5, 6), summaryMakeCommodityColumns),
      sourceRange(summaryMakeIndustryRows, summaryMakeCommodityColumns),
    ],
    values: summaryMake,
    rowEntries: summaryMakeIndustryRows,
    columnEntries: summaryMakeCommodityColumns,
  },
  {
    projectionId: "summary_make_output_2017",
    sourceLevel: "summary",
    sourceTable: "producer_make",
    sourceMember: EXPECTED.summaryMake.member,
    sourceRanges: [
      sourceRange(headerRows(5, 6), summaryMakeCommodityColumns),
      sourceRange(summaryMakeOutputRows, summaryMakeCommodityColumns),
    ],
    values: summaryMake,
    rowEntries: summaryMakeOutputRows,
    columnEntries: summaryMakeCommodityColumns,
  },
]) {
  addProjection(fixtureRows, projections, projection);
}
requireCondition(
  fixtureRows.length === EXPECTED.fixtureCellCount,
  `fixture cell count changed: ${fixtureRows.length}`,
);

const fixtureBytes = csvBytes(fixtureRows);
if (EXPECTED.fixtureSha256 !== null) {
  requireCondition(
    digest(fixtureBytes) === EXPECTED.fixtureSha256,
    "canonical fixture SHA-256 changed",
  );
}
const numericCount = fixtureRows.filter(
  ({ source_cell_kind: kind }) => kind === "numeric",
).length;
const nativeBlankCount = fixtureRows.filter(
  ({ source_cell_kind: kind }) => kind === "blank",
).length;
const ellipsisCount = fixtureRows.filter(
  ({ source_cell_kind: kind }) => kind === "ellipsis",
).length;
const selectedZeroCount = nativeBlankCount + ellipsisCount;
requireCondition(
  numericCount + nativeBlankCount + ellipsisCount === fixtureRows.length,
  "native source-cell kinds are not exhaustive",
);
const explicitNumericZeroCount = fixtureRows.filter(
  ({ source_cell_kind: kind, value }) => kind === "numeric" && value === 0,
).length;
const negativeCellCount = fixtureRows.filter(({ value }) => value < 0).length;
const manifestLines = [
  `schema_version = ${tomlString("beforeit-us-after-redefinitions-2017-special-accounts-fixture.v2")}`,
  `classification = ${tomlString("2017_BENCHMARK_CURRENT_ARCHIVE_SNAPSHOT_NOT_ORIGIN_ELIGIBLE")}`,
  `artifact_role = ${tomlString("VINTAGE_SPECIFIC_SPECIAL_ACCOUNT_RECONSTRUCTION_EVIDENCE_ONLY")}`,
  `promotion_status = ${tomlString("RESEARCH_ONLY_NOT_PROMOTED")}`,
  `year = ${YEAR}`,
  `benchmark_year = ${YEAR}`,
  `source_frequency = ${tomlString("annual benchmark")}`,
  `unit = ${tomlString("millions of current dollars")}`,
  `price_basis = ${tomlString("producers prices")}`,
  `detail_industry_count = 402`,
  `summary_industry_count = 71`,
  `detail_component_count = 4`,
  `summary_account_count = 2`,
  `final_use_count = 20`,
  `fixture_cell_count = ${fixtureRows.length}`,
  `fixture_sha256 = ${tomlString(digest(fixtureBytes))}`,
  `numeric_cell_count = ${numericCount}`,
  `selected_zero_not_shown_count = ${selectedZeroCount}`,
  `native_blank_count = ${nativeBlankCount}`,
  `ellipsis_not_shown_count = ${ellipsisCount}`,
  `explicit_numeric_zero_count = ${explicitNumericZeroCount}`,
  `negative_cell_count = ${negativeCellCount}`,
  `detail_to_summary_industry_crosswalk_pinned = false`,
  `component_crosswalk_pinned = true`,
  `intermediate_cellwise_reconstruction_claimed = false`,
  `make_cellwise_reconstruction_claimed = false`,
  `reconstruction_scope = ${tomlString("CODE_KEYED_FINAL_USE_AND_AGGREGATE_CONTROLS_ONLY")}`,
  `detail_component_codes = ${tomlStringArray(DETAIL_CODES)}`,
  `summary_account_codes = ${tomlStringArray(SUMMARY_CODES)}`,
  `final_use_codes = ${tomlStringArray(FINAL_USE_CODES)}`,
  `summary_industry_codes = ${tomlStringArray(SUMMARY_INDUSTRY_CODES)}`,
  `used_definition = ${tomlString("Used=S00401+S00402")}`,
  `other_definition = ${tomlString("Other=S00300+S00900")}`,
  `component_crosswalk_member = ${tomlString(path.basename(componentCrosswalkPath))}`,
  `component_crosswalk_sha256 = ${tomlString(EXPECTED.componentCrosswalkSha256)}`,
  `component_crosswalk_source_url = ${tomlString(COMPONENT_CROSSWALK_URL)}`,
  `component_crosswalk_source_sha256 = ${tomlString(EXPECTED.componentCrosswalkDocument.sha256)}`,
  `component_crosswalk_source_byte_count = ${EXPECTED.componentCrosswalkDocument.bytes}`,
  `component_crosswalk_source_pdf_index = ${EXPECTED.componentCrosswalkDocument.pdfIndex}`,
  `component_crosswalk_source_printed_page = ${EXPECTED.componentCrosswalkDocument.printedPage}`,
  `component_crosswalk_source_table_title = ${tomlString(componentCrosswalk.source_table_title)}`,
  `rounding_envelope_definition = ${tomlString("For each code-keyed final-use cell, absolute(two displayed detail components minus the independently displayed summary cell) <= 1.5 million dollars; T001, T004, T007, and aggregate make/output controls must reconstruct exactly.")}`,
  `source_mask_policy = ${tomlString("Every selected source cell retains one native kind: numeric, blank, or ellipsis. selected_zero_not_shown is derived as blank union ellipsis; numeric zero remains numeric; signs are never clipped.")}`,
  `source_make_placement_policy = ${tomlString("A nonzero make cell is a published source accounting placement, not identification of a technological producer, owner, government behavior, or model agent.")}`,
  `rest_of_world_adjustment_policy = ${tomlString("S00900 is retained with its published signs and make placement; this fixture makes no zero-cash inference and authorizes no replay of cash or GDP.")}`,
  `vintage_scope_policy = ${tomlString("All values and component shares are 2017-only evidence from the pinned current archive snapshot and must not be inferred, copied, or weighted into 2024 or another vintage.")}`,
  `source_url = ${tomlString(SOURCE_URL)}`,
  `source_retrieved_at_utc = ${tomlString(sourceMetadata.acquired_at_utc)}`,
  `source_zip_byte_count = ${EXPECTED.sourceZip.bytes}`,
  `source_zip_sha256 = ${tomlString(EXPECTED.sourceZip.sha256)}`,
  `source_metadata_sha256 = ${tomlString(EXPECTED.sourceMetadataSha256)}`,
  `source_metadata_member = ${tomlString(path.basename(sourceMetadataPath))}`,
  `generator_member = ${tomlString(path.basename(generatorPath))}`,
  `generator_sha256 = ${tomlString(generatorSha256)}`,
  `canonicalization_backend = ${tomlString("node_js_deterministic_csv_and_toml")}`,
  `accepted_reader_contracts = ${tomlStringArray(["openpyxl=3.1.5", "artifact_tool=2.8.39"])}`,
  `dual_reader_receipt_members = ${tomlStringArray(["generation_openpyxl.json", "generation_artifact_tool.json"])}`,
  `openpyxl_fallback_member = ${tomlString("extract_after_redefinitions_2017_special_accounts_values.py")}`,
  `openpyxl_fallback_sha256 = ${tomlString(EXPECTED.openpyxlFallbackSha256)}`,
  `detail_use_workbook_member = ${tomlString(EXPECTED.detailUse.member)}`,
  `detail_use_workbook_sha256 = ${tomlString(EXPECTED.detailUse.sha256)}`,
  `summary_use_workbook_member = ${tomlString(EXPECTED.summaryUse.member)}`,
  `summary_use_workbook_sha256 = ${tomlString(EXPECTED.summaryUse.sha256)}`,
  `detail_make_workbook_member = ${tomlString(EXPECTED.detailMake.member)}`,
  `detail_make_workbook_sha256 = ${tomlString(EXPECTED.detailMake.sha256)}`,
  `summary_make_workbook_member = ${tomlString(EXPECTED.summaryMake.member)}`,
  `summary_make_workbook_sha256 = ${tomlString(EXPECTED.summaryMake.sha256)}`,
  `runtime_materialization_selected = false`,
  `producer_agent_inference = false`,
  `government_producer_inference = false`,
  `zero_cash_inference = false`,
  `current_vintage_weight_inference = false`,
  `forecast_origin_admissible = false`,
  `model_state_write = false`,
  `calibration_dictionary_write = false`,
  `accounting_gate_effect = ${tomlString("NONE")}`,
  `emitted_runtime_keys = []`,
  `scientific_role = ${tomlString("Hermetic 2017 benchmark evidence for signed, mask-preserving reconstruction of BEA Used and Other code-keyed final-use cells and aggregate controls. Detailed and 71-industry intermediate/make cells are preserved independently, but no cellwise 402-to-71 reconstruction is claimed without a pinned official industry crosswalk. This is not a runtime transform, forecast origin, current-vintage split, or behavioral-agent identification.")}`,
];
for (const projection of projections) {
  manifestLines.push(
    "",
    "[[projection]]",
    `projection_id = ${tomlString(projection.projectionId)}`,
    `source_level = ${tomlString(projection.sourceLevel)}`,
    `source_table = ${tomlString(projection.sourceTable)}`,
    `source_member = ${tomlString(projection.sourceMember)}`,
    `source_ranges = ${tomlStringArray(projection.sourceRanges)}`,
    `row_count = ${projection.rowCount}`,
    `column_count = ${projection.columnCount}`,
    `cell_count = ${projection.cellCount}`,
    `projection_sha256 = ${tomlString(projection.projectionSha256)}`,
  );
}
const manifestBytes = Buffer.from(`${manifestLines.join("\n")}\n`, "utf8");

await fs.mkdir(outputDirectory, { recursive: true });
await fs.writeFile(path.join(outputDirectory, "cells.csv"), fixtureBytes);
await fs.writeFile(path.join(outputDirectory, "manifest.toml"), manifestBytes);
const generationReceipt = {
  accepted_reader_contract:
    readerBackend === "openpyxl"
      ? `openpyxl=${EXPECTED.independentOpenpyxlVersion}`
      : `artifact_tool=${EXPECTED.artifactToolVersion}`,
  canonicalization_backend: "node_js_deterministic_csv_and_toml",
  component_crosswalk_sha256: EXPECTED.componentCrosswalkSha256,
  fixture_sha256: digest(fixtureBytes),
  generator_sha256: generatorSha256,
  manifest_sha256: digest(manifestBytes),
  reader_backend: readerBackend,
  reader_version: readerVersion,
  schema_version:
    "beforeit-us-after-redefinitions-2017-special-accounts-generation-receipt.v1",
  source_metadata_sha256: EXPECTED.sourceMetadataSha256,
  source_zip_sha256: EXPECTED.sourceZip.sha256,
};
await fs.mkdir(path.dirname(generationReceiptPath), { recursive: true });
await fs.writeFile(
  generationReceiptPath,
  Buffer.from(`${canonicalJson(generationReceipt)}\n`, "utf8"),
);
console.log(
  JSON.stringify(
    {
      fixture_cell_count: fixtureRows.length,
      fixture_sha256: digest(fixtureBytes),
      manifest_sha256: digest(manifestBytes),
      numeric_cell_count: numericCount,
      selected_zero_not_shown_count: selectedZeroCount,
      native_blank_count: nativeBlankCount,
      ellipsis_not_shown_count: ellipsisCount,
      explicit_numeric_zero_count: explicitNumericZeroCount,
      negative_cell_count: negativeCellCount,
      projection_count: projections.length,
      reader_backend: readerBackend,
      reader_version: readerVersion,
      generation_receipt_sha256: digest(
        Buffer.from(`${canonicalJson(generationReceipt)}\n`, "utf8"),
      ),
    },
    null,
    2,
  ),
);
