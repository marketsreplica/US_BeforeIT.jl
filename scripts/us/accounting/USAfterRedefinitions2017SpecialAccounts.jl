module USAfterRedefinitions2017SpecialAccounts

using CSV
using SHA
using TOML

export MaskedSourceMatrix,
    ResidualLedger,
    SourceMakePlacement,
    SpecialAccountsFixture,
    SpecialAccountsProvenance,
    SpecialAccountReconstructionReport,
    after_redefinitions_2017_special_accounts_controls_pass,
    build_after_redefinitions_2017_special_accounts_diagnostic,
    load_after_redefinitions_2017_special_accounts,
    materialize_after_redefinitions_2017_special_accounts_model_state

const FIXTURE_SCHEMA =
    "beforeit-us-after-redefinitions-2017-special-accounts-fixture.v2"
const EXPECTED_CLASSIFICATION =
    "2017_BENCHMARK_CURRENT_ARCHIVE_SNAPSHOT_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_ARTIFACT_ROLE =
    "VINTAGE_SPECIFIC_SPECIAL_ACCOUNT_RECONSTRUCTION_EVIDENCE_ONLY"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_FIXTURE_SHA256 =
    "bb871c471b5bdc3dfea709749359717705167eff7e929bd9a2cc9071a21751e1"
const APPROVED_MANIFEST_SHA256 =
    "2432fecb0aa9ada6fe1dfc33aa51d17888df66676290c34a14bdb97e1aa3c31f"
const APPROVED_SOURCE_ZIP_SHA256 =
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
const APPROVED_SOURCE_METADATA_SHA256 =
    "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878"
const APPROVED_DETAIL_USE_SHA256 =
    "ee0f977ccc6b884d3e3b912596e39c1036f513880531dda33be947e68fb03fe4"
const APPROVED_SUMMARY_USE_SHA256 =
    "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7"
const APPROVED_DETAIL_MAKE_SHA256 =
    "96fb70a032e3ab81514231f49c2eae888b7ef8b741b00f352f2fc0fa8776db67"
const APPROVED_SUMMARY_MAKE_SHA256 =
    "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6"
const APPROVED_FALLBACK_SHA256 =
    "91cbb1d62bb4c55963616b70eb4e2d8667c2917fedec1b708fc4c281dd529b01"
const APPROVED_GENERATOR_SHA256 =
    "6a0562c1d858703a4ab47656712a3937d2b3971df0e6abc667684af4355b69f5"
const APPROVED_COMPONENT_CROSSWALK_SHA256 =
    "da7cba1018448321e6401dbe08614b73b3f0d9e65dfbd902a22b49cb95124ee0"
const APPROVED_COMPONENT_CROSSWALK_SOURCE_SHA256 =
    "c14a23ec44327fe8d8eb5d0e511234bbb30a3dccc5141087b1da6a5c4dd1c024"
const APPROVED_OPENPYXL_RECEIPT_SHA256 =
    "42c1d577b4b6b647592d6ab3c909538cb9f50b25a27c8dfcf212fae5e0f57f63"
const APPROVED_ARTIFACT_TOOL_RECEIPT_SHA256 =
    "4b121193e3099e1cf53e1e87908890b5ed54636cc286d38a84e56a12d11e26fa"
const APPROVED_FIXTURE_CELL_COUNT = 3_644
const APPROVED_NUMERIC_CELL_COUNT = 708
const APPROVED_SELECTED_ZERO_COUNT = 2_936
const APPROVED_NATIVE_BLANK_COUNT = 2_748
const APPROVED_ELLIPSIS_COUNT = 188
const APPROVED_EXPLICIT_NUMERIC_ZERO_COUNT = 50
const APPROVED_NEGATIVE_CELL_COUNT = 36
const EXPECTED_DETAIL_CODES = ["S00401", "S00402", "S00300", "S00900"]
const EXPECTED_SUMMARY_CODES = ["Used", "Other"]
const EXPECTED_FINAL_USE_CODES = [
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
]
const EXPECTED_SUMMARY_INDUSTRY_CODES = [
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
]
const EXPECTED_FINAL_RESIDUALS = Dict(
    ("Used", "F010") => -1.0,
    ("Used", "F040") => -1.0,
    ("Other", "F050") => 1.0,
)
const EXPECTED_DETAIL_USE_ROW_IDENTITY_RESIDUALS = [
    -1.0 0.0 0.0
    -1.0 3.0 0.0
    8.0 0.0 0.0
    0.0 0.0 0.0
]
const EXPECTED_SUMMARY_USE_ROW_IDENTITY_RESIDUALS = [
    0.0 1.0 0.0
    2.0 1.0 0.0
]
const EXPECTED_DETAIL_MAKE_IDENTITY_RESIDUALS = [-2.0, 0.0, 0.0, 0.0]
const EXPECTED_SUMMARY_MAKE_IDENTITY_RESIDUALS = [0.0, 0.0]
const FIXTURE_COLUMNS = [
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
]
const DEFAULT_FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_2017_special_accounts_vintage",
)
const GENERATOR_PATH =
    joinpath(@__DIR__, "generate_after_redefinitions_2017_special_accounts_fixture.mjs")
