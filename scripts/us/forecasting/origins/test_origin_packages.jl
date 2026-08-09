#!/usr/bin/env julia

using Test
using SHA
using TOML

include(joinpath(@__DIR__, "USOriginPackages.jl"))
using .USOriginPackages

const HASH_A = repeat("a", 64)
const HASH_B = repeat("b", 64)
const HASH_C = repeat("c", 64)
const HASH_D = repeat("d", 64)
const HASH_E = repeat("e", 64)
const HASH_F = repeat("f", 64)

raw_file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

const READINESS_FIXTURE_DIRECTORY = mktempdir()
const READINESS_ARTIFACT_PATHS = Dict{String, String}()
for artifact_id in vcat(
        ["protocol", "environment", "macro_source"],
        collect(REQUIRED_BLOCK_IDS),
    )
    path = joinpath(
        READINESS_FIXTURE_DIRECTORY,
        replace(artifact_id, "_" => "-") * ".txt",
    )
    write(path, "verified synthetic artifact: $artifact_id\n")
    READINESS_ARTIFACT_PATHS[String(artifact_id)] = path
end
const READINESS_ARTIFACT_HASHES = Dict(
    artifact_id => raw_file_sha256(path)
        for (artifact_id, path) in READINESS_ARTIFACT_PATHS
)
atexit() do
    isdir(READINESS_FIXTURE_DIRECTORY) &&
        rm(READINESS_FIXTURE_DIRECTORY; recursive = true)
end

function synthetic_external_gate_validator(context)
    all(
        artifact_id ->
        raw_file_sha256(context.artifact_paths[artifact_id]) ==
            context.artifact_sha256[artifact_id],
        keys(context.artifact_sha256),
    ) ||
        return (
        status = "fail",
        reason = "synthetic gate blocker",
        evidence = ["synthetic origin-package fixture"],
    )
    return (
        status = "pass",
        reason = "synthetic gate passed",
        evidence = ["synthetic origin-package fixture"],
    )
end

const TEST_READINESS_RESOLVER = OriginReadinessResolver(
    artifact_paths = READINESS_ARTIFACT_PATHS,
    gate_validators = Dict(
        String(gate_id) => synthetic_external_gate_validator
            for gate_id in REQUIRED_GATE_IDS
            if gate_id ∉ ("macro_control_identity", "semantic_mapping")
    ),
)

function artifact_header(schema)
    return Dict{String, Any}(
        "schema_version" => schema,
        "canonicalization" =>
            "sorted_typed_v1_excluding_artifact_content_sha256",
        "content_sha256" => repeat("0", 64),
    )
end

function macro_fixture()
    artifact = Dict{String, Any}(
        "artifact" =>
            artifact_header("beforeit-us-opening-macro-control.v1"),
        "control" => Dict{String, Any}(
            "control_id" => "bea.t10105.2026q1.current-vintage",
            "reference_period" => "2026Q1",
            "availability_timestamp_utc" => "2026-08-04T13:30:00Z",
            "availability_basis" => "archive_retrieval_completion",
            "source_release_id" => "bea-nipa-t10105-retrieval-2026-08-04",
            "source_artifact_sha256" =>
                READINESS_ARTIFACT_HASHES["macro_source"],
            "transformation_version" => "bea-nipa-saar-to-quarter.v1",
            "unit" => "millions_current_usd_per_quarter",
        ),
        "values" => Dict{String, Any}(
            "nominal_gdp" => 7_966_430.25,
            "pce" => 5_408_737.0,
            "gpdi" => 1_408_504.0,
            "fixed_investment" => 1_415_517.25,
            "inventory_investment" => -7_013.25,
            "exports" => 877_175.75,
            "imports" => 1_082_164.75,
            "government_consumption_and_investment" => 1_354_178.75,
        ),
        "identities" => Dict{String, Any}(
            "gdp_formula" =>
                "gdp-pce-gpdi-exports+imports-government",
            "gdp_residual" => -0.5,
            "gdp_tolerance" => 1.0,
            "investment_formula" =>
                "gpdi-fixed_investment-inventory_investment",
            "investment_residual" => 0.0,
            "investment_tolerance" => 0.5,
        ),
    )
    stamp_content_sha256!(artifact)
    return artifact
