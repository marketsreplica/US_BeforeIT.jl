#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(SCRIPT_DIRECTORY, "../../..");
const FIXTURE_DIRECTORY = path.join(
  SCRIPT_DIRECTORY,
  "fixtures",
  "bea_after_redefinitions_display_semantics_approved",
);
const DEFAULT_CANONICAL_GRID_PATH = path.join(
  FIXTURE_DIRECTORY,
  "itable_canonical_common_basis_grid.csv",
);
const DEFAULT_PATHS = {
  commonBasisCells: path.join(
    SCRIPT_DIRECTORY,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
    "cells.csv",
  ),
  commonBasisManifest: path.join(
    SCRIPT_DIRECTORY,
    "fixtures",
    "bea_after_redefinitions_common_basis_approved",
    "manifest.toml",
  ),
  displaySemanticsCells: path.join(
    FIXTURE_DIRECTORY,
    "display_semantics.csv",
  ),
  displaySemanticsManifest: path.join(FIXTURE_DIRECTORY, "manifest.toml"),
  canonicalGrid: DEFAULT_CANONICAL_GRID_PATH,
};

const ENDPOINT =
  "https://apps.bea.gov/iTablecore/data/app/GetSteps";
const CANONICAL_JSON_SERIALIZATION =
  "RFC8259_RECURSIVE_LEXICOGRAPHIC_OBJECT_KEYS_UTF8_LF";
const COORDINATE_SERIALIZATION =
  "ROW_MAJOR_JSON_ARRAY_OF_ROW_CODE_COLUMN_CODE_PAIRS_UTF8_LF";
const CANONICAL_GRID_SERIALIZATION =
  "RFC4180_UTF8_LF_TABLE_THEN_ROW_MAJOR_COMMON_BASIS_ONLY";
const RECEIPT_SCHEMA =
  "beforeit-us-bea-itable-display-semantics-receipt.v2";

const EXPECTED = {
  sourceRelease: {
    sourceZipSha256:
      "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da",
    producerMakeWorkbookSha256:
      "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6",
    importWorkbookSha256:
      "9246c68288bb593495366288b9d8fd2038cae1ff500855ccd3e5c4377d0d3b25",
  },
  commonBasis: {
    cellsBytes: 5_122_845,
    cellsSha256:
      "6c0c44ca0ac3f70c5d51d6b3a58fca2a02283e9e6f50a254ae663d12f187f0ac",
    manifestBytes: 9_491,
    manifestSha256:
      "ff555043829e5d12ba787ba9ad7d58ef4f0d2ee306740d6847bdfec800935030",
    importProjectionIds: [
      "import_intermediate_use_2024",
      "import_commodity_controls_2024",
      "import_final_use_2024",
    ],
    makeProjectionIds: ["producer_make_2024"],
  },
  displaySemantics: {
    cellsBytes: 3_491,
    cellsSha256:
      "3091d35ae9a7268ee9025e8c242392c0eb45f757b9a1e3331bc872526df1de5e",
    manifestBytes: 1_908,
    manifestSha256:
      "74d869aa36636487a8acd13b9eb15d942e83e274f86ace852dbde1519b4f26ff",
  },
  tables: {
    UIMARI: {
      expectedTitle: "Import Matrix, After Redefinitions - Summary",
      requestBody:
        '{"appid":1602,"steps":[2,3,4],"data":[["Categories","AR"],' +
        '["Table_List","UIMARI"],["RbDetailLvl","SUM"],' +
        '["Last_Year","2024"]]}\n',
      requestBytes: 127,
      requestSha256:
        "c4b58e84b903541570bfea69bba4b8f2ac27e0f75dd0364a1e9bff0635a90084",
      transportResponseBytes: 937_351,
      transportResponseSha256:
        "75a281dd4227c2f5a945fa0960e56d3876dadb13d9b9c2cbd430e7cb1b418b1f",
      decodedResponseBytes: 590_655,
      decodedResponseSha256:
        "7b20401412415df349c4067d25d9a38576715c9f6b266372949f4dca9e3a50d3",
      canonicalTableBytes: 297_988,
      canonicalTableSha256:
        "7e86247570afd23bba1d7c9282cbfd72235f0c560e875d95d5f04a995612fc66",
      axesBytes: 1_106,
      axesSha256:
        "f6ad266dbb923f21eac721cb86e37c4c7b88bc9905b8441d6ef3a33fe113fe30",
      classesBytes: 66_461,
      classesSha256:
        "43a2301adafccc092bc5bbd31d89997201ca4a51786659e32b00c9e1e2e3344b",
      rowCount: 73,
      columnCount: 93,
      markerCount: 4_102,
      literalZeroCount: 369,
      responseFilename: "UIMARI-2024-explicit-response.json",
      commonBasisProjectionIds: [
        "import_intermediate_use_2024",
        "import_commodity_controls_2024",
        "import_final_use_2024",
      ],
    },
    MakeAR: {
      expectedTitle:
        "The Make of Commodities by Industries, " +
        "After Redefinitions - Summary",
      requestBody:
        '{"appid":1602,"steps":[2,3,4],"data":[["Categories","AR"],' +
        '["Table_List","MakeAR"],["RbDetailLvl","SUM"],' +
        '["Last_Year","2024"]]}\n',
      requestBytes: 127,
      requestSha256:
        "8478598e4819286c3a5d203f43d98f1f36f9621fa43a685db2d3850cd25bdf40",
      transportResponseBytes: 745_821,
      transportResponseSha256:
        "cbac08eeb2778ebb551911644e84e9e9e799e0f5949ab0a6856b523765940688",
      decodedResponseBytes: 471_373,
      decodedResponseSha256:
        "4f27324594c859c51aa42ac74f686b84c48a00f174f7528dcd889db8b3229e41",
      canonicalTableBytes: 237_851,
      canonicalTableSha256:
        "f956a7a671c329bc87d930dec0b7a5a7589e5ed5fec3e541c9d6e19677fc16f1",
      axesBytes: 958,
      axesSha256:
        "5f8d03464102e46d957a11120ebf4d818a7439c9e41a46d9156a32df2ca07cf8",
      classesBytes: 70_301,
      classesSha256:
        "2b39f113340cc37f291dce29c95cecad574acffe6e170a5c870083709a82707c",
      rowCount: 72,
      columnCount: 74,
      markerCount: 4_682,
      literalZeroCount: 84,
      responseFilename: "MakeAR-2024-explicit-response.json",
      commonBasisProjectionIds: ["producer_make_2024"],
    },
  },
};

