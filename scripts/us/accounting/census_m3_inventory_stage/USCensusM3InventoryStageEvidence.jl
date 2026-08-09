module USCensusM3InventoryStageEvidence

using CSV
using SHA
using TOML

export SourceCellState,
    SOURCE_MISSING,
    SOURCE_EXPLICIT_ZERO,
    SOURCE_OBSERVED_NONZERO,
    M3InventorySeriesRow,
    M3InventoryIdentityCheck,
    M3InventoryStageEvidence,
    APPROVED_CONTRACT_SHA256,
    decode_series_id,
    load_m3_inventory_stage_evidence,
    normalized_module_sha256,
    request_model_bridge,
    source_cell_state,
    validate_m3_inventory_stage_evidence

@enum SourceCellState begin
    SOURCE_MISSING
    SOURCE_EXPLICIT_ZERO
    SOURCE_OBSERVED_NONZERO
end

const CONTRACT_SCHEMA =
    "beforeit-us-census-m3-inventory-stage-evidence-contract.v1"
const FIXTURE_SCHEMA =
    "beforeit-us-census-m3-inventory-stage-fixture.v1"
const EXPECTED_CLASSIFICATION =
    "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const APPROVED_CONTRACT_SHA256 =
    "21cf991d9caa74c793fac50a07a61ec4368b41f99714bbc6c96d2bf824db949e"
const APPROVED_ACQUIRER_SHA256 =
    "fa85479e8aba7a0125ce86079044d2dfbd40ac7cc47fcf5acfd7c5506e7508ab"
const APPROVED_GENERATOR_SHA256 =
    "94bd7a3287893816e588e61e8859b4b008e8f4f07343c3b69c38877e1119048c"
const APPROVED_RAW_WORKBOOK_SHA256 =
    "74ee0d3b9d4a9673a39f1f4ece28206dcccca6451f48aee63506c61675373538"
const APPROVED_SOURCE_RECEIPT_SHA256 =
    "8bee49047f315bfedbde66eb3f9ccccd7526726e13c3e0b6857da6a2947cb600"
const APPROVED_SERIES_ROWS_SHA256 =
    "7b0ab1879460afac35b7a84b7cc8d31be7c876e3f825f1fb141c1e94d242facf"
const APPROVED_IDENTITY_CHECKS_SHA256 =
    "9dcea66c61c18e5ce7eac620dcafeb300d7e97c5c6b6089e8696191a461ed932"
const APPROVED_FIXTURE_MANIFEST_SHA256 =
    "f9033f44947b1e13c4487886fe841fd1cc054535ef7067590c5e60897dd343d2"
const APPROVED_PROJECT_SHA256 =
    "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
const APPROVED_JULIA_MANIFEST_SHA256 =
    "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
const MODULE_HASH_POLICY =
    "SHA256_AFTER_REPLACING_SINGLE_APPROVED_CONTRACT_HASH_LITERAL_WITH_64_ZEROES"

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "census_m3_inventory_stage_evidence.toml")
const MONTH_NAMES =
    (:jan, :feb, :mar, :apr, :may, :jun, :jul, :aug, :sep, :oct, :nov, :dec)
const ITEM_CODES = Set(["TI", "MI", "WI", "FI"])
const EXPECTED_ARTIFACT_HASHES = Dict(
    "acquirer" => APPROVED_ACQUIRER_SHA256,
    "generator" => APPROVED_GENERATOR_SHA256,
    "raw_workbook" => APPROVED_RAW_WORKBOOK_SHA256,
    "source_receipt" => APPROVED_SOURCE_RECEIPT_SHA256,
    "series_rows" => APPROVED_SERIES_ROWS_SHA256,
    "identity_checks" => APPROVED_IDENTITY_CHECKS_SHA256,
    "fixture_manifest" => APPROVED_FIXTURE_MANIFEST_SHA256,
    "project" => APPROVED_PROJECT_SHA256,
    "julia_manifest" => APPROVED_JULIA_MANIFEST_SHA256,
)
const EXPECTED_CITATION_URLS = Dict(
    "historical_documentation_url" =>
        "https://www.census.gov/manufacturing/m3/historical_data/naicshist.pdf",
    "time_series_url" =>
        "https://www.census.gov/manufacturing/m3/historical/timeseries.html",
    "methodology_url" =>
        "https://www.census.gov/manufacturing/m3/how_the_data_are_collected/index.html",
    "definitions_url" =>
        "https://www.census.gov/manufacturing/m3/definitions/index.html",
    "about_url" =>
        "https://www.census.gov/manufacturing/m3/about_the_surveys/index.html",
)