end

function mapping_fixture(; approved = false)
    concepts = Dict(
        "pce" => (
            "household final consumption expenditure",
            ["initial_conditions.nominal_household_consumption"],
        ),
        "gpdi" => (
            "gross private domestic investment",
            ["initial_conditions.nominal_capitalformation"],
        ),
        "fixed_investment" => (
            "private fixed investment flow",
            ["initial_conditions.nominal_capitalformation"],
        ),
        "inventory_investment" => (
            "signed change in private inventories",
            ["proposed.initial_conditions.inventory_investment_s"],
        ),
        "exports" => (
            "exports of goods and services",
            ["initial_conditions.nominal_exports"],
        ),
        "imports" => (
            "imports of goods and services",
            ["initial_conditions.nominal_imports"],
        ),
        "government_consumption_and_investment" => (
            "government consumption expenditures and gross investment",
            ["initial_conditions.nominal_government_consumption"],
        ),
    )
    mappings = Dict{String, Any}[]
    for mapping_id in REQUIRED_MAPPING_IDS
        concept, fields = concepts[mapping_id]
        status =
            approved ? "approved" :
            mapping_id == "inventory_investment" ? "rejected" : "unresolved"
        push!(
            mappings,
            Dict{String, Any}(
                "mapping_id" => mapping_id,
                "source_control_id" => mapping_id,
                "model_concept" => concept,
                "model_fields" => fields,
                "status" => status,
                "treatment" =>
                    approved ? "synthetic reviewed mapping" :
                    "semantic design and implementation remain open",
                "evidence" => approved ?
                    ["synthetic independent review fixture"] :
                    ["current calibration semantics audit"],
                "model_owner" => approved ? "fixture-owner" : "unassigned",
                "independent_validator" =>
                    approved ? "fixture-validator" : "unassigned",
            ),
        )
    end
    artifact = Dict{String, Any}(
        "artifact" =>
            artifact_header("beforeit-us-opening-macro-mapping.v1"),
        "gate" => Dict{String, Any}(
            "status" => approved ? "CLOSED" : "OPEN",
            "rule" =>
                "all_required_mappings_approved_with_evidence_and_independent_ownership",
        ),
        "mapping" => mappings,
    )
    stamp_content_sha256!(artifact)
    return artifact
end

function block_fixture(block_id; available = true)
    basis =
        block_id in ("quarterly_vintages", "structural_inputs") ?
        "release_timestamp" :
        block_id in ("dynamic_parameters", "origin_state") ?
        "origin_information_cutoff" : "frozen_configuration"
    return Dict{String, Any}(
        "block_id" => block_id,
        "status" => available ? "available" : "missing",
        "eligibility_basis" => basis,
        "artifact_sha256" => available ?
            READINESS_ARTIFACT_HASHES[String(block_id)] : "unavailable",
        "as_of_timestamp_utc" =>
            available ?
            basis == "frozen_configuration" ?
            "not_applicable" : "2026-08-04T13:30:00Z" : "unavailable",
        "reason" =>
            available ? "synthetic fixture available" : "fixture absent",
        "evidence" => ["synthetic origin-package fixture"],
    )
end

function gate_fixture(gate_id; status = "pass")
    return Dict{String, Any}(
        "gate_id" => gate_id,
        "status" => status,
        "reason" => status == "pass" ?
            "synthetic gate passed" : "synthetic gate blocker",
        "evidence" => ["synthetic origin-package fixture"],
    )
end

