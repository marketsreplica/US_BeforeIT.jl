using SHA
using Test
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USCommonOriginPreflightV1.jl")
const MANIFEST_PATH = joinpath(TEST_DIRECTORY, "common_origin_preflight_v1.toml")
const EXPECTED_MODULE_SHA256 =
    "07cd16c8bab750a890e1f1cdd3baa18b7930240fbdaded7afb3fe0d6f3da8e3f"
const EXPECTED_MANIFEST_PHYSICAL_SHA256 =
    "a44f90f1cc809cfcc928e69f0ddc046916554fee9a534ff8d6162a4df6143902"
const EXPECTED_MANIFEST_CONTENT_SHA256 =
    "455ae03d775865eba34e1f1fc84ca0ffe790c79508d89b6cc284d19ce37a175a"
const EXPECTED_RESULT_SHA256 =
    "4b0871cdd9c25fadcd266b778ba23b0415f23ce8e8c423f6ee7fc5d936938fd5"

function exact_regular_bytes(path)
    current = dirname(path)
    while true
        islink(current) && error("symbolic path component: $current")
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    islink(path) && error("symbolic file is forbidden: $path")
    isfile(path) || error("missing regular file: $path")
    status = lstat(path)
    status.nlink == 1 || error("hard-linked file is forbidden: $path")
    before = (
        status.device,
        status.inode,
        status.mode,
        status.nlink,
        status.size,
        status.mtime,
        status.ctime,
    )
    bytes = read(path)
    after_status = lstat(path)
    after = (
        after_status.device,
        after_status.inode,
        after_status.mode,
        after_status.nlink,
        after_status.size,
        after_status.mtime,
        after_status.ctime,
    )
    before == after || error("file changed during read: $path")
    return bytes
end

function loaded_module_names()
    return Set(String(nameof(value)) for value in values(Base.loaded_modules))
end

const FORBIDDEN_MODULES = Set(
    ["BeforeIT", "CSV", "DataFrames", "Downloads", "HTTP", "JLD2", "JSON", "Pkg"],
)
const FORBIDDEN_MODEL_OR_DATA_MODULES =
    Set(["BeforeIT", "CSV", "DataFrames", "HTTP", "JLD2", "JSON"])
const BEFORE_INCLUDE_MODULES = loaded_module_names()
const MODULE_BYTES = exact_regular_bytes(MODULE_PATH)
const MODULE_TEXT = String(copy(MODULE_BYTES))

@testset "stdlib-only preinclude boundary" begin
    @test bytes2hex(SHA.sha256(MODULE_BYTES)) == EXPECTED_MODULE_SHA256
    imports = [
        matched.captures[1] for matched in eachmatch(
                r"(?m)^\s*(?:using|import)\s+([A-Za-z][A-Za-z0-9_.]*)\s*$",
                MODULE_TEXT,
            )
    ]
    @test Set(imports) == Set(["SHA", "TOML"])
    @test isempty(intersect(BEFORE_INCLUDE_MODULES, FORBIDDEN_MODEL_OR_DATA_MODULES))
    @test !occursin(r"\binclude\s*\(", MODULE_TEXT)
    @test !occursin(r"\b(?:eval|invokelatest)\s*\(", MODULE_TEXT)
    @test !occursin(
        r"\b(?:step!|filter_loglikelihood|fit!|forecast|score|download|request)\s*\(",
        MODULE_TEXT,
    )
    @test !occursin(r"\b(?:open|mkpath|mkdir|rm|cp|mv)\s*\(", MODULE_TEXT)
    @test !occursin(r"\b(?:CSV|DataFrames|Downloads|HTTP|JLD2|JSON|Pkg)\.", MODULE_TEXT)
end

include(MODULE_PATH)
const Preflight = USCommonOriginPreflightV1

function expect_preflight_error(code, thunk)
    observed = nothing
    try
        thunk()
    catch error
        observed = error
    end
    @test observed isa Preflight.PreflightError
    observed isa Preflight.PreflightError && @test observed.code == code
    return observed
end

function restamp_result!(document)
    document["artifact"]["content_sha256"] =
        Preflight.result_content_sha256(document)
    return document
end

function restamp_manifest!(document)
    document["artifact"]["content_sha256"] =
        Preflight.manifest_content_sha256(document)
    return document
end

function toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    return take!(io)
end

@testset "post-include boundary remains metadata-only" begin
    after = loaded_module_names()
    @test isempty(intersect(setdiff(after, BEFORE_INCLUDE_MODULES), FORBIDDEN_MODULES))
    @test isempty(intersect(after, FORBIDDEN_MODEL_OR_DATA_MODULES))
    @test Set(names(Preflight; all = false)) == Set(
        [
            :PreflightError,
            :USCommonOriginPreflightV1,
            :compile_preflight,
            :load_manifest,
            :manifest_content_sha256,
            :result_content_sha256,
            :validate_preflight,
        ],
    )