struct M3InventorySeriesRow
    source_row::Int
    series_id::String
    seasonal_adjustment_code::String
    m3_series_code::String
    item_code::String
    year::Int
    values::NTuple{12, Union{Missing, Int64}}
end

struct M3InventoryIdentityCheck
    check_id::String
    seasonal_adjustment_code::String
    m3_series_code::String
    reference_period::String
    total_series_id::String
    materials_series_id::String
    work_in_process_series_id::String
    finished_goods_series_id::String
    total_millions::Union{Missing, Int64}
    materials_millions::Union{Missing, Int64}
    work_in_process_millions::Union{Missing, Int64}
    finished_goods_millions::Union{Missing, Int64}
    residual_millions::Union{Missing, Int64}
    status::Symbol
end

struct M3InventoryStageEvidence
    contract::Dict{String, Any}
    fixture_manifest::Dict{String, Any}
    series_rows::Vector{M3InventorySeriesRow}
    identity_checks::Vector{M3InventoryIdentityCheck}
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
file_sha256(path) = sha256_hex(read(path))

function normalized_module_sha256(path::AbstractString)
    source = read(path, String)
    count = length(findall(APPROVED_CONTRACT_SHA256, source))
    count == 1 ||
        throw(
        ArgumentError(
            "expected one approved-contract hash literal in module, found $count",
        ),
    )
    normalized = replace(
        source,
        APPROVED_CONTRACT_SHA256 => repeat("0", 64);
        count = 1,
    )
    return sha256_hex(codeunits(normalized))
end

function source_cell_state(value::Union{Missing, Integer})
    ismissing(value) && return SOURCE_MISSING
    iszero(value) && return SOURCE_EXPLICIT_ZERO
    return SOURCE_OBSERVED_NONZERO
end

function decode_series_id(series_id::AbstractString)
    matched = match(r"^([AU])([A-Z0-9]{3})(TI|MI|WI|FI)$", series_id)
    matched === nothing &&
        throw(ArgumentError("unknown M3 inventory series code $series_id"))
    return (
        seasonal_adjustment_code = matched.captures[1],
        m3_series_code = matched.captures[2],
        item_code = matched.captures[3],
    )
end

function required_integer(value, field::AbstractString)
    value isa Integer ||
        throw(ArgumentError("$field must be an integer, got $(repr(value))"))
    return Int(value)
end

function nullable_integer(value, field::AbstractString)
    ismissing(value) && return missing
    value isa Integer ||
        throw(
        ArgumentError(
            "$field must be an integer or source-missing, got $(repr(value))",
        ),
    )
    return Int64(value)
end

function artifact_paths(contract::Dict{String, Any})
    specifications = get(contract, "artifact", nothing)
    specifications isa Vector ||
        throw(ArgumentError("contract must contain [[artifact]] entries"))
    paths = Dict{String, String}()
    hashes = Dict{String, String}()
    for specification in specifications
        Set(keys(specification)) ==
            Set(["artifact_id", "path", "sha256", "role"]) ||
            throw(ArgumentError("artifact entry has unexpected keys"))
        identifier = String(specification["artifact_id"])
        haskey(paths, identifier) &&
            throw(ArgumentError("duplicate artifact id $identifier"))
        paths[identifier] =
            normpath(joinpath(REPOSITORY_ROOT, String(specification["path"])))
        hashes[identifier] = String(specification["sha256"])
    end
    Set(keys(paths)) == Set(keys(EXPECTED_ARTIFACT_HASHES)) ||
        throw(ArgumentError("contract artifact identifier set mismatch"))
    for identifier in keys(paths)
        hashes[identifier] == EXPECTED_ARTIFACT_HASHES[identifier] ||
            throw(ArgumentError("contract hash mismatch for $identifier"))
        isfile(paths[identifier]) ||
            throw(ArgumentError("artifact is not a file: $(paths[identifier])"))
        file_sha256(paths[identifier]) == hashes[identifier] ||
            throw(ArgumentError("artifact byte hash mismatch for $identifier"))
    end
    return paths