const COMMON_BASIS_HEADERS = [
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
const CANONICAL_GRID_HEADERS = [
  "table_key",
  "api_row_position",
  "row_code",
  "api_column_position",
  "column_code",
  "api_token",
  "api_token_class",
  "api_numeric_value_millions",
  "authenticated_display_value_millions",
  "common_basis_source_cell_kind",
  "common_basis_value_millions",
  "exact_semantic_and_value_match",
];

function fail(message) {
  throw new Error(message);
}

function requireCondition(condition, message) {
  if (!condition) fail(message);
}

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

function canonicalJsonBytes(value) {
  return Buffer.from(`${JSON.stringify(stableValue(value))}\n`, "utf8");
}

function prettyCanonicalJsonBytes(value) {
  return Buffer.from(
    `${JSON.stringify(stableValue(value), null, 2)}\n`,
    "utf8",
  );
}

function csvField(value) {
  const text = String(value);
  return /[",\r\n]/u.test(text)
    ? `"${text.replaceAll('"', '""')}"`
    : text;
}

function canonicalGridBytes(records) {
  const lines = [
    CANONICAL_GRID_HEADERS.join(","),
    ...records.map((record) =>
      CANONICAL_GRID_HEADERS.map((header) =>
        csvField(record[header]),
      ).join(","),
    ),
  ];
  return Buffer.from(`${lines.join("\n")}\n`, "utf8");
}

function relativeRepositoryPath(targetPath) {
  const relative = path.relative(REPOSITORY_ROOT, path.resolve(targetPath));
  requireCondition(
    relative.length > 0 &&
      relative !== ".." &&
      !relative.startsWith(`..${path.sep}`),
    `${targetPath} is not inside the repository`,
  );
  return relative.split(path.sep).join("/");
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--fetch") {
      requireCondition(options.fetch === undefined, "--fetch repeated");
      options.fetch = true;
      continue;
    }
    const value = argv[index + 1];
    requireCondition(
      value !== undefined && !value.startsWith("--"),
      `${argument} requires a value`,
    );
    index += 1;
    const names = {
      "--response-directory": "responseDirectory",
      "--output": "output",
      "--observed-at-utc": "observedAtUtc",
      "--verify-receipt": "verifyReceipt",
      "--common-basis-cells": "commonBasisCells",
      "--common-basis-manifest": "commonBasisManifest",
      "--display-semantics-cells": "displaySemanticsCells",
      "--display-semantics-manifest": "displaySemanticsManifest",
      "--canonical-grid": "canonicalGrid",
      "--canonical-grid-output": "canonicalGridOutput",
    };
    requireCondition(names[argument] !== undefined, `unknown option ${argument}`);
    const name = names[argument];
    requireCondition(options[name] === undefined, `${argument} repeated`);
    options[name] = value;
  }
  return {
    ...DEFAULT_PATHS,
    ...options,
  };
}

function validateMode(options) {
  if (options.verifyReceipt !== undefined) {
    requireCondition(options.fetch === undefined, "verify mode cannot fetch");
    requireCondition(
      options.responseDirectory === undefined,
      "verify mode cannot read raw responses",
    );
    requireCondition(options.output === undefined, "verify mode cannot write");
    requireCondition(
      options.canonicalGridOutput === undefined,
      "verify mode cannot write a canonical grid",
    );
    requireCondition(
      options.observedAtUtc === undefined,
      "verify mode cannot change the observation timestamp",
    );
    return "verify";
  }
  requireCondition(
    (options.fetch === true) !== (options.responseDirectory !== undefined),
    "generation requires exactly one of --fetch or --response-directory",
  );
  requireCondition(options.output !== undefined, "generation requires --output");
  options.canonicalGridOutput ??= path.join(
    path.dirname(path.resolve(options.output)),
    path.basename(DEFAULT_CANONICAL_GRID_PATH),
  );
  requireCondition(
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(
      options.observedAtUtc ?? "",
    ),
    "generation requires canonical --observed-at-utc",
  );
  return "generate";
}

function parseCsv(text, label) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  let justClosedQuote = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"') {
        if (text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
          justClosedQuote = true;
        }
      } else {
        field += character;
      }
      continue;
    }
    if (character === '"') {
      requireCondition(field.length === 0, `${label}: quote inside field`);
      requireCondition(!justClosedQuote, `${label}: repeated quote`);
      quoted = true;
      continue;
    }
    if (character === ",") {
      row.push(field);
      field = "";
      justClosedQuote = false;
      continue;
    }
    if (character === "\n") {
      if (field.endsWith("\r")) field = field.slice(0, -1);
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      justClosedQuote = false;
      continue;
    }
    requireCondition(
      !justClosedQuote || character === "\r",
      `${label}: content after closing quote`,
    );
    field += character;
  }
  requireCondition(!quoted, `${label}: unterminated quote`);
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  requireCondition(rows.length > 1, `${label}: no data rows`);
  const headers = rows[0];
  requireCondition(
    new Set(headers).size === headers.length,
    `${label}: duplicate headers`,
  );
  for (let index = 1; index < rows.length; index += 1) {
    requireCondition(
      rows[index].length === headers.length,
      `${label}: row ${index + 1} has ${rows[index].length} fields, ` +
        `expected ${headers.length}`,
    );
  }
  return rows.slice(1).map((values) =>
    Object.fromEntries(
      headers.map((header, index) => [header, values[index]]),
    ),
  );
}

async function readPinnedFile(targetPath, expected, label) {
  const bytes = await fs.readFile(targetPath);
  requireCondition(
    bytes.length === expected.bytes,
    `${label} byte count changed: expected ${expected.bytes}, ` +
      `got ${bytes.length}`,
  );
  requireCondition(
    sha256(bytes) === expected.sha256,
    `${label} SHA-256 changed`,
  );
  return bytes;
}

function extractTable(rawResponseBytes, tableKey, expected) {
  let response;
  try {
    response = JSON.parse(rawResponseBytes.toString("utf8"));
  } catch (error) {
    fail(`${tableKey} response is not JSON: ${error.message}`);
  }
  requireCondition(response.Id === 1602, `${tableKey} app ID changed`);
  const step = response.Steps?.find((candidate) => candidate.Number === 4);
  requireCondition(step !== undefined, `${tableKey} step 4 missing`);
  const prompt = step.Prompts?.find(
    (candidate) => candidate.Name === "TheTable",
  );
  requireCondition(prompt !== undefined, `${tableKey} table prompt missing`);
  let wrapper;
  try {
    wrapper = JSON.parse(prompt.PromtData);
  } catch (error) {
    fail(`${tableKey} table wrapper is not JSON: ${error.message}`);
  }
  let table;
  try {
    table =
      typeof wrapper.Table === "string"
        ? JSON.parse(wrapper.Table)
        : wrapper.Table;
  } catch (error) {
    fail(`${tableKey} nested table is not JSON: ${error.message}`);
  }
  requireCondition(
    table?.Title === expected.expectedTitle,
    `${tableKey} title changed`,
  );
  requireCondition(
    table.Sub_Title === "2024, (Millions of dollars)",
    `${tableKey} subtitle changed`,
  );
  requireCondition(
    Array.isArray(table.Data_Rows),
    `${tableKey} data rows missing`,
  );
  return table;
}

