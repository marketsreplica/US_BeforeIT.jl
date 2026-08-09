#!/usr/bin/env julia

using Test
using TOML

include(joinpath(@__DIR__, "USModelVariants.jl"))
using .USModelVariants

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const REPOSITORY_LINE_COUNTS = Dict{String, Int}()

function restamp!(artifact)
    artifact["artifact"]["content_sha256"] =
        computed_artifact_sha256(artifact)
    return artifact
end

function restamp_pair!(crosswalk, variants)
    restamp!(crosswalk)
    variants["crosswalk_sha256"] =
        crosswalk["artifact"]["content_sha256"]
    restamp!(variants)
    return crosswalk, variants
end

function bind_gate_attestations!(crosswalk, variants)
    restamp!(crosswalk)
    variants["crosswalk_sha256"] =
        crosswalk["artifact"]["content_sha256"]
    for actor in ("model_owner", "independent_validator")
        variants["gate"]["$(actor)_signature"] =
            expected_gate_attestation(crosswalk, variants, actor)
    end
    restamp!(variants)
    return crosswalk, variants
end

function repository_evidence_location(pointer)
    matched =
        match(r"^repo:([^:]+)(?::([0-9]+)(?:-([0-9]+))?)?$", pointer)
    matched === nothing && return nothing
    path = joinpath(REPOSITORY_ROOT, matched.captures[1])
    first_line = if matched.captures[2] === nothing
        nothing
    else
        parse(Int, matched.captures[2])
    end
    last_line = if matched.captures[3] === nothing
        first_line
    else
        parse(Int, matched.captures[3])
    end
    return (; path, first_line, last_line)
end

@testset "WS-0B registry is complete and hash-addressed" begin
    registry = load_registry()
    crosswalk = registry.crosswalk
    variants = registry.variants
    report = registry.report

    @test report.schema_valid
    @test !report.gate_closed
    @test report.gate_status == "open"
    @test report.entry_count == 40
    @test report.crosswalk_sha256 ==
        "da097ef97ad6510dfed5234df7b14b4b48ad63d62a4f52f6829f70c0e2f6cde6"
    @test report.variants_sha256 ==
        "1fbdf6fcbeedc07fb9971b7e39c18852f74ace8fb07055b4f1ad2f43dcb29728"
    @test occursin(r"^[0-9a-f]{64}$", report.crosswalk_sha256)
    @test occursin(r"^[0-9a-f]{64}$", report.variants_sha256)
    @test occursin(r"^[0-9a-f]{64}$", report.approval_payload_sha256)
    @test variants["crosswalk_sha256"] == report.crosswalk_sha256
    @test crosswalk["source_baseline_commit"] ==
        "6030f7558a9956a99465a09e31c51f37df198c90"
    @test crosswalk["paper_sha256"] ==
        "8fce5fea20d90a361346b32916bf88b680a6ae7e8f835a06ceb9a0aeb7debaf2"

    entries = crosswalk["entries"]
    @test length(entries) == 40
    @test count(
        entry -> entry["classification"] == "paper_typo_candidate",
        entries,
    ) == 3
    @test count(
        entry -> entry["classification"] == "printed_upstream_difference",
        entries,
    ) == 19
    @test count(
        entry -> entry["classification"] == "implementation_convention",
        entries,
    ) == 3
    @test count(
        entry -> entry["classification"] == "latent_defect",
        entries,
    ) == 2
    @test count(
        entry -> entry["classification"] == "us_fork_addition",
        entries,
    ) == 13
    @test count(entry -> startswith(entry["id"], "diff_"), entries) == 19

    expected_variants = Set(
        [
            "printed_paper_reference",
            "upstream_compatible_6030f75",
            "reviewed_us_port",
            "corrected_candidate",
        ],
    )
    for entry in entries
        @test Set(keys(entry["treatments"])) == expected_variants
        @test !isempty(entry["paper_evidence"])
        @test !isempty(entry["code_evidence"])
        @test !isempty(entry["test_evidence"])
        @test !isempty(entry["owner"])
        @test !isempty(entry["independent_validator"])
        for field in ("code_evidence", "test_evidence")
            for pointer in entry[field]
                location = repository_evidence_location(pointer)
                if location !== nothing
                    @test isfile(location.path)
                    if location.first_line !== nothing
                        @test 1 <= location.first_line <= location.last_line
                        line_count = get!(
                            () -> countlines(location.path),
                            REPOSITORY_LINE_COUNTS,
                            location.path,
                        )
                        @test location.last_line <= line_count
                    end
                end
            end
        end
    end

    variant_entries = variants["variants"]
    @test [variant["id"] for variant in variant_entries] == [
        "printed_paper_reference",
        "upstream_compatible_6030f75",
        "reviewed_us_port",
        "corrected_candidate",
    ]
    @test variant_entries[1]["executable"] === false
    @test variant_entries[2]["code_revision"] ==
        "6030f7558a9956a99465a09e31c51f37df198c90"
    @test variant_entries[3]["allowed_claim"] ==
        "reviewed_us_port_configuration_not_forecast_validated"
    @test variant_entries[4]["capacity_minimum"] ==
        "elementwise_capacity_cap"
    @test variant_entries[4]["growth_process"] ==
        "log_level_default_with_base_model_guard"

    firms_source =
        read(joinpath(REPOSITORY_ROOT, "src", "agent_actions", "firms.jl"), String)
    @test occursin(
        "min.(Q_s_i, firms.K_i .* firms.kappa_i)",
        firms_source,
    )
    @test !occursin(
        "min(Q_s_i, firms.K_i .* firms.kappa_i)",
        firms_source,
    )
    init_source =
        read(joinpath(REPOSITORY_ROOT, "src", "model_init", "init.jl"), String)
    @test occursin(
        "get(parameters, \"use_growth_rate_ar1\", false)",
        init_source,
    )
    @test occursin("Use ModelGR or recalibrate", init_source)