end

@testset "self-hashed and physically pinned manifest" begin
    bytes = exact_regular_bytes(MANIFEST_PATH)
    @test bytes2hex(SHA.sha256(bytes)) == EXPECTED_MANIFEST_PHYSICAL_SHA256
    manifest = Preflight.load_manifest()
    @test manifest["artifact"]["content_sha256"] ==
        EXPECTED_MANIFEST_CONTENT_SHA256
    @test Preflight.manifest_content_sha256(manifest) ==
        EXPECTED_MANIFEST_CONTENT_SHA256
    @test manifest["contract"]["allowed_statuses"] == ["CANNOT_RUN"]
    @test manifest["contract"]["successor_only_status"] ==
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    @test manifest["contract"]["forbidden_status"] == "READY_TO_SCORE"
    @test length(manifest["sources"]) == 36
    @test length(manifest["required_conditions"]) == 21
    @test all(values(manifest["required_conditions"]))

    coordinated = deepcopy(manifest)
    coordinated["contract"]["future_ready_rule"] = "local_boolean_flip"
    restamp_manifest!(coordinated)
    @test Preflight.manifest_content_sha256(coordinated) ==
        coordinated["artifact"]["content_sha256"]
    expect_preflight_error(
        :manifest_physical_hash,
        () -> Preflight._verify_manifest_physical_bytes(toml_bytes(coordinated)),
    )

    repeated_label = deepcopy(manifest)
    repeated_label["sources"][2]["sha256"] =
        repeated_label["sources"][1]["sha256"]
    restamp_manifest!(repeated_label)
    @test repeated_label["artifact"]["content_sha256"] ==
        Preflight.manifest_content_sha256(repeated_label)
    expect_preflight_error(
        :manifest_physical_hash,
        () -> Preflight._verify_manifest_physical_bytes(toml_bytes(repeated_label)),
    )

    elevated = deepcopy(manifest)
    elevated["contract"]["current_expected_status"] =
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    restamp_manifest!(elevated)
    expect_preflight_error(:gate_elevation, () -> Preflight._manifest_payload(elevated))
end

@testset "current exact CANNOT_RUN derivation" begin
    result = Preflight.compile_preflight()
    @test Preflight.validate_preflight(result) === result
    @test result["artifact"]["content_sha256"] == EXPECTED_RESULT_SHA256
    @test Preflight.result_content_sha256(result) == EXPECTED_RESULT_SHA256
    @test result["preflight"]["status"] == "CANNOT_RUN"
    @test result["preflight"]["claim_ceiling"] == "CANNOT_RUN"
    @test result["preflight"]["successor_only_status"] ==
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    @test result["preflight"]["current_v1_ready_status_reachable"] === false
    @test result["preflight"]["source_binding_count"] == 36
    @test result["preflight"]["manifest_physical_sha256"] ==
        EXPECTED_MANIFEST_PHYSICAL_SHA256
    @test result["preflight"]["manifest_physical_sha256"] !=
        bytes2hex(SHA.sha256(UInt8[]))
    @test result["preflight"]["blocking_reason_count"] == 89
    @test result["preflight"]["limitation_count"] == 17
    @test length(result["blocking_reasons"]) == 89
    @test length(result["limitations"]) == 17
    @test length(result["readiness_conditions"]) == 21
    @test all(item -> item["satisfied"] === false, result["readiness_conditions"])
    @test all(
        item -> !isempty(item["blocking_reason_ids"]),
        result["readiness_conditions"],
    )
    @test issorted([item["reason_id"] for item in result["blocking_reasons"]])
    @test issorted([item["reason_id"] for item in result["limitations"]])

    source_ids = Set(item["binding_id"] for item in result["source_bindings"])
    @test length(source_ids) == 36
    @test "core3_revised_fixture_manifest" in source_ids
    @test all(
        item -> !isempty(item["condition_ids"]) &&
            all(in(source_ids), item["source_binding_ids"]),
        result["blocking_reasons"],
    )
    @test all(
        item -> all(in(source_ids), item["source_binding_ids"]),
        result["limitations"],
    )
    blocker_ids = Set(item["reason_id"] for item in result["blocking_reasons"])
    @test all(
        condition -> all(in(blocker_ids), condition["blocking_reason_ids"]),
        result["readiness_conditions"],
    )

    @test all(value -> value === false, values(result["scientific_gates"]))
    @test Set(keys(result["scientific_gates"])) == Set(
        [
            "accuracy_claim_allowed",
            "admission_allowed",
            "production_allowed",
            "promotion_allowed",
            "scoring_allowed",
            "suitability_claim_allowed",
        ],
    )
    @test result["truth_policy_state"] == Dict{String, Any}(
        "truth_policy_metadata_present" => true,
        "truth_policy_metadata_frozen" => false,
        "registered_truth_matrix_count" => 0,
        "preflight_truth_artifact_accessed" => false,
        "ready_to_score_allowed" => false,
    )
    counts = result["preflight_owned_action_counts"]
    @test counts["pinned_files_read"] == 37
    @test counts["metadata_toml_files_parsed"] == 16
    @test all(
        iszero,
        [
            counts["upstream_modules_included"],
            counts["model_constructions"],
            counts["model_steps"],
            counts["model_filters"],
            counts["model_fits"],
            counts["model_forecasts"],
            counts["scores"],
            counts["truth_artifacts_accessed"],
            counts["revised_panel_artifacts_accessed"],
            counts["filesystem_writes"],
            counts["network_requests"],
        ],
    )