function deriveAxesAndClasses(table, tableKey, expected) {
  const rows = table.Data_Rows;
  requireCondition(
    rows.length === expected.rowCount + 2,
    `${tableKey} row count changed`,
  );
  requireCondition(
    rows.every(
      (row) =>
        Array.isArray(row) && row.length === expected.columnCount + 2,
    ),
    `${tableKey} column count changed`,
  );
  const columnCodes = rows[0].slice(2).map((cell) => String(cell.CV));
  const rowCodes = rows.slice(2).map((row) => String(row[0].CV));
  requireCondition(
    columnCodes.length === expected.columnCount,
    `${tableKey} column axis changed`,
  );
  requireCondition(
    rowCodes.length === expected.rowCount,
    `${tableKey} row axis changed`,
  );
  requireCondition(
    new Set(columnCodes).size === columnCodes.length,
    `${tableKey} column codes are not unique`,
  );
  requireCondition(
    new Set(rowCodes).size === rowCodes.length,
    `${tableKey} row codes are not unique`,
  );

  const classes = {
    literal_zero: [],
    marker_triple_dash: [],
  };
  const cells = new Map();
  for (let rowIndex = 2; rowIndex < rows.length; rowIndex += 1) {
    const rowCode = rowCodes[rowIndex - 2];
    for (
      let columnIndex = 2;
      columnIndex < rows[rowIndex].length;
      columnIndex += 1
    ) {
      const columnCode = columnCodes[columnIndex - 2];
      const token = String(rows[rowIndex][columnIndex].CV);
      cells.set(coordinateKey(rowCode, columnCode), {
        columnPosition: columnIndex - 1,
        rowPosition: rowIndex - 1,
        token,
      });
      if (token === "0") {
        classes.literal_zero.push([rowCode, columnCode]);
      } else if (token === "---") {
        classes.marker_triple_dash.push([rowCode, columnCode]);
      }
    }
  }
  requireCondition(
    classes.marker_triple_dash.length === expected.markerCount,
    `${tableKey} marker count changed`,
  );
  requireCondition(
    classes.literal_zero.length === expected.literalZeroCount,
    `${tableKey} literal-zero count changed`,
  );
  return {
    axes: {
      column_codes: columnCodes,
      row_codes: rowCodes,
    },
    cells,
    classes,
  };
}

function coordinateKey(rowCode, columnCode) {
  return `${rowCode.length}:${rowCode}${columnCode.length}:${columnCode}`;
}

function commonBasisProjection(
  records,
  projectionIds,
  apiAxes,
  tableKey,
) {
  const projectionSet = new Set(projectionIds);
  const projectionRecords = records.filter((record) =>
    projectionSet.has(record.matrix_id),
  );
  requireCondition(
    new Set(projectionRecords.map((record) => record.matrix_id)).size ===
      projectionIds.length,
    `${tableKey} common-basis projections missing`,
  );

  const cells = new Map();
  for (const record of projectionRecords) {
    requireCondition(record.year === "2024", `${tableKey} year changed`);
    const key = coordinateKey(record.row_code, record.column_code);
    requireCondition(!cells.has(key), `${tableKey} duplicate cell ${key}`);
    requireCondition(
      record.source_cell_kind === "numeric" ||
        record.source_cell_kind === "selected_zero_not_shown",
      `${tableKey} unsupported source cell kind`,
    );
    const value = Number(record.value);
    requireCondition(
      Number.isFinite(value) && Number.isInteger(value),
      `${tableKey} non-integer source value`,
    );
    cells.set(key, {
      rowCode: record.row_code,
      columnCode: record.column_code,
      sourceCellKind: record.source_cell_kind,
      value,
    });
  }

  const apiRows =
    tableKey === "MakeAR" ? apiAxes.row_codes.slice(0, -1) : apiAxes.row_codes;
  const apiColumns =
    tableKey === "MakeAR"
      ? apiAxes.column_codes.slice(0, -1)
      : apiAxes.column_codes;
  const rowCodes = [...apiRows];
  const columnCodes = [...apiColumns];

  if (tableKey === "UIMARI") {
    requireCondition(rowCodes.length === 73, "UIMARI fixture rows changed");
    requireCondition(
      columnCodes.length === 93,
      "UIMARI fixture columns changed",
    );
  } else {
    requireCondition(rowCodes.length === 71, "MakeAR fixture rows changed");
    requireCondition(
      columnCodes.length === 73,
      "MakeAR fixture columns changed",
    );
  }

  const fixtureRows = new Set(
    projectionRecords.map((record) => record.row_code),
  );
  const fixtureColumns = new Set(
    projectionRecords.map((record) => record.column_code),
  );
  requireCondition(
    fixtureRows.size === rowCodes.length &&
      rowCodes.every((code) => fixtureRows.has(code)),
    `${tableKey} workbook/API row axes differ`,
  );
  requireCondition(
    fixtureColumns.size === columnCodes.length &&
      columnCodes.every((code) => fixtureColumns.has(code)),
    `${tableKey} workbook/API column axes differ`,
  );
  if (tableKey === "MakeAR") {
    requireCondition(
      apiAxes.row_codes.at(-1) === "" &&
        apiAxes.column_codes.at(-1) === "",
      "MakeAR API total axes changed",
    );
  }

  const classes = {
    literal_zero: [],
    marker_triple_dash: [],
  };
  for (const rowCode of rowCodes) {
    for (const columnCode of columnCodes) {
      const cell = cells.get(coordinateKey(rowCode, columnCode));
      requireCondition(
        cell !== undefined,
        `${tableKey} fixture cell missing at ${rowCode}/${columnCode}`,
      );
      if (cell.sourceCellKind === "selected_zero_not_shown") {
        requireCondition(
          cell.value === 0,
          `${tableKey} selected-zero fixture value is not zero`,
        );
        classes.marker_triple_dash.push([rowCode, columnCode]);
      } else if (cell.value === 0) {
        classes.literal_zero.push([rowCode, columnCode]);
      }
    }
  }
  requireCondition(
    cells.size === rowCodes.length * columnCodes.length,
    `${tableKey} fixture has cells outside its axes`,
  );
  return {
    axes: {
      column_codes: columnCodes,
      row_codes: rowCodes,
    },
    cells,
    classes,
    cellCount: cells.size,
  };
}