const SOURCE_METADATA_MEMBER = "source_acquisition_receipt.json"
const COMPONENT_CROSSWALK_MEMBER = "component_crosswalk.json"
const OPENPYXL_RECEIPT_MEMBER = "generation_openpyxl.json"
const ARTIFACT_TOOL_RECEIPT_MEMBER = "generation_artifact_tool.json"

const PROJECTION_SPECS = [
    (
        id = "detail_use_intermediate_2017",
        rows = 4,
        columns = 402,
        source_level = "detail",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Detail.xlsx",
    ),
    (
        id = "detail_use_final_2017",
        rows = 4,
        columns = 20,
        source_level = "detail",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Detail.xlsx",
    ),
    (
        id = "detail_use_controls_2017",
        rows = 4,
        columns = 3,
        source_level = "detail",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Detail.xlsx",
    ),
    (
        id = "summary_use_intermediate_2017",
        rows = 2,
        columns = 71,
        source_level = "summary",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    ),
    (
        id = "summary_use_final_2017",
        rows = 2,
        columns = 20,
        source_level = "summary",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    ),
    (
        id = "summary_use_controls_2017",
        rows = 2,
        columns = 3,
        source_level = "summary",
        source_table = "producer_use",
        source_member = "IOUse_After_Redefinitions_PRO_Summary.xlsx",
    ),
    (
        id = "detail_make_components_2017",
        rows = 402,
        columns = 4,
        source_level = "detail",
        source_table = "producer_make",
        source_member = "IOMake_After_Redefinitions_PRO_Detail.xlsx",
    ),
    (
        id = "detail_make_output_2017",
        rows = 1,
        columns = 4,
        source_level = "detail",
        source_table = "producer_make",
        source_member = "IOMake_After_Redefinitions_PRO_Detail.xlsx",
    ),
    (
        id = "summary_make_components_2017",
        rows = 71,
        columns = 2,
        source_level = "summary",
        source_table = "producer_make",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
    ),
    (
        id = "summary_make_output_2017",
        rows = 1,
        columns = 2,
        source_level = "summary",
        source_table = "producer_make",
        source_member = "IOMake_After_Redefinitions_PRO_Summary.xlsx",
    ),
]

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

"""One rectangular source projection with every native BEA cell kind retained."""
struct MaskedSourceMatrix
    projection_id::String
    year::Int
    source_level::Symbol
    source_table::Symbol
    source_workbook_member::String
    row_codes::Vector{String}
    row_descriptions::Vector{String}
    row_roles::Vector{Symbol}
    row_summary_industry_codes::Vector{String}
    column_codes::Vector{String}
    column_descriptions::Vector{String}
    column_roles::Vector{Symbol}
    column_summary_industry_codes::Vector{String}
    source_addresses::Matrix{String}
    values::Matrix{Float64}
    numeric_mask::BitMatrix
    blank_mask::BitMatrix
    ellipsis_mask::BitMatrix
    selected_zero_not_shown_mask::BitMatrix
end

"""Byte identities and fail-closed classification of the evidence fixture."""
struct SpecialAccountsProvenance
    fixture_sha256::String
    manifest_sha256::String
    source_zip_sha256::String
    source_metadata_sha256::String
    detail_use_workbook_sha256::String
    summary_use_workbook_sha256::String
    detail_make_workbook_sha256::String
    summary_make_workbook_sha256::String
    openpyxl_fallback_sha256::String
    generator_sha256::String
    component_crosswalk_sha256::String
    openpyxl_generation_receipt_sha256::String
    artifact_tool_generation_receipt_sha256::String
    classification::String
    promotion_status::String
end

"""All ten independent detail/summary projections for the 2017 vintage."""
struct SpecialAccountsFixture
    provenance::SpecialAccountsProvenance
    projections::Dict{String, MaskedSourceMatrix}
    manifest::Dict{String, Any}
end

"""Observed-minus-reconstructed residuals on an explicitly named axis."""
struct ResidualLedger
    account_codes::Vector{String}
    column_codes::Vector{String}
    reconstructed::Matrix{Float64}
    observed::Matrix{Float64}
    residuals::Matrix{Float64}
end

"""A nonzero source make cell, without a behavioral-producer inference."""
struct SourceMakePlacement
    source_level::Symbol
    industry_code::String
    industry_description::String
    account_code::String
    amount::Float64
    source_address::String
end