end

@testset "exact intersections and semantic boundaries" begin
    result = Preflight.compile_preflight()
    intersections = result["intersections"]
    @test intersections["origin"]["metadata_label_first"] == "2016Q2"
    @test intersections["origin"]["metadata_label_last"] == "2021Q2"
    @test intersections["origin"]["metadata_label_count"] == 21
    @test intersections["origin"]["strict_admitted_origins"] == String[]
    @test intersections["origin"]["abm_origin_period"] == "2026Q1"
    @test intersections["origin"]["core3_fixture_metadata_binding_id"] ==
        "core3_revised_fixture_manifest"
    @test intersections["origin"]["core3_fixture_declared_information_track"] ==
        "revised_mixed_vintage_diagnostic"
    @test intersections["origin"]["core3_fixture_declared_row_count"] == 101
    @test intersections["origin"]["core3_fixture_declared_panel_file"] ==
        "quarterly_panel.csv"
    @test intersections["origin"]["core3_fixture_declared_panel_sha256"] ==
        "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
    @test intersections["origin"]["core3_revised_panel_artifact_accessed"] === false
    @test intersections["origin"]["core3_last_h1_origin"] == "2025Q2"
    @test intersections["origin"]["core3_last_h4_origin"] == "2024Q3"
    @test intersections["origin"]["core3_last_h12_origin"] == "2022Q3"
    @test intersections["origin"]["all_model_common_origins"] == String[]

    @test intersections["target"]["declared_all_model_common_target_ids"] ==
        ["real_gdp"]
    @test intersections["target"]["eligible_all_model_common_target_ids"] ==
        String[]
    @test intersections["target"]["pce_and_gdp_deflator_alias_allowed"] === false
    @test intersections["transform"]["declared_common_transform_ids"] ==
        ["annualized_qoq_log_growth"]
    @test intersections["transform"]["approved_common_transform_ids"] == String[]

    @test intersections["horizon"]["required_protocol_horizons"] ==
        [1, 2, 4, 8, 12]
    @test intersections["horizon"]["nominal_all_model_horizons"] == [1, 2, 4]
    @test intersections["horizon"]["eligible_all_model_horizons"] == Int[]
    @test intersections["horizon"]["abm_h1_basis"] ==
        "model_implied_opening_to_post_step_flow"
    @test intersections["horizon"]["abm_h1_basis_compatible"] === false
    @test intersections["path"]["abm_path_count"] == 32
    @test intersections["path"]["common_convergence_rule_present"] === false

    registration = intersections["registration"]
    @test registration["registered_required_model_ids"] == String[]
    @test registration["mechanics_class_ids_not_executable_model_ids"] ==
        ["small_new_keynesian_dsge"]
    @test length(registration["missing_required_model_ids"]) == 4

    bindings = result["model_target_bindings"]
    @test length(bindings) == 8
    pce = only(
        [
            item for item in bindings if item["model_family_id"] ==
                "core3_autoregressive" && item["source_target_id"] == "pce_inflation"
        ],
    )
    @test pce["official_target_id"] == "pce_price_index"
    @test pce["official_target_id"] != "gdp_deflator"
    effr = only(
        [
            item for item in bindings if item["model_family_id"] ==
                "core3_autoregressive" && item["source_target_id"] ==
                "effective_federal_funds_rate"
        ],
    )
    @test effr["transformation_version"] == "us-effr-quarterly-average.v1-draft"
    @test effr["official_output_unit"] == "percentage_points"
    @test all(item -> item["mapping_status"] == "unapproved", bindings)
end