function parseApiIntegerToken(token, tableKey, rowCode, columnCode) {
  requireCondition(
    /^-?(?:0|[1-9]\d{0,2}(?:,\d{3})*|[1-9]\d*)$/u.test(token),
    `${tableKey} unsupported API token at ${rowCode}/${columnCode}: ${token}`,
  );
  const value = Number(token.replaceAll(",", ""));
  requireCondition(
    Number.isSafeInteger(value),
    `${tableKey} unsafe API integer at ${rowCode}/${columnCode}`,
  );
  return value;
}

function canonicalGridProjection(
  tableKey,
  apiProjection,
  commonProjection,
) {
  const records = [];
  let mismatchCount = 0;
  let exactMatchCount = 0;
  let maximumAbsoluteDifferenceMillions = 0;
  const tokenClassCounts = {
    LITERAL_ZERO: 0,
    MARKER_TRIPLE_DASH: 0,
    NONZERO_INTEGER: 0,
  };
  for (const rowCode of commonProjection.axes.row_codes) {
    for (const columnCode of commonProjection.axes.column_codes) {
      const key = coordinateKey(rowCode, columnCode);
      const apiCell = apiProjection.cells.get(key);
      const commonCell = commonProjection.cells.get(key);
      requireCondition(
        apiCell !== undefined && commonCell !== undefined,
        `${tableKey} canonical-grid cell missing at ${rowCode}/${columnCode}`,
      );
      const marker = apiCell.token === "---";
      const apiNumericValue = marker
        ? null
        : parseApiIntegerToken(
            apiCell.token,
            tableKey,
            rowCode,
            columnCode,
          );
      const displayValue = marker ? 0 : apiNumericValue;
      const tokenClass = marker
        ? "MARKER_TRIPLE_DASH"
        : apiNumericValue === 0
          ? "LITERAL_ZERO"
          : "NONZERO_INTEGER";
      tokenClassCounts[tokenClass] += 1;
      const semanticMatch = marker
        ? commonCell.sourceCellKind === "selected_zero_not_shown"
        : commonCell.sourceCellKind === "numeric";
      const difference = displayValue - commonCell.value;
      const exactMatch = semanticMatch && difference === 0;
      if (exactMatch) {
        exactMatchCount += 1;
      } else {
        mismatchCount += 1;
      }
      maximumAbsoluteDifferenceMillions = Math.max(
        maximumAbsoluteDifferenceMillions,
        Math.abs(difference),
      );
      records.push({
        table_key: tableKey,
        api_row_position: apiCell.rowPosition,
        row_code: rowCode,
        api_column_position: apiCell.columnPosition,
        column_code: columnCode,
        api_token: apiCell.token,
        api_token_class: tokenClass,
        api_numeric_value_millions: apiNumericValue ?? "",
        authenticated_display_value_millions: displayValue,
        common_basis_source_cell_kind: commonCell.sourceCellKind,
        common_basis_value_millions: commonCell.value,
        exact_semantic_and_value_match: exactMatch ? "true" : "false",
      });
    }
  }
  requireCondition(
    records.length === commonProjection.cellCount,
    `${tableKey} canonical-grid row count changed`,
  );
  requireCondition(
    mismatchCount === 0 &&
      exactMatchCount === records.length &&
      maximumAbsoluteDifferenceMillions === 0,
    `${tableKey} full-grid equality failed: ${mismatchCount} mismatches; ` +
      `maximum absolute difference ${maximumAbsoluteDifferenceMillions}`,
  );
  return {
    exactMatchCount,
    maximumAbsoluteDifferenceMillions,
    mismatchCount,
    records,
    tokenClassCounts,
  };
}

function requireSameCoordinates(left, right, label) {
  requireCondition(
    JSON.stringify(left) === JSON.stringify(right),
    `${label} coordinates differ`,
  );
}

function fileBinding(targetPath, bytes) {
  return {
    byte_count: bytes.length,
    repository_path: relativeRepositoryPath(targetPath),
    sha256: sha256(bytes),
  };
}

function semanticNoteBinding(displayRecords) {
  const makeNote = displayRecords.find(
    (record) =>
      record.record_id === "PRODUCER_MAKE_2024_ZERO_VALUE_NOTE",
  );
  requireCondition(makeNote !== undefined, "producer-make zero note missing");
  requireCondition(
    makeNote.semantic_class === "SELECTED_ELLIPSIS_IS_PUBLISHED_ZERO",
    "producer-make zero-note classification changed",
  );
  requireCondition(
    makeNote.exact_text_or_value ===
      "Note. Selected data with zero values are not shown.",
    "producer-make zero-note text changed",
  );
  const importWitness = displayRecords.find(
    (record) => record.record_id === "IMPORT_2024_ELLIPSIS_WITNESS",
  );
  requireCondition(importWitness !== undefined, "import witness missing");
  requireCondition(
    importWitness.source_token === "...",
    "import workbook ellipsis witness changed",
  );
  return {
    import_workbook_witness_record_id: importWitness.record_id,
    import_workbook_witness_token: importWitness.source_token,
    producer_make_note_record_id: makeNote.record_id,
    producer_make_note_text: makeNote.exact_text_or_value,
  };
}

async function fetchResponse(tableKey, expected) {
  const requestBytes = Buffer.from(expected.requestBody, "utf8");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  let response;
  try {
    response = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "User-Agent": "BeforeIT-US-Forecasting-Research/1.0",
      },
      body: requestBytes,
      redirect: "error",
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
  requireCondition(
    response.ok,
    `${tableKey} HTTP response was ${response.status}`,
  );
  return Buffer.from(await response.arrayBuffer());
}

async function acquireResponses(options) {
  const entries = await Promise.all(
    Object.entries(EXPECTED.tables).map(async ([tableKey, expected]) => {
      const sourceBytes =
        options.fetch === true
          ? await fetchResponse(tableKey, expected)
          : await fs.readFile(
              path.join(
                options.responseDirectory,
                expected.responseFilename,
              ),
            );
      let parsed;
      try {
        parsed = JSON.parse(sourceBytes.toString("utf8"));
      } catch (error) {
        fail(`${tableKey} response is not JSON: ${error.message}`);
      }
      const response =
        typeof parsed === "string"
          ? {
              decodedBytes: Buffer.from(parsed, "utf8"),
              transportBytes: sourceBytes,
            }
          : {
              decodedBytes: sourceBytes,
              transportBytes: null,
            };
      return [tableKey, response];
    }),
  );
  return Object.fromEntries(entries);
}