"""Narrow, vintage-specific reconstruction and source-boundary witness."""
struct SpecialAccountReconstructionReport
    provenance::SpecialAccountsProvenance
    final_use::ResidualLedger
    use_controls::ResidualLedger
    make_output::ResidualLedger
    detail_use_row_identity_residuals::Matrix{Float64}
    summary_use_row_identity_residuals::Matrix{Float64}
    detail_make_identity_residuals::Vector{Float64}
    summary_make_identity_residuals::Vector{Float64}
    detail_make_placements::Vector{SourceMakePlacement}
    summary_make_placements::Vector{SourceMakePlacement}
    detail_to_summary_industry_crosswalk_pinned::Bool
    component_crosswalk_pinned::Bool
    intermediate_cellwise_reconstruction_claimed::Bool
    make_cellwise_reconstruction_claimed::Bool
    runtime_materialization_selected::Bool
    producer_agent_inference::Bool
    government_producer_inference::Bool
    zero_cash_inference::Bool
    current_vintage_weight_inference::Bool
    forecast_origin_admissible::Bool
    model_state_write::Bool
    accounting_gate_effect::Symbol
end

function require_equal(actual, expected, label)
    actual == expected ||
        throw(ArgumentError("$label changed"))
    return nothing
end

function validate_manifest(manifest)
    require_equal(manifest["schema_version"], FIXTURE_SCHEMA, "fixture schema")
    require_equal(
        manifest["classification"],
        EXPECTED_CLASSIFICATION,
        "fixture classification",
    )
    require_equal(
        manifest["artifact_role"],
        EXPECTED_ARTIFACT_ROLE,
        "artifact role",
    )
    require_equal(
        manifest["promotion_status"],
        EXPECTED_PROMOTION_STATUS,
        "promotion status",
    )
    require_equal(Int(manifest["year"]), 2017, "fixture year")
    require_equal(Int(manifest["benchmark_year"]), 2017, "benchmark year")
    require_equal(
        Int(manifest["fixture_cell_count"]),
        APPROVED_FIXTURE_CELL_COUNT,
        "fixture cell count",
    )
    require_equal(
        Int(manifest["numeric_cell_count"]),
        APPROVED_NUMERIC_CELL_COUNT,
        "numeric cell count",
    )
    require_equal(
        Int(manifest["selected_zero_not_shown_count"]),
        APPROVED_SELECTED_ZERO_COUNT,
        "selected-zero cell count",
    )
    require_equal(
        Int(manifest["native_blank_count"]),
        APPROVED_NATIVE_BLANK_COUNT,
        "native blank count",
    )
    require_equal(
        Int(manifest["ellipsis_not_shown_count"]),
        APPROVED_ELLIPSIS_COUNT,
        "ellipsis count",
    )
    require_equal(
        manifest["fixture_sha256"],
        APPROVED_FIXTURE_SHA256,
        "fixture pin",
    )
    require_equal(
        manifest["source_zip_sha256"],
        APPROVED_SOURCE_ZIP_SHA256,
        "source ZIP pin",
    )
    require_equal(
        manifest["source_metadata_sha256"],
        APPROVED_SOURCE_METADATA_SHA256,
        "source metadata pin",
    )
    require_equal(
        manifest["detail_use_workbook_sha256"],
        APPROVED_DETAIL_USE_SHA256,
        "detail-use workbook pin",
    )
    require_equal(
        manifest["summary_use_workbook_sha256"],
        APPROVED_SUMMARY_USE_SHA256,
        "summary-use workbook pin",
    )
    require_equal(
        manifest["detail_make_workbook_sha256"],
        APPROVED_DETAIL_MAKE_SHA256,
        "detail-make workbook pin",
    )
    require_equal(
        manifest["summary_make_workbook_sha256"],
        APPROVED_SUMMARY_MAKE_SHA256,
        "summary-make workbook pin",
    )
    require_equal(
        manifest["openpyxl_fallback_sha256"],
        APPROVED_FALLBACK_SHA256,
        "fallback extractor pin",
    )
    require_equal(
        manifest["generator_sha256"],
        APPROVED_GENERATOR_SHA256,
        "generator pin",
    )
    require_equal(
        manifest["generator_member"],
        basename(GENERATOR_PATH),
        "generator member",
    )
    require_equal(
        manifest["source_metadata_member"],
        SOURCE_METADATA_MEMBER,
        "source metadata member",
    )
    require_equal(
        manifest["component_crosswalk_member"],
        COMPONENT_CROSSWALK_MEMBER,
        "component crosswalk member",
    )
    require_equal(
        manifest["component_crosswalk_sha256"],
        APPROVED_COMPONENT_CROSSWALK_SHA256,
        "component crosswalk pin",
    )
    require_equal(
        manifest["component_crosswalk_source_sha256"],
        APPROVED_COMPONENT_CROSSWALK_SOURCE_SHA256,
        "component crosswalk source pin",
    )
    require_equal(
        Int(manifest["component_crosswalk_source_byte_count"]),
        219_021,
        "component crosswalk source byte count",
    )
    require_equal(
        Int(manifest["component_crosswalk_source_pdf_index"]),
        14,
        "component crosswalk PDF index",
    )
    require_equal(
        Int(manifest["component_crosswalk_source_printed_page"]),
        15,
        "component crosswalk printed page",
    )
    require_equal(
        String.(manifest["accepted_reader_contracts"]),
        ["openpyxl=3.1.5", "artifact_tool=2.8.39"],
        "accepted reader contracts",
    )
    require_equal(
        String.(manifest["dual_reader_receipt_members"]),
        [OPENPYXL_RECEIPT_MEMBER, ARTIFACT_TOOL_RECEIPT_MEMBER],
        "dual-reader receipt members",
    )
    require_equal(
        String.(manifest["detail_component_codes"]),
        EXPECTED_DETAIL_CODES,
        "detail component codes",
    )
    require_equal(
        String.(manifest["summary_account_codes"]),
        EXPECTED_SUMMARY_CODES,
        "summary account codes",
    )
    require_equal(
        String.(manifest["final_use_codes"]),
        EXPECTED_FINAL_USE_CODES,
        "final-use codes",
    )
    require_equal(
        String.(manifest["summary_industry_codes"]),
        EXPECTED_SUMMARY_INDUSTRY_CODES,
        "summary industry codes",
    )
    require_equal(
        manifest["reconstruction_scope"],
        "CODE_KEYED_FINAL_USE_AND_AGGREGATE_CONTROLS_ONLY",
        "reconstruction scope",
    )
    require_equal(
        manifest["used_definition"],
        "Used=S00401+S00402",
        "Used definition",
    )
    require_equal(
        manifest["other_definition"],
        "Other=S00300+S00900",
        "Other definition",
    )
    manifest["component_crosswalk_pinned"] === true ||
        throw(ArgumentError("component crosswalk must remain pinned"))
    require_equal(
        manifest["accounting_gate_effect"],
        "NONE",
        "accounting-gate effect",
    )
    isempty(manifest["emitted_runtime_keys"]) ||
        throw(ArgumentError("fixture emits runtime keys"))
    for key in (
            "detail_to_summary_industry_crosswalk_pinned",
            "intermediate_cellwise_reconstruction_claimed",
            "make_cellwise_reconstruction_claimed",
            "runtime_materialization_selected",
            "producer_agent_inference",
            "government_producer_inference",
            "zero_cash_inference",
            "current_vintage_weight_inference",
            "forecast_origin_admissible",
            "model_state_write",
            "calibration_dictionary_write",
        )
        manifest[key] === false ||
            throw(ArgumentError("$key must remain false"))
    end

    manifest_projections = manifest["projection"]
    length(manifest_projections) == length(PROJECTION_SPECS) ||
        throw(ArgumentError("projection count changed"))
    for (metadata, expected) in zip(manifest_projections, PROJECTION_SPECS)
        require_equal(
            metadata["projection_id"],
            expected.id,
            "$(expected.id) projection id",
        )
        require_equal(
            metadata["source_level"],
            expected.source_level,
            "$(expected.id) source level",
        )
        require_equal(
            metadata["source_table"],
            expected.source_table,
            "$(expected.id) source table",
        )
        require_equal(
            metadata["source_member"],
            expected.source_member,
            "$(expected.id) source member",
        )
        require_equal(
            Int(metadata["row_count"]),
            expected.rows,
            "$(expected.id) row count",
        )
        require_equal(
            Int(metadata["column_count"]),
            expected.columns,
            "$(expected.id) column count",
        )
        require_equal(
            Int(metadata["cell_count"]),
            expected.rows * expected.columns,
            "$(expected.id) cell count",
        )
        isempty(metadata["source_ranges"]) &&
            throw(ArgumentError("$(expected.id) source ranges are empty"))
        length(metadata["projection_sha256"]) == 64 ||
            throw(ArgumentError("$(expected.id) projection pin is malformed"))
    end
    return nothing
