using Test

include(joinpath(@__DIR__, "USRegimeAdjudicationLedger.jl"))
using .USRegimeAdjudicationLedger

const PANDEMIC = "PANDEMIC_REGIME_CONTRAST"
const NBER = "NBER_REGIME_CONTRAST"
const POLICY = "POLICY_REGIME_CONTRAST"

function input_record(
        observation_id,
        contrast_id;
        tokens,
        evidence_refs = [
            "evidence:$observation_id:$contrast_id:$index"
                for index in eachindex(tokens)
        ],
        disposition = "REGIME_ACCEPTED",
        accepted = only(tokens),
        issue = "NONE",
        suffix = "",
    )
    return Dict{String, Any}(
        "record_id" => "$(observation_id).$(contrast_id)$suffix",
        "observation_id" => observation_id,
        "contrast_id" => contrast_id,
        "raw_tokens" => copy(tokens),
        "evidence_refs" => copy(evidence_refs),
        "disposition" => disposition,
        "accepted_regime_label" => accepted,
        "issue_code" => issue,
    )
end

function set_tokens!(row, tokens)
    row["raw_tokens"] = collect(tokens)
    row["evidence_refs"] = [
        "evidence:replacement:$(row["record_id"]):$index"
            for index in eachindex(tokens)
    ]
    return row
end

function valid_inputs()
    rows = Dict{String, Any}[
        input_record(
            "origin_1",
            PANDEMIC;
            tokens = ["PRE_PANDEMIC"],
        ),
        input_record(
            "origin_1",
            NBER;
            tokens = ["NBER_EXPANSION"],
        ),
        input_record(
            "origin_1",
            POLICY;
            tokens = ["STANDARD_POLICY"],
        ),
        input_record(
            "origin_2",
            PANDEMIC;
            tokens = ["Other"],
            disposition = "REGIME_UNKNOWN_PENDING_ADJUDICATION",
            accepted = "NOT_ACCEPTED",
            issue = "OTHER_UNREGISTERED_FOR_REGIME",
        ),
        input_record(
            "origin_2",
            NBER;
            tokens = ["NBER_EXPANSION"],
        ),
        input_record(
            "origin_2",
            POLICY;
            tokens = ["STANDARD_POLICY"],
        ),
        input_record(
            "origin_3",
            PANDEMIC;
            tokens = ["POST_ACUTE"],
        ),
        input_record(
            "origin_3",
            NBER;
            tokens = ["NBER_RECESSION", "NBER_EXPANSION"],
            disposition = "REGIME_CONTRADICTION_QUARANTINED",
            accepted = "NOT_ACCEPTED",
            issue = "MUTUALLY_EXCLUSIVE_REGIME_LABELS_PRESENT",
        ),
        input_record(
            "origin_3",
            POLICY;
            tokens = ["ELB_POLICY", "STANDARD_POLICY"],
            disposition = "REGIME_CONFLICT_QUARANTINED",
            accepted = "NOT_ACCEPTED",
            issue = "SOURCE_ASSERTIONS_DISAGREE",
        ),
    ]
    return rows
end

function build_valid()
    rows = valid_inputs()
    return build_regime_adjudication_ledger(
        "synthetic.regime.ledger.v1",
        ["origin_1", "origin_2", "origin_3"],
        reverse(rows),
    )
end

function rehash!(document)
    document["artifact"]["content_sha256"] =
        computed_ledger_sha256(document)
    return document
end

function record_index(rows, observation_id, contrast_id)
    return only(
        index for (index, row) in enumerate(rows) if
            row["observation_id"] == observation_id &&
            row["contrast_id"] == contrast_id
    )
end