function validateRequest(tableKey, expected) {
  const bytes = Buffer.from(expected.requestBody, "utf8");
  requireCondition(
    bytes.length === expected.requestBytes,
    `${tableKey} request byte count changed`,
  );
  requireCondition(
    sha256(bytes) === expected.requestSha256,
    `${tableKey} request SHA-256 changed`,
  );
  const parsed = JSON.parse(expected.requestBody);
  requireCondition(parsed.appid === 1602, `${tableKey} request app changed`);
  requireCondition(
    parsed.steps.join(",") === "2,3,4",
    `${tableKey} request steps changed`,
  );
  requireCondition(
    parsed.data.some(
      ([name, value]) => name === "Table_List" && value === tableKey,
    ),
    `${tableKey} request table selector changed`,
  );
}

function tableReceipt(
  tableKey,
  expected,
  response,
  table,
  apiProjection,
  commonProjection,
  gridProjection,
) {
  const canonicalTable = canonicalJsonBytes(table);
  const axes = canonicalJsonBytes(apiProjection.axes);
  const classes = canonicalJsonBytes(apiProjection.classes);
  for (const [label, bytes, expectedBytes, expectedSha256] of [
    [
      "decoded response",
      response.decodedBytes,
      expected.decodedResponseBytes,
      expected.decodedResponseSha256,
    ],
    [
      "canonical table",
      canonicalTable,
      expected.canonicalTableBytes,
      expected.canonicalTableSha256,
    ],
    ["axes", axes, expected.axesBytes, expected.axesSha256],
    ["cell classes", classes, expected.classesBytes, expected.classesSha256],
  ]) {
    requireCondition(
      bytes.length === expectedBytes,
      `${tableKey} ${label} byte count changed`,
    );
    requireCondition(
      sha256(bytes) === expectedSha256,
      `${tableKey} ${label} SHA-256 changed`,
    );
  }
  if (response.transportBytes !== null) {
    requireCondition(
      response.transportBytes.length === expected.transportResponseBytes &&
        sha256(response.transportBytes) ===
          expected.transportResponseSha256,
      `${tableKey} raw transport response changed`,
    );
  }

  requireSameCoordinates(
    apiProjection.classes.marker_triple_dash,
    commonProjection.classes.marker_triple_dash,
    `${tableKey} selected-zero marker`,
  );
  requireSameCoordinates(
    apiProjection.classes.literal_zero,
    commonProjection.classes.literal_zero,
    `${tableKey} literal-zero`,
  );

  const markerCoordinates = canonicalJsonBytes(
    apiProjection.classes.marker_triple_dash,
  );
  const zeroCoordinates = canonicalJsonBytes(
    apiProjection.classes.literal_zero,
  );
  const tableGrid = canonicalGridBytes(gridProjection.records);
  return {
    api_axes: {
      byte_count: axes.length,
      column_codes: apiProjection.axes.column_codes,
      column_count: apiProjection.axes.column_codes.length,
      row_codes: apiProjection.axes.row_codes,
      row_count: apiProjection.axes.row_codes.length,
      sha256: sha256(axes),
    },
    api_canonical_table: {
      byte_count: canonicalTable.length,
      sha256: sha256(canonicalTable),
    },
    api_cell_classes: {
      byte_count: classes.length,
      literal_zero: {
        coordinate_count: apiProjection.classes.literal_zero.length,
        coordinate_set_sha256: sha256(zeroCoordinates),
        exact_common_basis_coordinate_match: true,
        source_token: "0",
      },
      marker_triple_dash: {
        coordinate_count:
          apiProjection.classes.marker_triple_dash.length,
        coordinate_set_sha256: sha256(markerCoordinates),
        exact_common_basis_coordinate_match: true,
        source_token: "---",
      },
      sha256: sha256(classes),
    },
    common_basis_projection: {
      cell_count: commonProjection.cellCount,
      column_count: commonProjection.axes.column_codes.length,
      projection_ids: expected.commonBasisProjectionIds,
      row_count: commonProjection.axes.row_codes.length,
    },
    full_common_basis_grid_comparison: {
      canonical_table_grid_byte_count: tableGrid.length,
      canonical_table_grid_sha256: sha256(tableGrid),
      exact_match_count: gridProjection.exactMatchCount,
      maximum_absolute_difference_millions:
        gridProjection.maximumAbsoluteDifferenceMillions,
      mismatch_count: gridProjection.mismatchCount,
      token_class_counts: gridProjection.tokenClassCounts,
    },
    http_request: {
      body_byte_count: expected.requestBytes,
      body_sha256: expected.requestSha256,
      body_utf8: expected.requestBody,
      content_type: "application/json",
      endpoint: ENDPOINT,
      method: "POST",
    },
    http_response: {
      decoded_json_document_byte_count:
        expected.decodedResponseBytes,
      decoded_json_document_sha256:
        expected.decodedResponseSha256,
      raw_transport_body_byte_count:
        expected.transportResponseBytes,
      raw_transport_body_sha256:
        expected.transportResponseSha256,
      transport_encoding:
        "HTTP_BODY_IS_JSON_STRING; JSON_DECODE_ONCE_FOR_DOCUMENT",
    },
    table_key: tableKey,
    title: table.Title,
  };
}