end

function materialize_projection(rows, expected)
    selected = filter(row -> String(row.projection_id) == expected.id, rows)
    length(selected) == expected.rows * expected.columns ||
        throw(ArgumentError("$(expected.id) cell count changed"))

    row_codes = fill("", expected.rows)
    row_descriptions = fill("", expected.rows)
    row_roles = fill(:unknown, expected.rows)
    row_summary_codes = fill("", expected.rows)
    column_codes = fill("", expected.columns)
    column_descriptions = fill("", expected.columns)
    column_roles = fill(:unknown, expected.columns)
    column_summary_codes = fill("", expected.columns)
    source_addresses = fill("", expected.rows, expected.columns)
    values = zeros(Float64, expected.rows, expected.columns)
    numeric_mask = falses(expected.rows, expected.columns)
    blank_mask = falses(expected.rows, expected.columns)
    ellipsis_mask = falses(expected.rows, expected.columns)
    selected_zero_mask = falses(expected.rows, expected.columns)
    seen = falses(expected.rows, expected.columns)

    for row in selected
        Int(row.year) == 2017 ||
            throw(ArgumentError("$(expected.id) includes a non-2017 cell"))
        String(row.source_level) == expected.source_level ||
            throw(ArgumentError("$(expected.id) source level changed"))
        String(row.source_table) == expected.source_table ||
            throw(ArgumentError("$(expected.id) source table changed"))
        String(row.source_workbook_member) == expected.source_member ||
            throw(ArgumentError("$(expected.id) source member changed"))
        String(row.source_sheet) == "2017" ||
            throw(ArgumentError("$(expected.id) source sheet changed"))

        i = Int(row.row_position)
        j = Int(row.column_position)
        1 <= i <= expected.rows ||
            throw(ArgumentError("$(expected.id) row position is invalid"))
        1 <= j <= expected.columns ||
            throw(ArgumentError("$(expected.id) column position is invalid"))
        !seen[i, j] ||
            throw(ArgumentError("$(expected.id) has a duplicate cell"))
        seen[i, j] = true

        row_code = String(row.row_code)
        row_description = String(row.row_description)
        row_role = Symbol(String(row.row_role))
        row_summary_code = String(row.row_summary_industry_code)
        column_code = String(row.column_code)
        column_description = String(row.column_description)
        column_role = Symbol(String(row.column_role))
        column_summary_code = String(row.column_summary_industry_code)
        if j == 1
            row_codes[i] = row_code
            row_descriptions[i] = row_description
            row_roles[i] = row_role
            row_summary_codes[i] = row_summary_code
        else
            (
                row_codes[i],
                row_descriptions[i],
                row_roles[i],
                row_summary_codes[i],
            ) == (
                row_code,
                row_description,
                row_role,
                row_summary_code,
            ) || throw(ArgumentError("$(expected.id) row metadata changed"))
        end
        if i == 1
            column_codes[j] = column_code
            column_descriptions[j] = column_description
            column_roles[j] = column_role
            column_summary_codes[j] = column_summary_code
        else
            (
                column_codes[j],
                column_descriptions[j],
                column_roles[j],
                column_summary_codes[j],
            ) == (
                column_code,
                column_description,
                column_role,
                column_summary_code,
            ) || throw(
                ArgumentError("$(expected.id) column metadata changed"),
            )
        end

        source_addresses[i, j] = String(row.source_address)
        values[i, j] = Float64(row.value)
        source_kind = String(row.source_cell_kind)
        source_kind in ("numeric", "blank", "ellipsis") ||
            throw(ArgumentError("$(expected.id) source-cell kind changed"))
        numeric_mask[i, j] = source_kind == "numeric"
        blank_mask[i, j] = source_kind == "blank"
        ellipsis_mask[i, j] = source_kind == "ellipsis"
        selected_zero_mask[i, j] =
            blank_mask[i, j] || ellipsis_mask[i, j]
        selected_zero_mask[i, j] && values[i, j] != 0.0 &&
            throw(
            ArgumentError(
                "$(expected.id) selected-zero cell is nonzero",
            ),
        )
    end
    all(seen) || throw(ArgumentError("$(expected.id) has missing cells"))
    length(unique(vec(source_addresses))) == length(source_addresses) ||
        throw(ArgumentError("$(expected.id) source addresses are not unique"))
    all(
        numeric_mask .+ blank_mask .+ ellipsis_mask .== 1,
    ) || throw(
        ArgumentError(
            "$(expected.id) native cell-kind masks are not disjoint and exhaustive",
        ),
    )
    selected_zero_mask == (blank_mask .| ellipsis_mask) ||
        throw(ArgumentError("$(expected.id) selected-zero derivation changed"))

    return MaskedSourceMatrix(
        expected.id,
        2017,
        Symbol(expected.source_level),
        Symbol(expected.source_table),
        expected.source_member,
        row_codes,
        row_descriptions,
        row_roles,
        row_summary_codes,
        column_codes,
        column_descriptions,
        column_roles,
        column_summary_codes,
        source_addresses,
        values,
        numeric_mask,
        blank_mask,
        ellipsis_mask,
        selected_zero_mask,
    )