end

function read_series_rows(path::AbstractString)
    output = M3InventorySeriesRow[]
    for record in CSV.File(path; missingstring = "")
        values = ntuple(
            index -> nullable_integer(
                getproperty(record, MONTH_NAMES[index]),
                "$(record.series_id).$(MONTH_NAMES[index])",
            ),
            12,
        )
        push!(
            output,
            M3InventorySeriesRow(
                required_integer(record.source_row, "source_row"),
                String(record.series_id),
                String(record.seasonal_adjustment_code),
                String(record.m3_series_code),
                String(record.item_code),
                required_integer(record.year, "year"),
                values,
            ),
        )
    end
    return output
end

function read_identity_checks(path::AbstractString)
    output = M3InventoryIdentityCheck[]
    for record in CSV.File(
            path;
            missingstring = "",
            types = Dict(:reference_period => String),
        )
        push!(
            output,
            M3InventoryIdentityCheck(
                String(record.check_id),
                String(record.seasonal_adjustment_code),
                String(record.m3_series_code),
                string(record.reference_period),
                String(record.total_series_id),
                String(record.materials_series_id),
                String(record.work_in_process_series_id),
                String(record.finished_goods_series_id),
                nullable_integer(record.total_millions, "total_millions"),
                nullable_integer(
                    record.materials_millions,
                    "materials_millions",
                ),
                nullable_integer(
                    record.work_in_process_millions,
                    "work_in_process_millions",
                ),
                nullable_integer(
                    record.finished_goods_millions,
                    "finished_goods_millions",
                ),
                nullable_integer(
                    record.residual_millions,
                    "residual_millions",
                ),
                Symbol(record.status),
            ),
        )
    end
    return output
end

function expected_integer(
        contract::Dict{String, Any},
        key::AbstractString,
    )
    expected = contract["expected"]
    haskey(expected, key) ||
        throw(ArgumentError("contract is missing expected.$key"))
    return required_integer(expected[key], "expected.$key")
end