async function buildReceipt(options) {
  const [
    commonBasisCells,
    commonBasisManifest,
    displaySemanticsCells,
    displaySemanticsManifest,
  ] = await Promise.all([
    readPinnedFile(
      options.commonBasisCells,
      {
        bytes: EXPECTED.commonBasis.cellsBytes,
        sha256: EXPECTED.commonBasis.cellsSha256,
      },
      "common-basis cells",
    ),
    readPinnedFile(
      options.commonBasisManifest,
      {
        bytes: EXPECTED.commonBasis.manifestBytes,
        sha256: EXPECTED.commonBasis.manifestSha256,
      },
      "common-basis manifest",
    ),
    readPinnedFile(
      options.displaySemanticsCells,
      {
        bytes: EXPECTED.displaySemantics.cellsBytes,
        sha256: EXPECTED.displaySemantics.cellsSha256,
      },
      "display-semantics cells",
    ),
    readPinnedFile(
      options.displaySemanticsManifest,
      {
        bytes: EXPECTED.displaySemantics.manifestBytes,
        sha256: EXPECTED.displaySemantics.manifestSha256,
      },
      "display-semantics manifest",
    ),
  ]);
  const commonRecords = parseCsv(
    commonBasisCells.toString("utf8"),
    "common-basis cells",
  );
  requireCondition(
    JSON.stringify(Object.keys(commonRecords[0])) ===
      JSON.stringify(COMMON_BASIS_HEADERS),
    "common-basis headers changed",
  );
  const displayRecords = parseCsv(
    displaySemanticsCells.toString("utf8"),
    "display-semantics cells",
  );
  const semanticNotes = semanticNoteBinding(displayRecords);
  const rawResponses = await acquireResponses(options);

  const tableReceipts = [];
  const canonicalGridRecords = [];
  for (const [tableKey, expected] of Object.entries(EXPECTED.tables)) {
    validateRequest(tableKey, expected);
    const response = rawResponses[tableKey];
    requireCondition(
      response.decodedBytes.length === expected.decodedResponseBytes &&
        sha256(response.decodedBytes) === expected.decodedResponseSha256,
      `${tableKey} decoded response changed`,
    );
    const table = extractTable(response.decodedBytes, tableKey, expected);
    const apiProjection = deriveAxesAndClasses(table, tableKey, expected);
    const commonProjection = commonBasisProjection(
      commonRecords,
      expected.commonBasisProjectionIds,
      apiProjection.axes,
      tableKey,
    );
    const gridProjection = canonicalGridProjection(
      tableKey,
      apiProjection,
      commonProjection,
    );
    canonicalGridRecords.push(...gridProjection.records);
    tableReceipts.push(
      tableReceipt(
        tableKey,
        expected,
        response,
        table,
        apiProjection,
        commonProjection,
        gridProjection,
      ),
    );
  }

  const gridBytes = canonicalGridBytes(canonicalGridRecords);
  const receipt = {
    accounting_gate_effect: "NONE",
    canonical_common_basis_grid: {
      ...fileBinding(options.canonicalGridOutput, gridBytes),
      exact_match_count: canonicalGridRecords.length,
      maximum_absolute_difference_millions: 0,
      mismatch_count: 0,
      row_count: canonicalGridRecords.length,
      serialization: CANONICAL_GRID_SERIALIZATION,
    },
    canonical_json_serialization: CANONICAL_JSON_SERIALIZATION,
    classification:
      "AUTHENTICATED_RELEASE_SCOPED_DISPLAY_SEMANTICS_EVIDENCE",
    conclusions: {
      api_request_release_selector_status: "ABSENT",
      import_ellipsis_display_value_millions: 0,
      import_ellipsis_evidence_status:
        "BEA_RELEASE_FAMILY_CORROBORATED_PUBLISHED_ZERO",
      import_ellipsis_scope:
        "PINNED_2025_ANNUAL_RELEASE_2024_SUMMARY_TABLE_ONLY",
      import_ellipsis_structural_zero_status: "NOT_ESTABLISHED",
      import_ellipsis_variance_status: "NOT_ESTABLISHED",
      make_marker_note_status: "AUTHENTICATED_SAME_TABLE_NOTE",
      missing_value_rule_status: "NOT_A_GENERIC_BEA_MISSING_VALUE_RULE",
      pinned_archive_content_identity_status:
        "FULL_COMMON_BASIS_TOKEN_VALUE_AND_SEMANTIC_MATCH",
    },
    coordinate_serialization: COORDINATE_SERIALIZATION,
    display_semantics_binding: {
      cells: fileBinding(
        options.displaySemanticsCells,
        displaySemanticsCells,
      ),
      manifest: fileBinding(
        options.displaySemanticsManifest,
        displaySemanticsManifest,
      ),
      ...semanticNotes,
    },
    forecast_score_effect: "NONE",
    observed_at_utc: options.observedAtUtc,
    promotion_status: "EVIDENCE_ONLY_NOT_SOLVER_ADMITTED",
    schema_version: RECEIPT_SCHEMA,
    source_binding: {
      common_basis_cells: fileBinding(
        options.commonBasisCells,
        commonBasisCells,
      ),
      common_basis_manifest: fileBinding(
        options.commonBasisManifest,
        commonBasisManifest,
      ),
      import_workbook_sha256:
        EXPECTED.sourceRelease.importWorkbookSha256,
      producer_make_workbook_sha256:
        EXPECTED.sourceRelease.producerMakeWorkbookSha256,
      source_archive_url:
        "https://apps.bea.gov/HistData/Files/Releases/Industry/2025/" +
        "GDP_by_Industry/Q2/Annual_September-25-2025/" +
        "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip",
      source_zip_sha256: EXPECTED.sourceRelease.sourceZipSha256,
    },
    tables: tableReceipts,
  };
  return { gridBytes, receipt };
}

function receiptTable(receipt, tableKey) {
  const table = receipt.tables?.find(
    (candidate) => candidate.table_key === tableKey,
  );
  requireCondition(table !== undefined, `${tableKey} receipt missing`);
  return table;
}