end

"""
    load_after_redefinitions_2017_special_accounts([directory])

Load the exact 2017 evidence fixture. The loader rejects any changed byte,
vintage, source pin, axis, cell address, sign, or explicit-zero mask.
"""
function load_after_redefinitions_2017_special_accounts(
        directory::AbstractString = DEFAULT_FIXTURE_DIRECTORY,
    )
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "cells.csv")
    sha256_hex(read(GENERATOR_PATH)) == APPROVED_GENERATOR_SHA256 ||
        throw(ArgumentError("2017 special-account generator SHA-256 changed"))
    for (member, expected_sha256, label) in (
            (
                SOURCE_METADATA_MEMBER,
                APPROVED_SOURCE_METADATA_SHA256,
                "source metadata receipt",
            ),
            (
                COMPONENT_CROSSWALK_MEMBER,
                APPROVED_COMPONENT_CROSSWALK_SHA256,
                "component crosswalk",
            ),
            (
                OPENPYXL_RECEIPT_MEMBER,
                APPROVED_OPENPYXL_RECEIPT_SHA256,
                "openpyxl generation receipt",
            ),
            (
                ARTIFACT_TOOL_RECEIPT_MEMBER,
                APPROVED_ARTIFACT_TOOL_RECEIPT_SHA256,
                "artifact-tool generation receipt",
            ),
        )
        companion_path = joinpath(directory, member)
        isfile(companion_path) ||
            throw(ArgumentError("missing 2017 special-account $label"))
        sha256_hex(read(companion_path)) == expected_sha256 ||
            throw(ArgumentError("2017 special-account $label SHA-256 changed"))
    end
    manifest_bytes = read(manifest_path)
    sha256_hex(manifest_bytes) == APPROVED_MANIFEST_SHA256 ||
        throw(ArgumentError("unexpected 2017 special-account manifest SHA-256"))
    manifest = TOML.parse(String(manifest_bytes))
    validate_manifest(manifest)
    sha256_hex(read(cells_path)) == APPROVED_FIXTURE_SHA256 ||
        throw(ArgumentError("2017 special-account fixture SHA-256 changed"))

    table = CSV.File(
        cells_path;
        missingstring = nothing,
        types = Dict(
            :projection_id => String,
            :year => Int,
            :source_level => String,
            :source_table => String,
            :source_workbook_member => String,
            :source_sheet => String,
            :source_address => String,
            :row_position => Int,
            :row_code => String,
            :row_description => String,
            :row_role => String,
            :row_summary_industry_code => String,
            :column_position => Int,
            :column_code => String,
            :column_description => String,
            :column_role => String,
            :column_summary_industry_code => String,
            :value => Float64,
            :source_cell_kind => String,
        ),
    )
    String.(propertynames(table)) == FIXTURE_COLUMNS ||
        throw(ArgumentError("unexpected 2017 special-account fixture columns"))
    rows = collect(table)
    length(rows) == APPROVED_FIXTURE_CELL_COUNT ||
        throw(ArgumentError("2017 special-account fixture cell count changed"))
    count(row -> String(row.source_cell_kind) == "numeric", rows) ==
        APPROVED_NUMERIC_CELL_COUNT ||
        throw(ArgumentError("numeric source-cell count changed"))
    count(
        row ->
        String(row.source_cell_kind) in ("blank", "ellipsis"),
        rows,
    ) == APPROVED_SELECTED_ZERO_COUNT ||
        throw(ArgumentError("selected-zero source-cell count changed"))
    count(row -> String(row.source_cell_kind) == "blank", rows) ==
        APPROVED_NATIVE_BLANK_COUNT ||
        throw(ArgumentError("native blank source-cell count changed"))
    count(row -> String(row.source_cell_kind) == "ellipsis", rows) ==
        APPROVED_ELLIPSIS_COUNT ||
        throw(ArgumentError("ellipsis source-cell count changed"))
    count(
        row ->
        String(row.source_cell_kind) == "numeric" &&
            Float64(row.value) == 0.0,
        rows,
    ) == APPROVED_EXPLICIT_NUMERIC_ZERO_COUNT ||
        throw(ArgumentError("explicit numeric-zero count changed"))
    count(row -> Float64(row.value) < 0.0, rows) ==
        APPROVED_NEGATIVE_CELL_COUNT ||
        throw(ArgumentError("negative-cell count changed"))

    projections = Dict{String, MaskedSourceMatrix}()
    cursor = 1
    for expected in PROJECTION_SPECS
        cell_count = expected.rows * expected.columns
        stop = cursor + cell_count - 1
        stop <= length(rows) ||
            throw(ArgumentError("projection order is truncated"))
        all(
            row -> String(row.projection_id) == expected.id,
            @view(rows[cursor:stop]),
        ) || throw(ArgumentError("projection order changed"))
        projections[expected.id] = materialize_projection(rows, expected)
        cursor = stop + 1
    end
    cursor == length(rows) + 1 ||
        throw(ArgumentError("unexpected trailing projection rows"))

    provenance = SpecialAccountsProvenance(
        APPROVED_FIXTURE_SHA256,
        APPROVED_MANIFEST_SHA256,
        manifest["source_zip_sha256"],
        manifest["source_metadata_sha256"],
        manifest["detail_use_workbook_sha256"],
        manifest["summary_use_workbook_sha256"],
        manifest["detail_make_workbook_sha256"],
        manifest["summary_make_workbook_sha256"],
        manifest["openpyxl_fallback_sha256"],
        manifest["generator_sha256"],
        manifest["component_crosswalk_sha256"],
        APPROVED_OPENPYXL_RECEIPT_SHA256,
        APPROVED_ARTIFACT_TOOL_RECEIPT_SHA256,
        manifest["classification"],
        manifest["promotion_status"],
    )
    return SpecialAccountsFixture(provenance, projections, manifest)