@testset "required policy rejections and historical disposition" begin
    result = Preflight.compile_preflight()
    policies = Set(result["policy_rejections"])
    @test "REVISED_OR_CURRENT_INFORMATION_TRACK_FORBIDDEN" in policies
    @test "SYNTHETIC_RECEIPT_OR_DERIVATION_FORBIDDEN" in policies
    @test "REPEATED_HASH_LABEL_WITHOUT_EXACT_SOURCE_BINDING_FORBIDDEN" in policies
    @test "HINDSIGHT_STRUCTURAL_SELECTION_FORBIDDEN" in policies
    @test "UNREGISTERED_MODEL_FORBIDDEN" in policies
    @test "MISMATCHED_ORIGIN_TARGET_TRANSFORM_SEMANTICS_FORBIDDEN" in policies
    @test "PCE_INFLATION_TO_GDP_DEFLATOR_ALIAS_FORBIDDEN" in policies
    @test "ABM_H1_OPENING_TO_FLOW_BASIS_BREAK_FORBIDDEN" in policies
    @test "READY_TO_SCORE_FORBIDDEN" in policies
    @test "HISTORICAL_CORE3_EQUILIBRIUM_COMPARISON_REJECTED_NOT_COMMON_ORIGIN_EVIDENCE" in
        policies
    rejected = result["historical_rejected_evidence"]
    @test rejected["core3_equilibrium_comparison_disposition"] ==
        "REJECTED_NOT_COMMON_ORIGIN_EVIDENCE"
    @test rejected["core3_equilibrium_comparison_module_sha256"] ==
        "da3581203ed0ac580a315df172ed5f6a068770c99f1a172c8d8106ccbf2aa728"
    @test rejected["core3_equilibrium_comparison_tests_sha256"] ==
        "956b7011b01e8436aaee261e5767b9b3a73c96ffb42c0b7ffd36f4a841d93bc4"
    @test rejected["core3_equilibrium_comparison_runner_sha256"] ==
        "8fd455c959121ce1391e30b95a6dc2363f0ada25087269205890548f92d881f3"
end

@testset "coordinated result restamps fail evidence replay" begin
    baseline = Preflight.compile_preflight()

    ready = deepcopy(baseline)
    ready["preflight"]["status"] =
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    ready["preflight"]["claim_ceiling"] =
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    ready["preflight"]["current_v1_ready_status_reachable"] = true
    ready["blocking_reasons"] = Dict{String, Any}[]
    ready["preflight"]["blocking_reason_count"] = 0
    for condition in ready["readiness_conditions"]
        condition["satisfied"] = true
        condition["blocking_reason_ids"] = String[]
    end
    restamp_result!(ready)
    expect_preflight_error(:invalid_status, () -> Preflight.validate_preflight(ready))

    gate = deepcopy(baseline)
    gate["scientific_gates"]["accuracy_claim_allowed"] = true
    restamp_result!(gate)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(gate))

    source = deepcopy(baseline)
    source["source_bindings"][2]["physical_sha256"] =
        source["source_bindings"][1]["physical_sha256"]
    restamp_result!(source)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(source))

    mapping = deepcopy(baseline)
    pce_index = findfirst(
        item -> item["model_family_id"] == "core3_autoregressive" &&
            item["source_target_id"] == "pce_inflation",
        mapping["model_target_bindings"],
    )
    mapping["model_target_bindings"][pce_index]["official_target_id"] = "gdp_deflator"
    restamp_result!(mapping)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(mapping))

    blocker = deepcopy(baseline)
    pop!(blocker["blocking_reasons"])
    blocker["preflight"]["blocking_reason_count"] -= 1
    restamp_result!(blocker)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(blocker))

    policy = deepcopy(baseline)
    deleteat!(
        policy["policy_rejections"],
        findfirst(==("HINDSIGHT_STRUCTURAL_SELECTION_FORBIDDEN"), policy["policy_rejections"]),
    )
    restamp_result!(policy)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(policy))

    h1 = deepcopy(baseline)
    h1["intersections"]["horizon"]["abm_h1_basis"] =
        "post_step_flow_to_post_step_flow"
    h1["intersections"]["horizon"]["abm_h1_basis_compatible"] = true
    restamp_result!(h1)
    expect_preflight_error(:evidence_replay_mismatch, () -> Preflight.validate_preflight(h1))
end

@testset "path grammar fails closed" begin
    expect_preflight_error(:unsafe_path, () -> Preflight._validate_relative_path("../x"))
    expect_preflight_error(:unsafe_path, () -> Preflight._validate_relative_path("a/./b"))
    expect_preflight_error(:unsafe_path, () -> Preflight._validate_relative_path("a//b"))
    expect_preflight_error(:unsafe_path, () -> Preflight._validate_relative_path(MODULE_PATH))
    @test Preflight._validate_relative_path("scripts/us/Project.toml") ==
        ["scripts", "us", "Project.toml"]
end