function verifyCanonicalGridTable(
  tableKey,
  table,
  commonProjection,
  records,
) {
  requireCondition(
    records.length === commonProjection.cellCount,
    `${tableKey} canonical-grid row count changed`,
  );
  const markerCoordinates = [];
  const zeroCoordinates = [];
  const tokenClassCounts = {
    LITERAL_ZERO: 0,
    MARKER_TRIPLE_DASH: 0,
    NONZERO_INTEGER: 0,
  };
  let exactMatchCount = 0;
  let mismatchCount = 0;
  let maximumAbsoluteDifferenceMillions = 0;
  let recordIndex = 0;
  for (
    let rowIndex = 0;
    rowIndex < commonProjection.axes.row_codes.length;
    rowIndex += 1
  ) {
    const rowCode = commonProjection.axes.row_codes[rowIndex];
    for (
      let columnIndex = 0;
      columnIndex < commonProjection.axes.column_codes.length;
      columnIndex += 1
    ) {
      const columnCode = commonProjection.axes.column_codes[columnIndex];
      const record = records[recordIndex];
      recordIndex += 1;
      requireCondition(
        record.table_key === tableKey &&
          record.row_code === rowCode &&
          record.column_code === columnCode &&
          record.api_row_position === String(rowIndex + 1) &&
          record.api_column_position === String(columnIndex + 1),
        `${tableKey} canonical-grid ordering/coordinate changed at row ` +
          `${recordIndex + 1}`,
      );
      const commonCell = commonProjection.cells.get(
        coordinateKey(rowCode, columnCode),
      );
      const marker = record.api_token === "---";
      const apiNumericValue = marker
        ? null
        : parseApiIntegerToken(
            record.api_token,
            tableKey,
            rowCode,
            columnCode,
          );
      const tokenClass = marker
        ? "MARKER_TRIPLE_DASH"
        : apiNumericValue === 0
          ? "LITERAL_ZERO"
          : "NONZERO_INTEGER";
      requireCondition(
        record.api_token_class === tokenClass &&
          record.api_numeric_value_millions ===
            (apiNumericValue === null ? "" : String(apiNumericValue)),
        `${tableKey} canonical-grid token classification changed at ` +
          `${rowCode}/${columnCode}`,
      );
      tokenClassCounts[tokenClass] += 1;
      if (marker) markerCoordinates.push([rowCode, columnCode]);
      if (apiNumericValue === 0) zeroCoordinates.push([rowCode, columnCode]);
      const displayValue = marker ? 0 : apiNumericValue;
      const semanticMatch = marker
        ? commonCell.sourceCellKind === "selected_zero_not_shown"
        : commonCell.sourceCellKind === "numeric";
      const difference = displayValue - commonCell.value;
      const exactMatch =
        semanticMatch &&
        difference === 0 &&
        record.common_basis_source_cell_kind ===
          commonCell.sourceCellKind &&
        record.common_basis_value_millions === String(commonCell.value) &&
        record.authenticated_display_value_millions ===
          String(displayValue) &&
        record.exact_semantic_and_value_match === "true";
      if (exactMatch) {
        exactMatchCount += 1;
      } else {
        mismatchCount += 1;
      }
      maximumAbsoluteDifferenceMillions = Math.max(
        maximumAbsoluteDifferenceMillions,
        Math.abs(difference),
      );
    }
  }
  requireSameCoordinates(
    markerCoordinates,
    commonProjection.classes.marker_triple_dash,
    `${tableKey} canonical-grid selected-zero marker`,
  );
  requireSameCoordinates(
    zeroCoordinates,
    commonProjection.classes.literal_zero,
    `${tableKey} canonical-grid literal-zero`,
  );
  const comparison = table.full_common_basis_grid_comparison;
  const tableBytes = canonicalGridBytes(records);
  requireCondition(
    comparison.canonical_table_grid_byte_count === tableBytes.length &&
      comparison.canonical_table_grid_sha256 === sha256(tableBytes) &&
      comparison.exact_match_count === exactMatchCount &&
      comparison.mismatch_count === mismatchCount &&
      comparison.maximum_absolute_difference_millions ===
        maximumAbsoluteDifferenceMillions &&
      JSON.stringify(comparison.token_class_counts) ===
        JSON.stringify(tokenClassCounts),
    `${tableKey} canonical-grid receipt summary changed`,
  );
  requireCondition(
    exactMatchCount === records.length &&
      mismatchCount === 0 &&
      maximumAbsoluteDifferenceMillions === 0,
    `${tableKey} offline full-grid equality failed: ${mismatchCount} ` +
      `mismatches; maximum absolute difference ` +
      `${maximumAbsoluteDifferenceMillions}`,
  );
  return { exactMatchCount, maximumAbsoluteDifferenceMillions, mismatchCount };
}