end

function row_positions(matrix::MaskedSourceMatrix, codes)
    positions = Int[]
    for code in codes
        position = findfirst(==(String(code)), matrix.row_codes)
        position === nothing &&
            throw(ArgumentError("$(matrix.projection_id) lacks row $code"))
        push!(positions, position)
    end
    return positions
end

function canonical_column_codes(matrix::MaskedSourceMatrix)
    return [
        isempty(summary_code) ? code : summary_code for
            (code, summary_code) in
            zip(matrix.column_codes, matrix.column_summary_industry_codes)
    ]
end

function aligned_columns(matrix::MaskedSourceMatrix, codes)
    source_codes = canonical_column_codes(matrix)
    positions = Int[]
    for code in codes
        position = findfirst(==(String(code)), source_codes)
        position === nothing &&
            throw(
            ArgumentError(
                "$(matrix.projection_id) lacks canonical column $code",
            ),
        )
        push!(positions, position)
    end
    return matrix.values[:, positions]
end

function reconstruct_accounts(component_matrix, component_codes, column_codes)
    rows = row_positions(component_matrix, component_codes)
    values = aligned_columns(component_matrix, column_codes)
    used = values[rows[1], :] .+ values[rows[2], :]
    other = values[rows[3], :] .+ values[rows[4], :]
    return vcat(reshape(used, 1, :), reshape(other, 1, :))