function origin_fixture(
        macro_artifact,
        mapping;
        missing_block = nothing,
        failing_gate = nothing,
        information_track = "common_information",
    )
    blocks = [
        block_fixture(block_id; available = block_id != missing_block)
            for block_id in REQUIRED_BLOCK_IDS
    ]
    block_lookup = Dict(row["block_id"] => row for row in blocks)
    block_lookup["model_variant"]["artifact_sha256"] =
        READINESS_ARTIFACT_HASHES["model_variant"]
    block_lookup["parameter_registry"]["artifact_sha256"] =
        READINESS_ARTIFACT_HASHES["parameter_registry"]
    map_gate = mapping_gate(mapping)
    gates = Dict{String, Any}[]
    for gate_id in REQUIRED_GATE_IDS
        status =
            gate_id == "semantic_mapping" && map_gate.status == "OPEN" ?
            "fail" :
            gate_id == failing_gate ? "fail" : "pass"
        push!(gates, gate_fixture(gate_id; status))
    end
    computed_ready =
        missing_block === nothing &&
        failing_gate === nothing &&
        map_gate.status == "CLOSED"
    artifact = Dict{String, Any}(
        "artifact" => artifact_header("beforeit-us-origin-package.v1"),
        "origin" => Dict{String, Any}(
            "origin_id" => "origin.2026q1.synthetic",
            "origin_kind" => information_track == "common_information" ?
                "retrospective" : "current_diagnostic",
            "origin_timestamp_utc" => "2026-08-05T00:00:00Z",
            "reference_period" => "2026Q1",
            "created_at_utc" => "2026-08-05T10:00:00Z",
            "protocol_sha256" => READINESS_ARTIFACT_HASHES["protocol"],
            "environment_sha256" => READINESS_ARTIFACT_HASHES["environment"],
            "macro_control_sha256" =>
                macro_control_sha256(macro_artifact),
            "mapping_registry_sha256" =>
                mapping_registry_sha256(mapping),
            "model_variant_sha256" =>
                READINESS_ARTIFACT_HASHES["model_variant"],
            "parameter_registry_sha256" =>
                READINESS_ARTIFACT_HASHES["parameter_registry"],
            "information_track" => information_track,
            "evidence_class" =>
                information_track == "common_information" ?
                "vintage_clean_candidate" :
                "diagnostic_only_no_promotion",
            "status" => computed_ready ? "ready" : "cannot_run",
        ),
        "blocks" => blocks,
        "gates" => gates,
    )
    stamp_content_sha256!(artifact)
    return artifact
end

@testset "opening macro-control identity and provenance" begin
    macro_artifact = macro_fixture()
    result = validate_macro_control(macro_artifact)
    @test result.reference_period == "2026Q1"
    @test result.gdp_residual == -0.5
    @test result.investment_residual == 0.0
    @test result.sha256 == macro_artifact["artifact"]["content_sha256"]
    @test result.sha256 == macro_control_sha256(deepcopy(macro_artifact))
    @test macro_artifact["values"]["inventory_investment"] < 0

    reordered = Dict(reverse(collect(macro_artifact)))
    @test computed_content_sha256(reordered) ==
        macro_artifact["artifact"]["content_sha256"]

    tampered = deepcopy(macro_artifact)
    tampered["control"]["source_release_id"] *= "-tampered"
    @test_throws OriginValidationError validate_macro_control(tampered)

    bad_identity = deepcopy(macro_artifact)
    bad_identity["values"]["pce"] += 2.0
    stamp_content_sha256!(bad_identity)
    @test_throws OriginValidationError validate_macro_control(bad_identity)

    disguised_identity = deepcopy(macro_artifact)
    disguised_identity["values"]["pce"] += 2.0
    disguised_identity["identities"]["gdp_residual"] -= 2.0
    stamp_content_sha256!(disguised_identity)
    @test_throws OriginValidationError validate_macro_control(disguised_identity)

    bad_investment = deepcopy(macro_artifact)
    bad_investment["values"]["fixed_investment"] += 1.0
    bad_investment["identities"]["investment_residual"] -= 1.0
    stamp_content_sha256!(bad_investment)
    @test_throws OriginValidationError validate_macro_control(bad_investment)

    nonpositive = deepcopy(macro_artifact)
    nonpositive["values"]["exports"] = 0.0
    stamp_content_sha256!(nonpositive)
    @test_throws OriginValidationError validate_macro_control(nonpositive)

    extra = deepcopy(macro_artifact)
    extra["values"]["statistical_discrepancy"] = 0.5
    stamp_content_sha256!(extra)
    @test_throws OriginValidationError validate_macro_control(extra)