async function verifyReceipt(options) {
  const [
    receiptBytes,
    canonicalGrid,
    commonBasisCells,
    commonBasisManifest,
    displaySemanticsCells,
    displaySemanticsManifest,
  ] = await Promise.all([
    fs.readFile(options.verifyReceipt),
    fs.readFile(options.canonicalGrid),
    readPinnedFile(
      options.commonBasisCells,
      {
        bytes: EXPECTED.commonBasis.cellsBytes,
        sha256: EXPECTED.commonBasis.cellsSha256,
      },
      "common-basis cells",
    ),
    readPinnedFile(
      options.commonBasisManifest,
      {
        bytes: EXPECTED.commonBasis.manifestBytes,
        sha256: EXPECTED.commonBasis.manifestSha256,
      },
      "common-basis manifest",
    ),
    readPinnedFile(
      options.displaySemanticsCells,
      {
        bytes: EXPECTED.displaySemantics.cellsBytes,
        sha256: EXPECTED.displaySemantics.cellsSha256,
      },
      "display-semantics cells",
    ),
    readPinnedFile(
      options.displaySemanticsManifest,
      {
        bytes: EXPECTED.displaySemantics.manifestBytes,
        sha256: EXPECTED.displaySemantics.manifestSha256,
      },
      "display-semantics manifest",
    ),
  ]);
  const receipt = JSON.parse(receiptBytes.toString("utf8"));
  requireCondition(
    receipt.schema_version === RECEIPT_SCHEMA,
    "receipt schema changed",
  );
  requireCondition(
    receipt.canonical_common_basis_grid.serialization ===
      CANONICAL_GRID_SERIALIZATION &&
      receipt.canonical_common_basis_grid.repository_path ===
        relativeRepositoryPath(options.canonicalGrid) &&
      receipt.canonical_common_basis_grid.byte_count ===
        canonicalGrid.length &&
      receipt.canonical_common_basis_grid.sha256 ===
        sha256(canonicalGrid),
    "canonical common-basis grid receipt binding changed",
  );
  requireCondition(
    receipt.canonical_json_serialization ===
      CANONICAL_JSON_SERIALIZATION,
    "receipt canonical serialization changed",
  );
  requireCondition(
    receipt.coordinate_serialization === COORDINATE_SERIALIZATION,
    "receipt coordinate serialization changed",
  );
  requireCondition(
    receiptBytes.equals(prettyCanonicalJsonBytes(receipt)),
    "receipt JSON is not canonical",
  );
  for (const [binding, targetPath, bytes, label] of [
    [
      receipt.source_binding.common_basis_cells,
      options.commonBasisCells,
      commonBasisCells,
      "common-basis cells",
    ],
    [
      receipt.source_binding.common_basis_manifest,
      options.commonBasisManifest,
      commonBasisManifest,
      "common-basis manifest",
    ],
    [
      receipt.display_semantics_binding.cells,
      options.displaySemanticsCells,
      displaySemanticsCells,
      "display-semantics cells",
    ],
    [
      receipt.display_semantics_binding.manifest,
      options.displaySemanticsManifest,
      displaySemanticsManifest,
      "display-semantics manifest",
    ],
  ]) {
    requireCondition(
      binding.repository_path === relativeRepositoryPath(targetPath) &&
        binding.byte_count === bytes.length &&
        binding.sha256 === sha256(bytes),
      `${label} receipt binding changed`,
    );
  }

  const commonRecords = parseCsv(
    commonBasisCells.toString("utf8"),
    "common-basis cells",
  );
  const canonicalGridRecords = parseCsv(
    canonicalGrid.toString("utf8"),
    "canonical common-basis grid",
  );
  requireCondition(
    JSON.stringify(Object.keys(canonicalGridRecords[0])) ===
      JSON.stringify(CANONICAL_GRID_HEADERS),
    "canonical common-basis grid headers changed",
  );
  let gridExactMatchCount = 0;
  let gridMismatchCount = 0;
  let gridMaximumAbsoluteDifferenceMillions = 0;
  let consumedGridRows = 0;
  for (const [tableKey, expected] of Object.entries(EXPECTED.tables)) {
    validateRequest(tableKey, expected);
    const table = receiptTable(receipt, tableKey);
    requireCondition(
      table.http_request.body_utf8 === expected.requestBody &&
        table.http_request.body_byte_count === expected.requestBytes &&
        table.http_request.body_sha256 === expected.requestSha256 &&
        table.http_request.endpoint === ENDPOINT &&
        table.http_request.method === "POST",
      `${tableKey} request receipt changed`,
    );
    requireCondition(
      table.http_response.raw_transport_body_byte_count ===
        expected.transportResponseBytes &&
        table.http_response.raw_transport_body_sha256 ===
          expected.transportResponseSha256 &&
        table.http_response.decoded_json_document_byte_count ===
          expected.decodedResponseBytes &&
        table.http_response.decoded_json_document_sha256 ===
          expected.decodedResponseSha256,
      `${tableKey} response receipt changed`,
    );
    requireCondition(
      table.api_canonical_table.byte_count ===
        expected.canonicalTableBytes &&
        table.api_canonical_table.sha256 ===
          expected.canonicalTableSha256,
      `${tableKey} canonical table receipt changed`,
    );
    requireCondition(
      table.api_axes.byte_count === expected.axesBytes &&
        table.api_axes.sha256 === expected.axesSha256 &&
        table.api_axes.row_count === expected.rowCount &&
        table.api_axes.column_count === expected.columnCount,
      `${tableKey} axes receipt changed`,
    );
    requireCondition(
      table.api_cell_classes.byte_count === expected.classesBytes &&
        table.api_cell_classes.sha256 === expected.classesSha256,
      `${tableKey} class receipt changed`,
    );

    const apiAxes = {
      column_codes: table.api_axes.column_codes,
      row_codes: table.api_axes.row_codes,
    };
    const axesBytes = canonicalJsonBytes(apiAxes);
    requireCondition(
      axesBytes.length === expected.axesBytes &&
        sha256(axesBytes) === expected.axesSha256,
      `${tableKey} stored axes do not reproduce their hash`,
    );
    const commonProjection = commonBasisProjection(
      commonRecords,
      expected.commonBasisProjectionIds,
      apiAxes,
      tableKey,
    );
    const tableGridRecords = canonicalGridRecords.slice(
      consumedGridRows,
      consumedGridRows + commonProjection.cellCount,
    );
    consumedGridRows += tableGridRecords.length;
    const gridResult = verifyCanonicalGridTable(
      tableKey,
      table,
      commonProjection,
      tableGridRecords,
    );
    gridExactMatchCount += gridResult.exactMatchCount;
    gridMismatchCount += gridResult.mismatchCount;
    gridMaximumAbsoluteDifferenceMillions = Math.max(
      gridMaximumAbsoluteDifferenceMillions,
      gridResult.maximumAbsoluteDifferenceMillions,
    );
    for (const [classKey, receiptKey, expectedCount] of [
      [
        "marker_triple_dash",
        "marker_triple_dash",
        expected.markerCount,
      ],
      ["literal_zero", "literal_zero", expected.literalZeroCount],
    ]) {
      const coordinates = canonicalJsonBytes(
        commonProjection.classes[classKey],
      );
      const classReceipt = table.api_cell_classes[receiptKey];
      requireCondition(
        classReceipt.coordinate_count === expectedCount &&
          classReceipt.coordinate_set_sha256 === sha256(coordinates) &&
          classReceipt.exact_common_basis_coordinate_match === true,
        `${tableKey} ${classKey} offline coordinate verification failed`,
      );
    }
  }
  requireCondition(
    consumedGridRows === canonicalGridRecords.length &&
      receipt.canonical_common_basis_grid.row_count ===
        canonicalGridRecords.length &&
      receipt.canonical_common_basis_grid.exact_match_count ===
        gridExactMatchCount &&
      receipt.canonical_common_basis_grid.mismatch_count ===
        gridMismatchCount &&
      receipt.canonical_common_basis_grid
        .maximum_absolute_difference_millions ===
        gridMaximumAbsoluteDifferenceMillions &&
      gridExactMatchCount === canonicalGridRecords.length &&
      gridMismatchCount === 0 &&
      gridMaximumAbsoluteDifferenceMillions === 0,
    "canonical common-basis grid aggregate verification failed",
  );
  requireCondition(
    receipt.conclusions.api_request_release_selector_status === "ABSENT" &&
      receipt.conclusions.pinned_archive_content_identity_status ===
        "FULL_COMMON_BASIS_TOKEN_VALUE_AND_SEMANTIC_MATCH" &&
      receipt.conclusions.import_ellipsis_evidence_status ===
      "BEA_RELEASE_FAMILY_CORROBORATED_PUBLISHED_ZERO" &&
      receipt.conclusions.import_ellipsis_structural_zero_status ===
        "NOT_ESTABLISHED" &&
      receipt.conclusions.import_ellipsis_variance_status ===
        "NOT_ESTABLISHED",
    "receipt conclusions changed",
  );
  return {
    canonicalGridBytes: canonicalGrid.length,
    canonicalGridRows: canonicalGridRecords.length,
    canonicalGridSha256: sha256(canonicalGrid),
    receiptBytes: receiptBytes.length,
    receiptSha256: sha256(receiptBytes),
  };
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const mode = validateMode(options);
  if (mode === "verify") {
    const result = await verifyReceipt(options);
    console.log(`canonical_grid_sha256=${result.canonicalGridSha256}`);
    console.log(`canonical_grid_bytes=${result.canonicalGridBytes}`);
    console.log(`canonical_grid_rows=${result.canonicalGridRows}`);
    console.log(`receipt_sha256=${result.receiptSha256}`);
    console.log(`receipt_bytes=${result.receiptBytes}`);
    console.log("offline_coordinate_verification=PASS");
    return;
  }
  const { gridBytes, receipt } = await buildReceipt(options);
  const receiptBytes = prettyCanonicalJsonBytes(receipt);
  await fs.mkdir(path.dirname(path.resolve(options.output)), {
    recursive: true,
  });
  await fs.mkdir(path.dirname(path.resolve(options.canonicalGridOutput)), {
    recursive: true,
  });
  await Promise.all([
    fs.writeFile(options.output, receiptBytes),
    fs.writeFile(options.canonicalGridOutput, gridBytes),
  ]);
  console.log(`canonical_grid_sha256=${sha256(gridBytes)}`);
  console.log(`canonical_grid_bytes=${gridBytes.length}`);
  console.log(
    `canonical_grid_rows=${receipt.canonical_common_basis_grid.row_count}`,
  );
  console.log(`receipt_sha256=${sha256(receiptBytes)}`);
  console.log(`receipt_bytes=${receiptBytes.length}`);
  console.log("api_common_basis_coordinate_match=PASS");
}

await main();