end

function observed_accounts(summary_matrix, summary_codes, column_codes)
    rows = row_positions(summary_matrix, summary_codes)
    values = aligned_columns(summary_matrix, column_codes)
    return values[rows, :]
end

function residual_ledger(
        detail_matrix,
        summary_matrix,
        column_codes,
    )
    reconstructed = reconstruct_accounts(
        detail_matrix,
        EXPECTED_DETAIL_CODES,
        column_codes,
    )
    observed = observed_accounts(
        summary_matrix,
        EXPECTED_SUMMARY_CODES,
        column_codes,
    )
    return ResidualLedger(
        copy(EXPECTED_SUMMARY_CODES),
        String.(column_codes),
        reconstructed,
        observed,
        observed - reconstructed,
    )
end

function make_output_ledger(detail_output, summary_output)
    detail_values = aligned_columns(detail_output, EXPECTED_DETAIL_CODES)
    summary_values = aligned_columns(summary_output, EXPECTED_SUMMARY_CODES)
    reconstructed = reshape(
        [
            detail_values[1, 1] + detail_values[1, 2],
            detail_values[1, 3] + detail_values[1, 4],
        ],
        2,
        1,
    )
    observed = reshape(summary_values[1, :], 2, 1)
    return ResidualLedger(
        copy(EXPECTED_SUMMARY_CODES),
        ["T007"],
        reconstructed,
        observed,
        observed - reconstructed,
    )
end

function use_identity_residuals(intermediate, final_use, controls)
    control_values = aligned_columns(controls, ["T001", "T004", "T007"])
    return hcat(
        vec(sum(intermediate.values; dims = 2)) - control_values[:, 1],
        vec(sum(final_use.values; dims = 2)) - control_values[:, 2],
        control_values[:, 1] + control_values[:, 2] -
            control_values[:, 3],
    )
end

function make_identity_residuals(make_matrix, output_matrix)
    output_values = vec(
        aligned_columns(output_matrix, make_matrix.column_codes)[1, :],
    )
    return vec(sum(make_matrix.values; dims = 1)) - output_values
end

function nonzero_make_placements(matrix::MaskedSourceMatrix)
    placements = SourceMakePlacement[]
    for i in axes(matrix.values, 1), j in axes(matrix.values, 2)
        amount = matrix.values[i, j]
        amount == 0.0 && continue
        push!(
            placements,
            SourceMakePlacement(
                matrix.source_level,
                matrix.row_codes[i],
                matrix.row_descriptions[i],
                matrix.column_codes[j],
                amount,
                matrix.source_addresses[i, j],
            ),
        )
    end
    return placements
end

function build_report(fixture::SpecialAccountsFixture)
    p = fixture.projections
    final_use = residual_ledger(
        p["detail_use_final_2017"],
        p["summary_use_final_2017"],
        EXPECTED_FINAL_USE_CODES,
    )
    use_controls = residual_ledger(
        p["detail_use_controls_2017"],
        p["summary_use_controls_2017"],
        ["T001", "T004", "T007"],
    )
    make_output = make_output_ledger(
        p["detail_make_output_2017"],
        p["summary_make_output_2017"],
    )
    manifest = fixture.manifest
    return SpecialAccountReconstructionReport(
        fixture.provenance,
        final_use,
        use_controls,
        make_output,
        use_identity_residuals(
            p["detail_use_intermediate_2017"],
            p["detail_use_final_2017"],
            p["detail_use_controls_2017"],
        ),
        use_identity_residuals(
            p["summary_use_intermediate_2017"],
            p["summary_use_final_2017"],
            p["summary_use_controls_2017"],
        ),
        make_identity_residuals(
            p["detail_make_components_2017"],
            p["detail_make_output_2017"],
        ),
        make_identity_residuals(
            p["summary_make_components_2017"],
            p["summary_make_output_2017"],
        ),
        nonzero_make_placements(p["detail_make_components_2017"]),
        nonzero_make_placements(p["summary_make_components_2017"]),
        manifest["detail_to_summary_industry_crosswalk_pinned"],
        manifest["component_crosswalk_pinned"],
        manifest["intermediate_cellwise_reconstruction_claimed"],
        manifest["make_cellwise_reconstruction_claimed"],
        manifest["runtime_materialization_selected"],
        manifest["producer_agent_inference"],
        manifest["government_producer_inference"],
        manifest["zero_cash_inference"],
        manifest["current_vintage_weight_inference"],
        manifest["forecast_origin_admissible"],
        manifest["model_state_write"],
        Symbol(lowercase(manifest["accounting_gate_effect"])),
    )