@testset "bounded regime-adjudication ledger" begin
    document = build_valid()
    validated = validate_regime_adjudication_ledger(document)

    @test validated.schema_version == LEDGER_SCHEMA_VERSION
    @test validated.ledger_id == "synthetic.regime.ledger.v1"
    @test validated.observation_ids ==
        ("origin_1", "origin_2", "origin_3")
    @test full_sample_primary_inclusion_mask(validated) ==
        (true, true, true)
    @test affected_contrast_inclusion_mask(validated, PANDEMIC) ==
        (true, false, true)
    @test affected_contrast_inclusion_mask(validated, NBER) ==
        (true, true, false)
    @test affected_contrast_inclusion_mask(validated, POLICY) ==
        (true, true, false)
    @test validated.summary.observation_count == 3
    @test validated.summary.record_count == 9
    @test validated.summary.raw_token_count == 11
    @test validated.summary.accepted_count == 6
    @test validated.summary.pending_count == 1
    @test validated.summary.contradiction_count == 1
    @test validated.summary.conflict_count == 1
    @test validated.summary.affected_contrast_included_count == 6
    @test validated.summary.affected_contrast_excluded_count == 3
    @test validated.summary.full_sample_primary_included_count == 3
    @test length(validated.raw_token_inventory) == 11
    @test any(
        item ->
        item.observation_id == "origin_2" &&
            item.contrast_id == PANDEMIC &&
            item.raw_token == "Other",
        validated.raw_token_inventory,
    )
    @test validated.records[1].observation_id == "origin_1"
    @test validated.records[1].contrast_id == PANDEMIC
    @test validated.records[1].raw_tokens == ("PRE_PANDEMIC",)
    @test validated.records[1].evidence_refs ==
        ("evidence:origin_1:PANDEMIC_REGIME_CONTRAST:1",)
    @test all(
        !isempty(item.evidence_ref)
            for item in validated.raw_token_inventory
    )
    @test !validated.scoring_artifact
    @test !validated.promotion_artifact
    @test !validated.empirical_result_artifact
    @test document["artifact"]["content_sha256"] ==
        computed_ledger_sha256(document)
    @test all(document["full_sample_primary_mask"])
    @test_throws RegimeAdjudicationError affected_contrast_inclusion_mask(
        validated,
        "Other",
    )
end