function validate_contract(
        contract::Dict{String, Any},
        fixture_manifest::Dict{String, Any},
    )
    contract["schema_version"] == CONTRACT_SCHEMA ||
        throw(ArgumentError("contract schema mismatch"))
    contract["classification"] == EXPECTED_CLASSIFICATION ||
        throw(ArgumentError("contract classification mismatch"))
    contract["promotion_status"] == "RESEARCH_ONLY_NOT_PROMOTED" ||
        throw(ArgumentError("contract promotion status mismatch"))
    contract["forecast_origin_admissible"] === false ||
        throw(ArgumentError("contract cannot be forecast-origin admissible"))
    contract["economy_wide_scope_claimed"] === false ||
        throw(ArgumentError("contract cannot claim economy-wide scope"))
    for key in (
            "bea_allocation_applied",
            "commodity_holder_crosswalk_applied",
            "transition_emitted",
            "model_inventory_vector_emitted",
            "model_state_write",
        )
        contract[key] === false ||
            throw(ArgumentError("contract must keep $key false"))
    end
    contract["accounting_gate_effect"] == "NONE" ||
        throw(ArgumentError("contract accounting gate effect must be NONE"))
    contract["forecast_score_effect"] == "NONE" ||
        throw(ArgumentError("contract forecast score effect must be NONE"))

    implementation = contract["implementation"]
    implementation["module_hash_policy"] == MODULE_HASH_POLICY ||
        throw(ArgumentError("module hash policy mismatch"))
    implementation["module_normalized_sha256"] ==
        normalized_module_sha256(joinpath(@__DIR__, basename(@__FILE__))) ||
        throw(ArgumentError("module normalized hash mismatch"))

    semantics = contract["source_semantics"]
    semantics["scope"] == "DOMESTIC_MANUFACTURING_M3_SURVEY_ONLY" ||
        throw(ArgumentError("source scope mismatch"))
    semantics["time_basis"] == "END_OF_MONTH_STOCK_LEVEL" ||
        throw(ArgumentError("source time basis mismatch"))
    semantics["adjusted_code"] == "A" ||
        throw(ArgumentError("adjusted series code mismatch"))
    semantics["unadjusted_code"] == "U" ||
        throw(ArgumentError("unadjusted series code mismatch"))
    semantics["total_code"] == "TI" ||
        throw(ArgumentError("total series code mismatch"))
    semantics["materials_code"] == "MI" ||
        throw(ArgumentError("materials series code mismatch"))
    semantics["work_in_process_code"] == "WI" ||
        throw(ArgumentError("work-in-process series code mismatch"))
    semantics["finished_goods_code"] == "FI" ||
        throw(ArgumentError("finished-goods series code mismatch"))
    semantics["missing_value_policy"] ==
        "ABSENT_CELL_IS_SOURCE_MISSING_NOT_ZERO" ||
        throw(ArgumentError("source missing-value policy mismatch"))
    semantics["zero_policy"] ==
        "NUMERIC_ZERO_IS_EXPLICIT_ZERO_DISTINCT_FROM_MISSING" ||
        throw(ArgumentError("source zero policy mismatch"))
    occursin("NO_PSEUDO_VINTAGE", semantics["revision_policy"]) ||
        throw(ArgumentError("source revision policy is not fail closed"))

    method = contract["source_method"]
    method["stage_control_allocation_is_census_method"] === true ||
        throw(ArgumentError("Census stage control allocation is undocumented"))
    method["independent_stage_measurement_claimed"] === false ||
        throw(ArgumentError("stage detail cannot be claimed independent"))
    method["project_allocation_applied"] === false ||
        throw(ArgumentError("project allocation must remain false"))
    occursin("PROPORTIONALLY_ALLOCATED", method["unadjusted_stage_method"]) ||
        throw(ArgumentError("unadjusted source method mismatch"))
    occursin(
        "PROPORTIONALLY_ALLOCATED",
        method["seasonally_adjusted_stage_method"],
    ) || throw(ArgumentError("adjusted source method mismatch"))
    occursin("CANNOT_REPORT_STAGE_DETAIL", method["reason"]) ||
        throw(ArgumentError("source allocation reason mismatch"))

    for (key, expected_url) in EXPECTED_CITATION_URLS
        contract["citations"][key] == expected_url ||
            throw(ArgumentError("official Census citation mismatch for $key"))
    end
    all(values(contract["blocked_boundaries"])) ||
        throw(ArgumentError("every model boundary must remain blocked"))

    fixture_manifest["schema_version"] == FIXTURE_SCHEMA ||
        throw(ArgumentError("fixture schema mismatch"))
    fixture_manifest["classification"] == EXPECTED_CLASSIFICATION ||
        throw(ArgumentError("fixture classification mismatch"))
    fixture_manifest["source_workbook_vintage"] ==
        "CURRENT_MUTABLE_CAPTURE_NOT_IMMUTABLE_RELEASE" ||
        throw(ArgumentError("fixture makes an invalid vintage claim"))
    fixture_manifest["source_revision_status"] ==
        "NOT_ENCODED_PER_CELL_IN_WORKBOOK" ||
        throw(ArgumentError("fixture revision status mismatch"))
    fixture_manifest["forecast_origin_admissible"] === false ||
        throw(ArgumentError("fixture cannot be forecast-origin admissible"))
    fixture_manifest["source_workbook_sha256"] ==
        APPROVED_RAW_WORKBOOK_SHA256 ||
        throw(ArgumentError("fixture raw workbook hash mismatch"))
    fixture_manifest["source_receipt_sha256"] ==
        APPROVED_SOURCE_RECEIPT_SHA256 ||
        throw(ArgumentError("fixture source receipt hash mismatch"))
    fixture_manifest["artifacts"]["series_rows_sha256"] ==
        APPROVED_SERIES_ROWS_SHA256 ||
        throw(ArgumentError("fixture series rows hash mismatch"))
    fixture_manifest["artifacts"]["identity_checks_sha256"] ==
        APPROVED_IDENTITY_CHECKS_SHA256 ||
        throw(ArgumentError("fixture identity checks hash mismatch"))
    return nothing
end