end

"""
    build_after_redefinitions_2017_special_accounts_diagnostic([directory])

Build the vintage-specific final-use/control reconstruction. Independently
preserved intermediate and make cells are not rolled from 402 to 71 industries.
"""
function build_after_redefinitions_2017_special_accounts_diagnostic(
        directory::AbstractString = DEFAULT_FIXTURE_DIRECTORY,
    )
    return build_report(
        load_after_redefinitions_2017_special_accounts(directory),
    )
end

function report_controls_pass(report::SpecialAccountReconstructionReport)
    report.provenance.fixture_sha256 == APPROVED_FIXTURE_SHA256 ||
        return false
    report.provenance.manifest_sha256 == APPROVED_MANIFEST_SHA256 ||
        return false
    report.provenance.generator_sha256 == APPROVED_GENERATOR_SHA256 ||
        return false
    report.provenance.component_crosswalk_sha256 ==
        APPROVED_COMPONENT_CROSSWALK_SHA256 || return false
    report.provenance.openpyxl_generation_receipt_sha256 ==
        APPROVED_OPENPYXL_RECEIPT_SHA256 || return false
    report.provenance.artifact_tool_generation_receipt_sha256 ==
        APPROVED_ARTIFACT_TOOL_RECEIPT_SHA256 || return false
    report.provenance.classification == EXPECTED_CLASSIFICATION ||
        return false
    report.provenance.promotion_status == EXPECTED_PROMOTION_STATUS ||
        return false
    report.component_crosswalk_pinned || return false
    any(
        (
            report.detail_to_summary_industry_crosswalk_pinned,
            report.intermediate_cellwise_reconstruction_claimed,
            report.make_cellwise_reconstruction_claimed,
            report.runtime_materialization_selected,
            report.producer_agent_inference,
            report.government_producer_inference,
            report.zero_cash_inference,
            report.current_vintage_weight_inference,
            report.forecast_origin_admissible,
            report.model_state_write,
        ),
    ) && return false
    report.accounting_gate_effect == :none || return false
    report.detail_use_row_identity_residuals ==
        EXPECTED_DETAIL_USE_ROW_IDENTITY_RESIDUALS || return false
    report.summary_use_row_identity_residuals ==
        EXPECTED_SUMMARY_USE_ROW_IDENTITY_RESIDUALS || return false
    report.detail_make_identity_residuals ==
        EXPECTED_DETAIL_MAKE_IDENTITY_RESIDUALS || return false
    report.summary_make_identity_residuals ==
        EXPECTED_SUMMARY_MAKE_IDENTITY_RESIDUALS || return false
    all(iszero, report.use_controls.residuals) || return false
    all(iszero, report.make_output.residuals) || return false
    for (i, account_code) in enumerate(report.final_use.account_codes)
        for (j, column_code) in enumerate(report.final_use.column_codes)
            expected = get(
                EXPECTED_FINAL_RESIDUALS,
                (account_code, column_code),
                0.0,
            )
            report.final_use.residuals[i, j] == expected || return false
            abs(report.final_use.residuals[i, j]) <= 1.5 || return false
        end
    end

    detail_s009 = filter(
        placement ->
        placement.account_code == "S00900" &&
            placement.amount != 0.0,
        report.detail_make_placements,
    )
    length(detail_s009) == 1 || return false
    only(detail_s009) == SourceMakePlacement(
        :detail,
        "S00600",
        "Federal general government (nondefense)",
        "S00900",
        3_468.0,
        "ON399",
    ) || return false
    detail_zero_accounts = Set(["S00402", "S00300"])
    any(
        placement -> placement.account_code in detail_zero_accounts,
        report.detail_make_placements,
    ) && return false
    summary_other = filter(
        placement -> placement.account_code == "Other",
        report.summary_make_placements,
    )
    length(summary_other) == 1 || return false
    only(summary_other) == SourceMakePlacement(
        :summary,
        "GFGN",
        "Federal general government (nondefense)",
        "Other",
        3_468.0,
        "BW75",
    ) || return false
    return true
end

"""
    after_redefinitions_2017_special_accounts_controls_pass([directory])

Re-read the byte-pinned source fixture and evaluate the narrow controls. This
is deliberately path/source-aware; there is no public report-only acceptance
gate.
"""
function after_redefinitions_2017_special_accounts_controls_pass(
        directory::AbstractString = DEFAULT_FIXTURE_DIRECTORY,
    )
    try
        return report_controls_pass(
            build_after_redefinitions_2017_special_accounts_diagnostic(
                directory,
            ),
        )
    catch
        return false
    end
end

"""Fail closed: this evidence artifact cannot emit model or forecast state."""
function materialize_after_redefinitions_2017_special_accounts_model_state(
        args...;
        kwargs...,
    )
    throw(
        ArgumentError(
            "2017 special-account evidence is non-runtime, " *
                "not origin-eligible, and has no materializer",
        ),
    )
end

end