end

@testset "semantic mapping approval fails closed" begin
    open_mapping = mapping_fixture()
    open_result = validate_mapping_registry(open_mapping)
    @test open_result.status == "OPEN"
    @test length(open_result.open_mapping_ids) == 7
    @test "inventory_investment" in open_result.open_mapping_ids

    approved = mapping_fixture(; approved = true)
    approved_result = validate_mapping_registry(approved)
    @test approved_result.status == "CLOSED"
    @test isempty(approved_result.open_mapping_ids)
    @test mapping_registry_sha256(approved) ==
        approved["artifact"]["content_sha256"]

    self_approved = deepcopy(approved)
    self_approved["mapping"][1]["independent_validator"] = "fixture-owner"
    stamp_content_sha256!(self_approved)
    @test_throws OriginValidationError validate_mapping_registry(self_approved)

    placeholder = deepcopy(approved)
    placeholder["mapping"][1]["evidence"] = ["pending"]
    stamp_content_sha256!(placeholder)
    @test_throws OriginValidationError validate_mapping_registry(placeholder)

    false_gate = deepcopy(open_mapping)
    false_gate["gate"]["status"] = "CLOSED"
    stamp_content_sha256!(false_gate)
    @test_throws OriginValidationError validate_mapping_registry(false_gate)

    duplicate = deepcopy(open_mapping)
    duplicate["mapping"][2]["mapping_id"] =
        duplicate["mapping"][1]["mapping_id"]
    duplicate["mapping"][2]["source_control_id"] =
        duplicate["mapping"][1]["source_control_id"]
    stamp_content_sha256!(duplicate)
    @test_throws OriginValidationError validate_mapping_registry(duplicate)

    tampered = deepcopy(open_mapping)
    tampered["mapping"][1]["treatment"] *= " changed"
    @test_throws OriginValidationError validate_mapping_registry(tampered)
end