end

@testset "WS-0B canonical hashes are deterministic and tamper-evident" begin
    registry = load_registry()
    crosswalk = registry.crosswalk
    variants = registry.variants

    reordered_crosswalk = Dict(reverse(collect(pairs(deepcopy(crosswalk)))))
    @test computed_artifact_sha256(reordered_crosswalk) ==
        registry.report.crosswalk_sha256

    reordered_variants = Dict(reverse(collect(pairs(deepcopy(variants)))))
    @test computed_artifact_sha256(reordered_variants) ==
        registry.report.variants_sha256

    tampered = deepcopy(crosswalk)
    tampered["entries"][1]["title"] *= " tampered"
    @test_throws RegistryValidationError registry_report(tampered, variants)

    tampered_link = deepcopy(variants)
    tampered_link["crosswalk_sha256"] = repeat("f", 64)
    restamp!(tampered_link)
    @test_throws RegistryValidationError registry_report(
        crosswalk,
        tampered_link,
    )
end

@testset "WS-0B validator fails closed on omissions and ambiguity" begin
    registry = load_registry()
    base_crosswalk = registry.crosswalk
    base_variants = registry.variants

    missing_entry = deepcopy(base_crosswalk)
    pop!(missing_entry["entries"])
    @test_throws RegistryValidationError validate_crosswalk(missing_entry)

    missing_required_id = deepcopy(base_crosswalk)
    missing_required_id["entries"][1]["id"] = "paper_typo_replacement"
    @test_throws RegistryValidationError validate_crosswalk(missing_required_id)

    missing_field = deepcopy(base_crosswalk)
    delete!(missing_field["entries"][1], "owner")
    @test_throws RegistryValidationError validate_crosswalk(missing_field)

    missing_treatment = deepcopy(base_crosswalk)
    delete!(
        missing_treatment["entries"][1]["treatments"],
        "corrected_candidate",
    )
    @test_throws RegistryValidationError validate_crosswalk(missing_treatment)

    ambiguous_treatment = deepcopy(base_crosswalk)
    ambiguous_treatment["entries"][1]["treatments"][
        "corrected_candidate",
    ] = "inherit"
    @test_throws RegistryValidationError validate_crosswalk(
        ambiguous_treatment,
    )

    vague_treatment = deepcopy(base_crosswalk)
    vague_treatment["entries"][1]["treatments"][
        "corrected_candidate",
    ] = "document_later"
    @test_throws RegistryValidationError validate_crosswalk(vague_treatment)

    compound_ambiguity = deepcopy(base_crosswalk)
    compound_ambiguity["entries"][1]["treatments"][
        "corrected_candidate",
    ] = "retain_tbd"
    @test_throws RegistryValidationError validate_crosswalk(
        compound_ambiguity,
    )

    missing_evidence = deepcopy(base_crosswalk)
    empty!(missing_evidence["entries"][1]["paper_evidence"])
    @test_throws RegistryValidationError validate_crosswalk(missing_evidence)

    bad_evidence_prefix = deepcopy(base_crosswalk)
    bad_evidence_prefix["entries"][1]["code_evidence"] =
        ["somewhere in the source"]
    @test_throws RegistryValidationError validate_crosswalk(
        bad_evidence_prefix,
    )

    blank_paper_evidence = deepcopy(base_crosswalk)
    blank_paper_evidence["entries"][1]["paper_evidence"] = ["paper:"]
    @test_throws RegistryValidationError validate_crosswalk(
        blank_paper_evidence,
    )

    blank_repository_evidence = deepcopy(base_crosswalk)
    blank_repository_evidence["entries"][1]["code_evidence"] = ["repo:"]
    @test_throws RegistryValidationError validate_crosswalk(
        blank_repository_evidence,
    )

    deferred_treatment = deepcopy(base_crosswalk)
    deferred_treatment["entries"][1]["treatments"][
        "corrected_candidate",
    ] = "retain_to_be_decided"
    @test_throws RegistryValidationError validate_crosswalk(
        deferred_treatment,
    )

    unassigned_treatment = deepcopy(base_crosswalk)
    unassigned_treatment["entries"][1]["treatments"][
        "corrected_candidate",
    ] = "unassigned"
    @test_throws RegistryValidationError validate_crosswalk(
        unassigned_treatment,
    )

    unknown_entry_field = deepcopy(base_crosswalk)
    unknown_entry_field["entries"][1]["replicates_paper"] = true
    @test_throws RegistryValidationError validate_crosswalk(
        unknown_entry_field,
    )

    blanket_claim_allowed = deepcopy(base_crosswalk)
    blanket_claim_allowed["blanket_replication_claims_prohibited"] = false
    @test_throws RegistryValidationError validate_crosswalk(
        blanket_claim_allowed,
    )

    blanket_variant_claim = deepcopy(base_variants)
    blanket_variant_claim["variants"][2]["allowed_claim"] =
        "exact_paper_replication"
    @test_throws RegistryValidationError validate_variants(
        blanket_variant_claim,
    )

    missing_variant = deepcopy(base_variants)
    pop!(missing_variant["variants"])
    @test_throws RegistryValidationError validate_variants(missing_variant)

    unknown_variant_field = deepcopy(base_variants)
    unknown_variant_field["variants"][4]["silent_fallback"] = true
    @test_throws RegistryValidationError validate_variants(
        unknown_variant_field,
    )