@testset "Used, Other, unknown, provenance, and BEA labels are preserved" begin
    cases = (
        (
            token = "Used",
            issue = "BARE_USED_INVALID_FOR_REGIME",
        ),
        (
            token = "Other",
            issue = "OTHER_UNREGISTERED_FOR_REGIME",
        ),
        (
            token = "mystery-regime",
            issue = "UNKNOWN_OR_UNREGISTERED_RAW_TOKEN",
        ),
        (
            token = "0",
            issue = "UNKNOWN_OR_UNREGISTERED_RAW_TOKEN",
        ),
        (
            token = "SOURCE_USAGE_INPUT_ONLY",
            issue = "SOURCE_USAGE_PROVENANCE_OUTSIDE_REGIME_VOCABULARY",
        ),
        (
            token = "Used",
            issue = "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY",
        ),
        (
            token = "Other",
            issue = "NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY",
        ),
    )
    for (case_index, case) in enumerate(cases)
        rows = valid_inputs()
        index = record_index(rows, "origin_2", PANDEMIC)
        set_tokens!(rows[index], [case.token])
        rows[index]["issue_code"] = case.issue
        document = build_regime_adjudication_ledger(
            "preservation.case.$case_index",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
        validated = validate_regime_adjudication_ledger(document)
        record = only(
            item for item in validated.records if
                item.observation_id == "origin_2" &&
                item.contrast_id == PANDEMIC
        )
        @test record.raw_tokens == (case.token,)
        @test record.disposition ==
            "REGIME_UNKNOWN_PENDING_ADJUDICATION"
        @test record.issue_code == case.issue
        @test !record.include_in_affected_regime_contrast
        @test affected_contrast_inclusion_mask(validated, PANDEMIC) ==
            (true, false, true)
        @test affected_contrast_inclusion_mask(validated, NBER) ==
            (true, true, false)
        @test full_sample_primary_inclusion_mask(validated) ==
            (true, true, true)
        @test any(
            item ->
            item.record_id == record.record_id &&
                item.raw_token == case.token,
            validated.raw_token_inventory,
        )
    end

    rows = valid_inputs()
    index = record_index(rows, "origin_2", PANDEMIC)
    set_tokens!(rows[index], String[])
    rows[index]["issue_code"] = "NO_RAW_REGIME_TOKEN_SUPPLIED"
    document = build_regime_adjudication_ledger(
        "no.raw.token.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )
    validated = validate_regime_adjudication_ledger(document)
    @test validated.summary.raw_token_count == 10
    @test !affected_contrast_inclusion_mask(validated, PANDEMIC)[2]
    @test all(full_sample_primary_inclusion_mask(validated))
end

@testset "out-of-vocabulary tokens cannot bypass pending adjudication" begin
    conflict_token_sets = (
        ["Used", "Other"],
        ["mystery-regime-a", "mystery-regime-b"],
        ["SOURCE_USAGE_INPUT_ONLY", "SOURCE_USAGE_OUTPUT_ONLY"],
        ["NBER_RECESSION", "NBER_EXPANSION"],
    )
    for tokens in conflict_token_sets
        rows = valid_inputs()
        index = record_index(rows, "origin_3", POLICY)
        set_tokens!(rows[index], tokens)
        @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
            "invalid.conflict.routing.v1",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
    end

    contradiction_extra_tokens = (
        "Used",
        "Other",
        "mystery-regime",
        "SOURCE_USAGE_INPUT_ONLY",
    )
    for token in contradiction_extra_tokens
        rows = valid_inputs()
        index = record_index(rows, "origin_3", NBER)
        set_tokens!(
            rows[index],
            ["NBER_RECESSION", "NBER_EXPANSION", token],
        )
        @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
            "invalid.contradiction.routing.v1",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
    end
end

@testset "malformed disposition, whitespace, and coercion fail closed" begin
    cases = Function[
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["disposition"] = "REGIME_ACCEPTED"
            rows[index]["accepted_regime_label"] = "PRE_PANDEMIC"
            rows[index]["issue_code"] = "NONE"
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            set_tokens!(rows[index], ["Used"])
            rows[index]["issue_code"] =
                "UNKNOWN_OR_UNREGISTERED_RAW_TOKEN"
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["disposition"] = "Other"
        end,
        function (rows)
            index = record_index(rows, "origin_1", PANDEMIC)
            rows[index]["accepted_regime_label"] = "NBER_EXPANSION"
        end,
        function (rows)
            index = record_index(rows, "origin_1", PANDEMIC)
            set_tokens!(rows[index], ["PRE_PANDEMIC", "POST_ACUTE"])
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["accepted_regime_label"] = "PRE_PANDEMIC"
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["issue_code"] = "UNREGISTERED_PENDING_REASON"
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            set_tokens!(rows[index], Any[0])
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            set_tokens!(rows[index], [" Other "])
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["evidence_refs"] = String[]
        end,
        function (rows)
            index = record_index(rows, "origin_2", PANDEMIC)
            rows[index]["evidence_refs"] = ["unknown"]
        end,
    ]
    for mutate! in cases
        rows = valid_inputs()
        mutate!(rows)
        @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
            "invalid.disposition.v1",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
    end
end

@testset "evidence references use closed non-placeholder namespaces" begin
    invalid_refs = (
        "placeholder:source",
        "Placeholder:source",
        "evidence:unknown",
        "EVIDENCE:Unknown",
        "todo#source",
        "TODO#SOURCE",
        "evidence:n/a",
        "EVIDENCE:N/A",
        "custom:source-1",
        "evidence:",
    )
    for evidence_ref in invalid_refs
        rows = valid_inputs()
        index = record_index(rows, "origin_1", PANDEMIC)
        rows[index]["evidence_refs"] = [evidence_ref]
        @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
            "invalid.evidence.ref.v1",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
    end

    for (case_index, evidence_ref) in enumerate(
            (
                "manifest:release-2026Q1",
                "source:table-record-17",
                "https://example.com/release-2026Q1",
            ),
        )
        rows = valid_inputs()
        index = record_index(rows, "origin_1", PANDEMIC)
        rows[index]["evidence_refs"] = [evidence_ref]
        document = build_regime_adjudication_ledger(
            "recognized.evidence.namespace.$case_index",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
        validated = validate_regime_adjudication_ledger(document)
        record = only(
            item for item in validated.records if
                item.observation_id == "origin_1" &&
                item.contrast_id == PANDEMIC
        )
        @test record.evidence_refs == (evidence_ref,)
    end
end

@testset "contradiction and source-conflict reasons are typed" begin
    cases = Function[
        function (rows)
            index = record_index(rows, "origin_3", NBER)
            set_tokens!(rows[index], ["NBER_RECESSION"])
        end,
        function (rows)
            index = record_index(rows, "origin_3", NBER)
            rows[index]["issue_code"] = "UNKNOWN_CONTRADICTION"
        end,
        function (rows)
            index = record_index(rows, "origin_3", POLICY)
            set_tokens!(rows[index], ["ELB_POLICY", "ELB_POLICY"])
        end,
        function (rows)
            index = record_index(rows, "origin_3", POLICY)
            rows[index]["issue_code"] = "UNKNOWN_CONFLICT"
        end,
        function (rows)
            index = record_index(rows, "origin_3", POLICY)
            rows[index]["evidence_refs"] = [
                "evidence:duplicate",
                "evidence:duplicate",
            ]
        end,
        function (rows)
            index = record_index(rows, "origin_3", NBER)
            rows[index]["evidence_refs"] = [
                "evidence:duplicate",
                "evidence:duplicate",
            ]
        end,
        function (rows)
            index = record_index(rows, "origin_3", POLICY)
            set_tokens!(rows[index], ["ELB_POLICY", "ELB_POLICY"])
            rows[index]["evidence_refs"] = [
                "evidence:duplicate",
                "evidence:duplicate",
            ]
            rows[index]["issue_code"] = "SOURCE_PROVENANCE_CONFLICT"
        end,
    ]
    for mutate! in cases
        rows = valid_inputs()
        mutate!(rows)
        @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
            "invalid.conflict.v1",
            ["origin_1", "origin_2", "origin_3"],
            rows,
        )
    end

    rows = valid_inputs()
    index = record_index(rows, "origin_3", NBER)
    set_tokens!(rows[index], ["ELB_POLICY"])
    rows[index]["issue_code"] = "REGIME_LABEL_CONTRADICTS_CONTRAST"
    document = build_regime_adjudication_ledger(
        "cross.contrast.contradiction.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )
    validated = validate_regime_adjudication_ledger(document)
    @test validated.summary.contradiction_count == 1
    @test !affected_contrast_inclusion_mask(validated, NBER)[3]

    rows = valid_inputs()
    index = record_index(rows, "origin_3", POLICY)
    set_tokens!(rows[index], ["ELB_POLICY", "ELB_POLICY"])
    rows[index]["evidence_refs"] = [
        "evidence:provenance:vintage-1",
        "evidence:provenance:vintage-2",
    ]
    rows[index]["issue_code"] = "SOURCE_PROVENANCE_CONFLICT"
    document = build_regime_adjudication_ledger(
        "same.assertion.provenance.conflict.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )
    validated = validate_regime_adjudication_ledger(document)
    record = only(
        item for item in validated.records if
            item.observation_id == "origin_3" &&
            item.contrast_id == POLICY
    )
    @test record.raw_tokens == ("ELB_POLICY", "ELB_POLICY")
    @test record.evidence_refs == (
        "evidence:provenance:vintage-1",
        "evidence:provenance:vintage-2",
    )
    @test record.issue_code == "SOURCE_PROVENANCE_CONFLICT"
    @test !record.include_in_affected_regime_contrast
end

@testset "protocol vocabularies cannot be extended in another process" begin
    module_file =
        joinpath(@__DIR__, "USRegimeAdjudicationLedger.jl")
    probe = """
    include($(repr(module_file)))
    using .USRegimeAdjudicationLedger

    try
        ACCEPTED_REGIME_LABELS["PANDEMIC_REGIME_CONTRAST"] = ("Used",)
        exit(11)
    catch error
        error isa MethodError || exit(12)
    end
    try
        push!(
            ACCEPTED_REGIME_LABELS.PANDEMIC_REGIME_CONTRAST,
            "Used",
        )
        exit(13)
    catch error
        error isa MethodError || exit(14)
    end
    try
        push!(
            USRegimeAdjudicationLedger.ALL_ACCEPTED_LABELS,
            "Used",
        )
        exit(15)
    catch error
        error isa MethodError || exit(16)
    end
    try
        push!(
            USRegimeAdjudicationLedger.RESERVED_ID_TOKENS,
            "new-placeholder",
        )
        exit(17)
    catch error
        error isa MethodError || exit(18)
    end
    "Used" in ACCEPTED_REGIME_LABELS.PANDEMIC_REGIME_CONTRAST &&
        exit(19)
    exit(0)
    """
    command = `$(Base.julia_cmd()) --startup-file=no -e $probe`
    process = run(
        pipeline(
            ignorestatus(command);
            stdout = devnull,
            stderr = devnull,
        ),
    )
    @test success(process)
end

@testset "same-source token multiplicity is retained without fabricated refs" begin
    rows = valid_inputs()
    index = record_index(rows, "origin_1", PANDEMIC)
    rows[index]["raw_tokens"] = ["PRE_PANDEMIC", "PRE_PANDEMIC"]
    rows[index]["evidence_refs"] = [
        "evidence:same-source",
        "evidence:same-source",
    ]
    document = build_regime_adjudication_ledger(
        "same.source.multiplicity.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )
    validated = validate_regime_adjudication_ledger(document)
    record = only(
        item for item in validated.records if
            item.observation_id == "origin_1" &&
            item.contrast_id == PANDEMIC
    )
    @test record.raw_tokens == ("PRE_PANDEMIC", "PRE_PANDEMIC")
    @test record.evidence_refs ==
        ("evidence:same-source", "evidence:same-source")
    inventory_rows = filter(
        item -> item.record_id == record.record_id,
        validated.raw_token_inventory,
    )
    @test Tuple(item.token_index for item in inventory_rows) == (1, 2)
    @test Tuple(item.raw_token for item in inventory_rows) ==
        ("PRE_PANDEMIC", "PRE_PANDEMIC")
    @test Tuple(item.evidence_ref for item in inventory_rows) ==
        ("evidence:same-source", "evidence:same-source")
end

@testset "duplicate identifiers and incomplete grids fail closed" begin
    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "duplicate.observations.v1",
        ["origin_1", "origin_1"],
        valid_inputs(),
    )

    rows = valid_inputs()
    rows[2]["record_id"] = rows[1]["record_id"]
    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "duplicate.records.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )

    rows = valid_inputs()
    rows[2]["observation_id"] = rows[1]["observation_id"]
    rows[2]["contrast_id"] = rows[1]["contrast_id"]
    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "duplicate.pairs.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )

    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "missing.grid.v1",
        ["origin_1", "origin_2", "origin_3"],
        valid_inputs()[1:(end - 1)],
    )

    rows = valid_inputs()
    rows[1]["observation_id"] = "origin_unregistered"
    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "unknown.observation.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )

    rows = valid_inputs()
    rows[1]["contrast_id"] = "UNKNOWN_CONTRAST"
    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "unknown.contrast.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )

    @test_throws RegimeAdjudicationError build_regime_adjudication_ledger(
        "Used",
        ["origin_1", "origin_2", "origin_3"],
        valid_inputs(),
    )
end

@testset "counts, masks, schema, and raw inventory are tamper evident" begin
    mutations = Function[
        document -> document["summary"]["record_count"] -= 1,
        document -> document["summary"]["accepted_count"] += 1,
        document -> document["summary"]["raw_token_count"] -= 1,
        document -> document["summary"][
            "affected_contrast_excluded_count",
        ] -= 1,
        document -> document["full_sample_primary_mask"][2] = false,
        document -> document["contrast_masks"][1]["inclusion_mask"][2] =
            true,
        document -> document["contrast_masks"][1]["included_count"] += 1,
        document -> pop!(document["contrast_masks"]),
        document -> pop!(document["raw_token_inventory"]),
        document -> document["raw_token_inventory"][1]["raw_token"] =
            "Other",
        document -> document["raw_token_inventory"][1]["evidence_ref"] =
            "evidence:wrong",
        document -> document["raw_token_inventory"][1]["sequence"] = 2,
        document -> document["records"][1]["raw_token_count"] = 2,
        document -> document["records"][1][
            "include_in_full_sample_primary",
        ] = false,
        document -> document["records"][4][
            "include_in_affected_regime_contrast",
        ] = true,
        document -> document["artifact"]["schema_version"] = "unknown.v2",
        document -> document["artifact"]["scoring_artifact"] = true,
        document -> document["protocol"]["affected_contrast_policy"] =
            "DROP_FROM_ALL_ANALYSES",
        document -> document["unexpected"] = true,
    ]
    for mutate! in mutations
        document = build_valid()
        mutate!(document)
        rehash!(document)
        @test_throws RegimeAdjudicationError validate_regime_adjudication_ledger(
            document,
        )
    end

    document = build_valid()
    document["records"][1]["raw_tokens"][1] = "Other"
    @test_throws RegimeAdjudicationError validate_regime_adjudication_ledger(
        document,
    )
end

@testset "builder copies raw tokens and validated return is immutable-shaped" begin
    token = ["PRE_PANDEMIC"]
    rows = valid_inputs()
    index = record_index(rows, "origin_1", PANDEMIC)
    rows[index]["raw_tokens"] = token
    rows[index]["evidence_refs"] = ["evidence:mutable-token"]
    document = build_regime_adjudication_ledger(
        "copied.tokens.v1",
        ["origin_1", "origin_2", "origin_3"],
        rows,
    )
    token[1] = "Other"
    validated = validate_regime_adjudication_ledger(document)
    @test validated.records[1].raw_tokens == ("PRE_PANDEMIC",)
    @test validated.observation_ids isa Tuple
    @test validated.contrast_masks isa Tuple
    @test validated.raw_token_inventory isa Tuple
    @test validated.records isa Tuple
end