@testset "origin package readiness and leakage gates" begin
    macro_artifact = macro_fixture()
    approved = mapping_fixture(; approved = true)
    ready = origin_fixture(macro_artifact, approved)
    @test_throws OriginValidationError validate_origin_package(
        ready;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )
    result = validate_origin_package(
        ready;
        macro_control = macro_artifact,
        mapping_registry = approved,
        readiness_resolver = TEST_READINESS_RESOLVER,
    )
    @test result.status == "ready"
    @test result.information_track == "common_information"
    @test result.sha256 == ready["artifact"]["content_sha256"]
    @test origin_package_sha256(
        ready;
        macro_control = macro_artifact,
        mapping_registry = approved,
        readiness_resolver = TEST_READINESS_RESOLVER,
    ) == result.sha256

    mktempdir() do directory
        changed_protocol = joinpath(directory, "changed-protocol.txt")
        write(changed_protocol, "not the verified protocol artifact\n")
        changed_paths = copy(READINESS_ARTIFACT_PATHS)
        changed_paths["protocol"] = changed_protocol
        mismatched_resolver = OriginReadinessResolver(
            artifact_paths = changed_paths,
            gate_validators = TEST_READINESS_RESOLVER.gate_validators,
        )
        @test_throws OriginValidationError validate_origin_package(
            ready;
            macro_control = macro_artifact,
            mapping_registry = approved,
            readiness_resolver = mismatched_resolver,
        )
    end

    self_asserted_gate = deepcopy(ready)
    accounting_gate = only(
        gate
            for gate in self_asserted_gate["gates"]
            if gate["gate_id"] == "accounting"
    )
    accounting_gate["reason"] = "self-asserted pass without validator result"
    stamp_content_sha256!(self_asserted_gate)
    @test_throws OriginValidationError validate_origin_package(
        self_asserted_gate;
        macro_control = macro_artifact,
        mapping_registry = approved,
        readiness_resolver = TEST_READINESS_RESOLVER,
    )

    fake_source_macro = deepcopy(macro_artifact)
    fake_source_macro["control"]["source_artifact_sha256"] = HASH_A
    stamp_content_sha256!(fake_source_macro)
    fake_source_package = deepcopy(ready)
    fake_source_package["origin"]["macro_control_sha256"] =
        macro_control_sha256(fake_source_macro)
    stamp_content_sha256!(fake_source_package)
    @test_throws OriginValidationError validate_origin_package(
        fake_source_package;
        macro_control = fake_source_macro,
        mapping_registry = approved,
        readiness_resolver = TEST_READINESS_RESOLVER,
    )

    missing = origin_fixture(
        macro_artifact,
        approved;
        missing_block = "quarterly_vintages",
    )
    missing_result = validate_origin_package(
        missing;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )
    @test missing_result.status == "cannot_run"

    open_mapping = mapping_fixture()
    semantic_blocked = origin_fixture(macro_artifact, open_mapping)
    semantic_result = validate_origin_package(
        semantic_blocked;
        macro_control = macro_artifact,
        mapping_registry = open_mapping,
    )
    @test semantic_result.status == "cannot_run"

    false_ready = deepcopy(missing)
    false_ready["origin"]["status"] = "ready"
    stamp_content_sha256!(false_ready)
    @test_throws OriginValidationError validate_origin_package(
        false_ready;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )

    leaked_macro = deepcopy(macro_artifact)
    leaked_macro["control"]["availability_timestamp_utc"] =
        "2026-08-06T00:00:00Z"
    stamp_content_sha256!(leaked_macro)
    leaked = deepcopy(ready)
    leaked["origin"]["macro_control_sha256"] =
        macro_control_sha256(leaked_macro)
    stamp_content_sha256!(leaked)
    @test_throws OriginValidationError validate_origin_package(
        leaked;
        macro_control = leaked_macro,
        mapping_registry = approved,
    )

    leaked_block = deepcopy(ready)
    leaked_block["blocks"][1]["as_of_timestamp_utc"] =
        "2026-08-05T00:00:01Z"
    stamp_content_sha256!(leaked_block)
    @test_throws OriginValidationError validate_origin_package(
        leaked_block;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )

    variant_mismatch = deepcopy(ready)
    variant_mismatch["origin"]["model_variant_sha256"] = HASH_A
    stamp_content_sha256!(variant_mismatch)
    @test_throws OriginValidationError validate_origin_package(
        variant_mismatch;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )

    mixed = origin_fixture(
        macro_artifact,
        approved;
        information_track = "revised_mixed_vintage_diagnostic",
    )
    mixed_result = validate_origin_package(
        mixed;
        macro_control = macro_artifact,
        mapping_registry = approved,
        readiness_resolver = TEST_READINESS_RESOLVER,
    )
    @test mixed_result.status == "ready"
    @test mixed_result.evidence_class == "diagnostic_only_no_promotion"

    mislabeled = deepcopy(mixed)
    mislabeled["origin"]["evidence_class"] = "vintage_clean_candidate"
    stamp_content_sha256!(mislabeled)
    @test_throws OriginValidationError validate_origin_package(
        mislabeled;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )
end