end

@testset "WS-0B schema validity is not governance approval" begin
    registry = load_registry()
    report = registry.report
    @test report.schema_valid
    @test report.gate_status == "open"
    @test report.open_entry_count == 27
    @test report.pending_test_entry_count == 34
    @test report.pending_test_pointer_count == 36
    @test report.untested_entry_count == 25
    @test report.unassigned_owner_count == 0
    @test report.unassigned_validator_count == 40
    @test "crosswalk artifact status is draft" in report.gate_reasons
    @test "variant artifact status is draft" in report.gate_reasons
    @test "governance status is open" in report.gate_reasons
    @test "model-owner signature is missing" in report.gate_reasons
    @test "independent-validator signature is missing" in
        report.gate_reasons
    @test any(
        reason -> occursin(
            "crosswalk entries lack an independent validator",
            reason,
        ),
        report.gate_reasons,
    )
    @test_throws RegistryValidationError require_closed_gate(report)

    false_closed = deepcopy(registry.variants)
    false_closed["gate"]["status"] = "closed"
    @test_throws RegistryValidationError validate_variants(false_closed)

    malformed_signature = deepcopy(registry.variants)
    malformed_signature["gate"]["model_owner"] = "model_engineering_lead"
    malformed_signature["gate"]["model_owner_signature"] = "signed"
    @test_throws RegistryValidationError validate_variants(
        malformed_signature,
    )

    unassigned_signer = deepcopy(registry.variants)
    unassigned_signer["gate"]["model_owner_signature"] =
        "sha256:" * repeat("1", 64)
    unassigned_signer["gate"]["model_owner_signed_at"] =
        "2026-08-05T12:00:00Z"
    @test_throws RegistryValidationError validate_variants(unassigned_signer)

    signed_crosswalk = deepcopy(registry.crosswalk)
    signed_crosswalk["artifact_status"] = "approved"
    for entry in signed_crosswalk["entries"]
        entry["independent_validator"] = "independent_replicator"
        startswith(entry["status"], "open_") &&
            (entry["status"] = "documented_variant_split")
        entry["test_evidence"] = [
            "repo:scripts/us/forecasting/variants/test_variants.jl:1",
        ]
    end
    signed_variants = deepcopy(registry.variants)
    signed_variants["artifact_status"] = "approved"
    gate = signed_variants["gate"]
    gate["status"] = "closed"
    gate["model_owner"] = "model_engineering_lead"
    gate["model_owner_signed_at"] = "2026-08-05T12:00:00Z"
    gate["independent_validator"] = "independent_replicator"
    gate["independent_validator_signed_at"] = "2026-08-05T12:01:00Z"
    bind_gate_attestations!(signed_crosswalk, signed_variants)
    signed_report = registry_report(signed_crosswalk, signed_variants)
    @test signed_report.schema_valid
    @test signed_report.gate_closed
    @test signed_report.gate_status == "closed"
    @test isempty(signed_report.gate_reasons)
    @test require_closed_gate(signed_report) === signed_report

    unbound_attestation = deepcopy(signed_variants)
    unbound_attestation["gate"]["model_owner_signature"] =
        "sha256:" * repeat("3", 64)
    restamp!(unbound_attestation)
    @test_throws RegistryValidationError registry_report(
        signed_crosswalk,
        unbound_attestation,
    )

    conflicted_crosswalk = deepcopy(signed_crosswalk)
    conflicted_variants = deepcopy(signed_variants)
    conflicted_crosswalk["entries"][1]["independent_validator"] =
        conflicted_crosswalk["entries"][1]["owner"]
    bind_gate_attestations!(conflicted_crosswalk, conflicted_variants)
    @test_throws RegistryValidationError registry_report(
        conflicted_crosswalk,
        conflicted_variants,
    )

    unowned_crosswalk = deepcopy(signed_crosswalk)
    unowned_variants = deepcopy(signed_variants)
    unowned_crosswalk["entries"][1]["owner"] = "unassigned"
    bind_gate_attestations!(unowned_crosswalk, unowned_variants)
    @test_throws RegistryValidationError registry_report(
        unowned_crosswalk,
        unowned_variants,
    )

    draft_crosswalk = deepcopy(signed_crosswalk)
    draft_variants = deepcopy(signed_variants)
    draft_crosswalk["artifact_status"] = "draft"
    bind_gate_attestations!(draft_crosswalk, draft_variants)
    @test_throws RegistryValidationError registry_report(
        draft_crosswalk,
        draft_variants,
    )

    same_reviewer = deepcopy(signed_variants)
    same_reviewer["gate"]["independent_validator"] =
        same_reviewer["gate"]["model_owner"]
    restamp!(same_reviewer)
    @test_throws RegistryValidationError validate_variants(same_reviewer)
end

@testset "WS-0B parser fails closed" begin
    mktempdir() do directory
        invalid_crosswalk = joinpath(directory, "invalid-crosswalk.toml")
        write(invalid_crosswalk, "[broken\n")
        @test_throws RegistryValidationError load_registry(
            invalid_crosswalk,
            DEFAULT_VARIANTS_PATH,
        )
    end
    @test_throws RegistryValidationError load_registry(
        joinpath(@__DIR__, "missing-crosswalk.toml"),
        DEFAULT_VARIANTS_PATH,
    )
end