function validate_series_rows(
        rows::Vector{M3InventorySeriesRow},
        contract::Dict{String, Any},
    )
    length(rows) == expected_integer(contract, "source_row_count") ||
        throw(ArgumentError("source row count mismatch"))
    all(row.source_row == index for (index, row) in enumerate(rows)) ||
        throw(ArgumentError("source row order is not exact"))

    identifiers = Set(row.series_id for row in rows)
    length(identifiers) == expected_integer(contract, "source_series_count") ||
        throw(ArgumentError("source series count mismatch"))
    adjustment_counts = Dict(
        code => count(startswith(code), identifiers) for code in ("A", "U")
    )
    adjustment_counts["A"] ==
        expected_integer(contract, "adjusted_series_count") ||
        throw(ArgumentError("adjusted source series count mismatch"))
    adjustment_counts["U"] ==
        expected_integer(contract, "unadjusted_series_count") ||
        throw(ArgumentError("unadjusted source series count mismatch"))
    for (item_code, expected_key) in (
            ("TI", "total_series_count"),
            ("MI", "materials_series_count"),
            ("WI", "work_in_process_series_count"),
            ("FI", "finished_goods_series_count"),
        )
        count(endswith(item_code), identifiers) ==
            expected_integer(contract, expected_key) ||
            throw(ArgumentError("$item_code source series count mismatch"))
    end

    seen = Set{Tuple{String, Int}}()
    numeric_count = 0
    missing_count = 0
    explicit_zero_count = 0
    negative_count = 0
    for row in rows
        decoded = decode_series_id(row.series_id)
        decoded.seasonal_adjustment_code ==
            row.seasonal_adjustment_code ||
            throw(ArgumentError("series adjustment code mismatch"))
        decoded.m3_series_code == row.m3_series_code ||
            throw(ArgumentError("M3 series code mismatch"))
        decoded.item_code == row.item_code ||
            throw(ArgumentError("series item code mismatch"))
        row.item_code in ITEM_CODES ||
            throw(ArgumentError("unknown item code"))
        expected_integer(contract, "year_minimum") <= row.year <=
            expected_integer(contract, "year_maximum") ||
            throw(ArgumentError("source year outside contract"))
        key = (row.series_id, row.year)
        key in seen &&
            throw(ArgumentError("duplicate series-year source row"))
        push!(seen, key)
        for (month, value) in enumerate(row.values)
            expected_missing = row.year == 2026 && month >= 7
            ismissing(value) == expected_missing ||
                throw(
                ArgumentError(
                    "unexpected missing pattern at $(row.series_id) " *
                        "$(row.year)-$(lpad(month, 2, '0'))",
                ),
            )
            if ismissing(value)
                missing_count += 1
            else
                numeric_count += 1
                explicit_zero_count += iszero(value)
                negative_count += value < 0
            end
        end
    end
    length(rows) * 12 == expected_integer(contract, "source_cell_count") ||
        throw(ArgumentError("source cell count mismatch"))
    numeric_count == expected_integer(contract, "numeric_cell_count") ||
        throw(ArgumentError("numeric source cell count mismatch"))
    missing_count == expected_integer(contract, "missing_cell_count") ||
        throw(ArgumentError("source-missing cell count mismatch"))
    explicit_zero_count ==
        expected_integer(contract, "explicit_zero_count") ||
        throw(ArgumentError("explicit-zero source cell count mismatch"))
    negative_count == expected_integer(contract, "negative_count") ||
        throw(ArgumentError("negative source cell count mismatch"))
    return nothing
end