@testset "complete, hash-addressed cannot-run decisions" begin
    macro_artifact = macro_fixture()
    approved = mapping_fixture(; approved = true)
    missing = origin_fixture(
        macro_artifact,
        approved;
        missing_block = "quarterly_vintages",
        failing_gate = "vintage_firewall",
    )
    record = build_cannot_run_record(
        missing;
        macro_control = macro_artifact,
        mapping_registry = approved,
        record_id = "cannot-run.origin.2026q1.synthetic",
        recorded_at_utc = "2026-08-05T10:01:00Z",
    )
    result = validate_cannot_run_record(
        record,
        missing;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )
    @test result.failure_count == 2
    @test Set(row["failure_id"] for row in record["failures"]) ==
        Set(["block:quarterly_vintages", "gate:vintage_firewall"])
    @test result.sha256 == record["artifact"]["content_sha256"]

    incomplete = deepcopy(record)
    pop!(incomplete["failures"])
    incomplete["record"]["failure_count"] -= 1
    stamp_content_sha256!(incomplete)
    @test_throws OriginValidationError validate_cannot_run_record(
        incomplete,
        missing;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )

    tampered = deepcopy(record)
    tampered["failures"][1]["reason"] *= " altered"
    @test_throws OriginValidationError validate_cannot_run_record(
        tampered,
        missing;
        macro_control = macro_artifact,
        mapping_registry = approved,
    )

    open_mapping = mapping_fixture()
    semantic_blocked = origin_fixture(macro_artifact, open_mapping)
    semantic_record = build_cannot_run_record(
        semantic_blocked;
        macro_control = macro_artifact,
        mapping_registry = open_mapping,
        record_id = "cannot-run.origin.2026q1.mapping",
        recorded_at_utc = "2026-08-05T10:02:00Z",
    )
    @test semantic_record["record"]["failure_count"] == 8
    @test count(
        row -> row["category"] == "mapping",
        semantic_record["failures"],
    ) == 7

    ready = origin_fixture(macro_artifact, approved)
    @test_throws OriginValidationError build_cannot_run_record(
        ready;
        macro_control = macro_artifact,
        mapping_registry = approved,
        record_id = "cannot-run.invalid",
        recorded_at_utc = "2026-08-05T10:03:00Z",
    )
end

@testset "tracked current-vintage diagnostic remains non-runnable" begin
    diagnostic_directory = normpath(
        joinpath(
            @__DIR__,
            "..",
            "..",
            "..",
            "..",
            "data",
            "us",
            "origins",
            "current_vintage_2026q1",
        ),
    )
    macro_artifact = load_toml_artifact(
        joinpath(diagnostic_directory, "opening_macro_control.toml"),
    )
    mapping = load_toml_artifact(
        joinpath(@__DIR__, "opening_macro_mapping.toml"),
    )
    package = load_toml_artifact(
        joinpath(diagnostic_directory, "origin_package.toml"),
    )
    cannot_run = load_toml_artifact(
        joinpath(diagnostic_directory, "cannot_run.toml"),
    )
    accounting_gate_path = normpath(
        joinpath(
            diagnostic_directory,
            "..",
            "..",
            "validation",
            "ACCOUNTING_GATES.toml",
        ),
    )
    accounting_gate_sha256 =
        bytes2hex(SHA.sha256(read(accounting_gate_path)))
    vintage_audit = TOML.parsefile(
        normpath(
            joinpath(
                diagnostic_directory,
                "..",
                "..",
                "validation",
                "VINTAGE_AUDIT.toml",
            ),
        ),
    )
    package_result = validate_origin_package(
        package;
        macro_control = macro_artifact,
        mapping_registry = mapping,
    )
    record_result = validate_cannot_run_record(
        cannot_run,
        package;
        macro_control = macro_artifact,
        mapping_registry = mapping,
    )
    @test package_result.status == "cannot_run"
    @test package_result.information_track ==
        "revised_mixed_vintage_diagnostic"
    @test package_result.sha256 ==
        "dbadd9008743f5745cd7152cc5b90fe17c26b5b25f34b1cee91f60b21c72df27"
    @test mapping_gate(mapping).status == "OPEN"
    @test mapping_registry_sha256(mapping) ==
        "a5afb57a8551b06c6583aa81a1f79f41575a334eca95960167d9b2a9e6f1d665"
    @test all(
        row -> any(
            evidence -> occursin("no mapping approval", evidence),
            String.(row["evidence"]),
        ),
        mapping["mapping"],
    )
    @test all(
        row -> any(
            evidence -> occursin(
                accounting_gate_sha256,
                evidence,
            ),
            String.(row["evidence"]),
        ),
        mapping["mapping"],
    )
    @test record_result.failure_count == 21
    @test record_result.sha256 ==
        "2cd145bbbe50556dfd1d10c86aa70feea4725ca590e618c3b4dd5e009662ee65"
    @test vintage_audit["protocol_admissible_historical_origins"] == 0
    @test !vintage_audit["strict_no_download_pilot_runnable"]
    @test vintage_audit["tier1_coverage"]["required_target_count"] == 8
    @test vintage_audit["tier1_coverage"][
        "exact_vintage_clean_target_count",
    ] == 0
end