function validate_identity_checks(
        checks::Vector{M3InventoryIdentityCheck},
        rows::Vector{M3InventorySeriesRow},
        contract::Dict{String, Any},
    )
    length(checks) == expected_integer(contract, "identity_check_count") ||
        throw(ArgumentError("identity check count mismatch"))
    lookup = Dict(
        (row.series_id, row.year) => row for row in rows
    )
    check_ids = Set{String}()
    status_counts = Dict{Symbol, Int}()
    stage_sets = Set{Tuple{String, String}}()
    maximum_absolute_residual = 0
    for check in checks
        check.check_id in check_ids &&
            throw(ArgumentError("duplicate identity check id"))
        push!(check_ids, check.check_id)
        status_counts[check.status] =
            get(status_counts, check.status, 0) + 1
        push!(
            stage_sets,
            (check.seasonal_adjustment_code, check.m3_series_code),
        )
        period = match(r"^([0-9]{4})-([0-9]{2})$", check.reference_period)
        period === nothing &&
            throw(ArgumentError("invalid identity reference period"))
        year = parse(Int, period.captures[1])
        month = parse(Int, period.captures[2])
        1 <= month <= 12 ||
            throw(ArgumentError("invalid identity reference month"))
        prefix =
            check.seasonal_adjustment_code * check.m3_series_code
        expected_series_ids = (
            prefix * "TI",
            prefix * "MI",
            prefix * "WI",
            prefix * "FI",
        )
        (
            check.total_series_id,
            check.materials_series_id,
            check.work_in_process_series_id,
            check.finished_goods_series_id,
        ) == expected_series_ids ||
            throw(ArgumentError("identity series code mismatch"))
        source_values = ntuple(
            index -> lookup[(expected_series_ids[index], year)].values[month],
            4,
        )
        check_values = (
            check.total_millions,
            check.materials_millions,
            check.work_in_process_millions,
            check.finished_goods_millions,
        )
        isequal(check_values, source_values) ||
            throw(ArgumentError("identity values do not match source rows"))
        if all(ismissing, source_values)
            check.status == :NOT_RUN_SOURCE_MISSING ||
                throw(ArgumentError("missing identity must not run"))
            ismissing(check.residual_millions) ||
                throw(ArgumentError("missing identity cannot have a residual"))
        elseif any(ismissing, source_values)
            throw(ArgumentError("partial source identity is prohibited"))
        else
            residual =
                source_values[1] -
                source_values[2] -
                source_values[3] -
                source_values[4]
            check.residual_millions == residual ||
                throw(ArgumentError("identity residual mismatch"))
            check.status == :PASS_EXACT_SOURCE_IDENTITY ||
                throw(ArgumentError("observed identity did not pass exactly"))
            iszero(residual) ||
                throw(ArgumentError("published stage identity is not exact"))
            maximum_absolute_residual =
                max(maximum_absolute_residual, abs(residual))
        end
    end
    length(stage_sets) ==
        expected_integer(contract, "stage_identity_set_count") ||
        throw(ArgumentError("stage identity-set count mismatch"))
    get(status_counts, :PASS_EXACT_SOURCE_IDENTITY, 0) ==
        expected_integer(contract, "identity_exact_pass_count") ||
        throw(ArgumentError("identity exact-pass count mismatch"))
    get(status_counts, :NOT_RUN_SOURCE_MISSING, 0) ==
        expected_integer(contract, "identity_source_missing_count") ||
        throw(ArgumentError("identity source-missing count mismatch"))
    sum(values(status_counts)) == length(checks) ||
        throw(ArgumentError("unexpected identity status"))
    maximum_absolute_residual ==
        expected_integer(
        contract,
        "maximum_absolute_identity_residual_millions",
    ) || throw(ArgumentError("maximum identity residual mismatch"))
    return nothing
end

function validate_m3_inventory_stage_evidence(
        evidence::M3InventoryStageEvidence,
    )
    validate_contract(evidence.contract, evidence.fixture_manifest)
    validate_series_rows(evidence.series_rows, evidence.contract)
    validate_identity_checks(
        evidence.identity_checks,
        evidence.series_rows,
        evidence.contract,
    )
    return evidence
end

function load_m3_inventory_stage_evidence(
        contract_path::AbstractString = DEFAULT_CONTRACT_PATH,
    )
    file_sha256(contract_path) == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("Census M3 evidence contract SHA-256 mismatch"))
    contract = TOML.parsefile(contract_path)
    paths = artifact_paths(contract)
    fixture_manifest = TOML.parsefile(paths["fixture_manifest"])
    evidence = M3InventoryStageEvidence(
        contract,
        fixture_manifest,
        read_series_rows(paths["series_rows"]),
        read_identity_checks(paths["identity_checks"]),
    )
    return validate_m3_inventory_stage_evidence(evidence)
end

function request_model_bridge(
        ::M3InventoryStageEvidence,
        operation::Symbol,
    )
    operation in (
        :economy_wide_bea_allocation,
        :commodity_holder_crosswalk,
        :stage_to_model_stock_scope_bridge,
        :stock_flow_transition,
        :current_vintage_to_forecast_origin,
        :model_state_write,
        :accounting_gate,
        :forecast_score,
    ) || throw(ArgumentError("unknown model bridge operation $operation"))
    throw(
        ArgumentError(
            "Census M3 evidence is research-only; $operation is blocked",
        ),
    )
end

end
