using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsValuationEnvelope.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsFinalUseEnvelope.jl"))
include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitionsProducerPriceAdapterCandidate.jl",
    ),
)
include(joinpath(@__DIR__, "USProductionReconciliationLedger.jl"))

using .USProductionReconciliationLedger

const LEDGER_CONTRACT_PATH =
    joinpath(@__DIR__, "production_reconciliation_candidate_ledger.toml")
const LEDGER_MODULE_PATH =
    joinpath(@__DIR__, "USProductionReconciliationLedger.jl")
const LEDGER_REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", ".."))

const LEDGER_NUMERIC_STATE = "SOURCE_NUMERIC"
const LEDGER_EXPLICIT_ZERO_STATE = "SOURCE_EXPLICIT_NUMERIC_ZERO"
const LEDGER_SELECTED_ZERO_STATE = "SOURCE_SELECTED_ZERO_NOT_SHOWN"
const LEDGER_DERIVED_ZERO_STATE = "DERIVED_EXACT_IDENTITY_ZERO"

function only_ledger_cell(report, cell_id)
    return only(cell for cell in report.cells if cell.cell_id == cell_id)
end

function ledger_cell_block(cell)
    parts = split(cell.cell_id, ':')
    length(parts) >= 2 || error("malformed cell id $(cell.cell_id)")
    return parts[2]
end

function replace_struct_field(value, field::Symbol, replacement)
    type = typeof(value)
    fields = fieldnames(type)
    field in fields || error("unknown field $field for $type")
    values = ntuple(
        index ->
        fields[index] == field ?
            replacement :
            getfield(value, fields[index]),
        fieldcount(type),
    )
    return type(values...)
end

function copy_ledger_bound_tree(
        temporary_root::AbstractString,
        contract,
    )
    relative_paths = String[
        artifact.relative_path for artifact in values(contract.artifacts)
    ]
    append!(
        relative_paths,
        [contract.module_path, contract.runner_path],
    )
    for relative_path in unique(relative_paths)
        destination = joinpath(temporary_root, relative_path)
        mkpath(dirname(destination))
        cp(
            joinpath(LEDGER_REPO_ROOT, relative_path),
            destination;
            force = true,
        )
    end
    return nothing
end

function captured_error(function_call)
    return try
        function_call()
        nothing
    catch error
        error
    end
end

@testset "WS-2C authenticated production reconciliation ledger" begin
    contract =
        USProductionReconciliationLedger.load_contract(LEDGER_CONTRACT_PATH)
    first_output_directory = mktempdir()
    first_written = write_production_reconciliation_ledger_report(
        first_output_directory,
        LEDGER_CONTRACT_PATH,
    )
    report = first_written.report

    @testset "Pinned contract and synthetic-free production schema" begin
        @test bytes2hex(SHA.sha256(read(LEDGER_CONTRACT_PATH))) ==
            APPROVED_CONTRACT_SHA256
        @test contract.source_sha256 == APPROVED_CONTRACT_SHA256
        @test contract.contract_id ==
            "us-ws2c-production-reconciliation-candidate-ledger-v1"
        @test contract.classification ==
            "CURRENT_VINTAGE_CANDIDATE_LEDGER_NOT_SOLVER_ADMITTED"
        @test contract.artifact_role ==
            "AUTHENTICATED_PRODUCTION_SCHEMA_AND_LINEAGE_CANDIDATE"
        @test contract.promotion_status == "RESEARCH_ONLY_NOT_PROMOTED"
        @test contract.problem_scope_hash ==
            "scope1:c5431dd4b2691fa29e57c35cbe8dc2b5e5a325fc2b637602df83d5399d142903"
        @test normalized_module_sha256(LEDGER_MODULE_PATH) ==
            contract.module_normalized_sha256
        @test collect(String.(fieldnames(ProductionCellRecord))) ==
            CELL_SCHEMA_FIELDS
        @test collect(String.(fieldnames(ProductionControlRecord))) ==
            CONTROL_SCHEMA_FIELDS
        @test Set(String.(fieldnames(SemanticOverlay))) == Set(
            [
                "overlay_id",
                "view_id",
                "owner_kind",
                "owner_id",
                "source_view_record_id",
                "annotation_kind",
                "annotation",
            ],
        )

        source = read(LEDGER_MODULE_PATH, String)
        for forbidden_symbol in (
                "StoneProblem",
                "LedgerCell",
                "truth_value",
                "benchmark_role",
                "reconcile_stone",
            )
            @test !occursin(forbidden_symbol, source)
        end
        @test !occursin(
            "USConstrainedStoneReconciliation.jl",
            source,
        )
        @test !("raw_value" in String.(fieldnames(SemanticOverlay)))
        @test !("value" in String.(fieldnames(SemanticOverlay)))
        @test !("weight" in String.(fieldnames(SemanticOverlay)))
    end

    @testset "Exact cell blocks, source states, and signs" begin
        @test report.schema_version ==
            "beforeit-us-production-reconciliation-candidate-ledger-report.v1"
        @test report.contract_sha256 == contract.source_sha256
        @test report.problem_scope_hash == contract.problem_scope_hash
        @test startswith(report.problem_hash, "problem1:")
        @test length(report.cells) == 17_422 ==
            contract.expected["candidate_cell_count"]
        @test length(unique(cell.cell_id for cell in report.cells)) ==
            length(report.cells)
        @test issorted(getfield.(report.cells, :cell_id))

        expected_block_stats = Dict(
            "PRODUCER_INTERMEDIATE_USE" => (
                total = 4_760,
                observed = 3_636,
                selected = 1_124,
                explicit_zero = 119,
                positive = 3_512,
                negative = 5,
            ),
            "PRODUCER_FINAL_USE" => (
                total = 1_400,
                observed = 348,
                selected = 1_052,
                explicit_zero = 9,
                positive = 278,
                negative = 61,
            ),
            "PRODUCER_VALUE_ADDED" => (
                total = 204,
                observed = 201,
                selected = 3,
                explicit_zero = 0,
                positive = 197,
                negative = 4,
            ),
            "PRODUCER_MAKE" => (
                total = 4_760,
                observed = 497,
                selected = 4_263,
                explicit_zero = 83,
                positive = 413,
                negative = 1,
            ),
            "COMMODITY_OUTPUT" => (
                total = 70,
                observed = 70,
                selected = 0,
                explicit_zero = 0,
                positive = 70,
                negative = 0,
            ),
            "INDUSTRY_OUTPUT" => (
                total = 68,
                observed = 68,
                selected = 0,
                explicit_zero = 0,
                positive = 68,
                negative = 0,
            ),
            "IMPORT_INTERMEDIATE_USE" => (
                total = 4_760,
                observed = 2_302,
                selected = 2_458,
                explicit_zero = 348,
                positive = 1_952,
                negative = 2,
            ),
            "IMPORT_FINAL_USE" => (
                total = 1_400,
                observed = 187,
                selected = 1_213,
                explicit_zero = 4,
                positive = 127,
                negative = 56,
            ),
        )
        @test Set(ledger_cell_block(cell) for cell in report.cells) ==
            Set(keys(expected_block_stats))
        for (block, expected) in expected_block_stats
            cells = filter(
                cell -> ledger_cell_block(cell) == block,
                report.cells,
            )
            @test length(cells) == expected.total
            @test count(cell -> cell.raw_value !== nothing, cells) ==
                expected.observed
            @test count(
                cell -> cell.cell_state == LEDGER_SELECTED_ZERO_STATE,
                cells,
            ) == expected.selected
            @test count(
                cell -> cell.cell_state == LEDGER_EXPLICIT_ZERO_STATE,
                cells,
            ) == expected.explicit_zero
            @test count(
                cell ->
                cell.raw_value !== nothing && cell.raw_value > 0.0,
                cells,
            ) == expected.positive
            @test count(
                cell ->
                cell.raw_value !== nothing && cell.raw_value < 0.0,
                cells,
            ) == expected.negative
        end

        @test count(
            cell -> cell.cell_state == LEDGER_NUMERIC_STATE,
            report.cells,
        ) == 6_746
        @test count(
            cell -> cell.cell_state == LEDGER_EXPLICIT_ZERO_STATE,
            report.cells,
        ) == 563
        @test count(
            cell -> cell.cell_state == LEDGER_SELECTED_ZERO_STATE,
            report.cells,
        ) == 10_113
        @test all(
            cell.raw_value === nothing
                for cell in report.cells
                if cell.cell_state == LEDGER_SELECTED_ZERO_STATE
        )
        @test all(
            cell.raw_value == 0.0
                for cell in report.cells
                if cell.cell_state == LEDGER_EXPLICIT_ZERO_STATE
        )
        @test count(
            cell ->
            cell.raw_value !== nothing && cell.raw_value < 0.0,
            report.cells,
        ) == 129
        @test length(report.unresolved_negative_cell_ids) == 23
        @test count(
            cell ->
            cell.raw_value !== nothing &&
                cell.raw_value < 0.0 &&
                !startswith(cell.negative_economic_type, "UNRESOLVED_"),
            report.cells,
        ) == 106
        @test count(
            cell ->
            ledger_cell_block(cell) == "PRODUCER_FINAL_USE" &&
                cell.column_code == "F030" &&
                cell.raw_value !== nothing &&
                cell.raw_value < 0.0,
            report.cells,
        ) == 7
        @test count(
            cell ->
            ledger_cell_block(cell) == "PRODUCER_FINAL_USE" &&
                cell.column_code == "F050" &&
                cell.raw_value !== nothing &&
                cell.raw_value < 0.0,
            report.cells,
        ) == 47
        @test count(
            cell ->
            ledger_cell_block(cell) == "PRODUCER_VALUE_ADDED" &&
                cell.row_code == "V002" &&
                cell.raw_value !== nothing &&
                cell.raw_value < 0.0,
            report.cells,
        ) == 4
        @test count(
            cell ->
            ledger_cell_block(cell) == "IMPORT_FINAL_USE" &&
                cell.column_code == "F050" &&
                cell.raw_value !== nothing &&
                cell.raw_value < 0.0,
            report.cells,
        ) == 48

        selected_f030 = only_ledger_cell(
            report,
            "AR24:PRODUCER_FINAL_USE:CORE:4A0:F030",
        )
        used_f030 = only_ledger_cell(
            report,
            "AR24:PRODUCER_FINAL_USE:CLOSURE:Used:F030",
        )
        other_f030 = only_ledger_cell(
            report,
            "AR24:PRODUCER_FINAL_USE:CLOSURE:Other:F030",
        )
        explicit_zero_f02r = only_ledger_cell(
            report,
            "AR24:PRODUCER_FINAL_USE:CORE:334:F02R",
        )
        @test selected_f030.cell_state == LEDGER_SELECTED_ZERO_STATE
        @test selected_f030.raw_value === nothing
        @test used_f030.cell_state == LEDGER_NUMERIC_STATE
        @test used_f030.raw_value == 9_450.0
        @test other_f030.cell_state == LEDGER_SELECTED_ZERO_STATE
        @test other_f030.raw_value === nothing
        @test explicit_zero_f02r.cell_state ==
            LEDGER_EXPLICIT_ZERO_STATE
        @test explicit_zero_f02r.raw_value == 0.0
    end

    @testset "Canonical raw and aggregate lineage" begin
        @test length(report.source_lineage_members) == 19_428
        @test length(report.target_lineages) == 17_422
        @test length(
            unique(
                member.canonical_source_key
                    for member in report.source_lineage_members
            ),
        ) == 19_428
        @test length(
            unique(
                member.lineage_hash
                    for member in report.source_lineage_members
            ),
        ) == 19_428
        @test all(
            startswith(member.canonical_source_key, "csk1:")
                for member in report.source_lineage_members
        )
        @test all(
            startswith(member.lineage_hash, "lin1:")
                for member in report.source_lineage_members
        )

        expected_projection_lineage = Dict(
            "producer_intermediate_use_2024" => (
                count = 5_183,
                sha256 =
                    "4a8b361fc8c635602df6cedd0f3d7e728933105e37eaddbebabc8ce1925173f4",
            ),
            "producer_final_use_2024" => (
                count = 1_460,
                sha256 =
                    "205d6c126efc27ba07e89b262e27f81f9bcb7200d679ce039a5aaa7a889e6fbb",
            ),
            "producer_value_added_2024" => (
                count = 213,
                sha256 =
                    "81cd3d1443357f1fad597bd329616deaabc15b435960ca2354ad4a8d047e20bb",
            ),
            "producer_make_2024" => (
                count = 5_183,
                sha256 =
                    "5c80053d4e1803e05f5ad597daa4f7511e6ab68e4b07c45e48678c09ed8c63d4",
            ),
            "producer_make_commodity_output_2024" => (
                count = 73,
                sha256 =
                    "012e85bbb74764355347c4c556a70d34f1385effef21577a2abdda86c34d2833",
            ),
            "producer_make_industry_output_2024" => (
                count = 71,
                sha256 =
                    "9ce864bb432c097172e22f735ab6c659eff9a2d91f34ce6803aea0545de368e0",
            ),
            "import_intermediate_use_2024" => (
                count = 5_183,
                sha256 =
                    "36151c03db3c3c33fc170324c4ef19805aade5be7f7655b3ea5ff3c91a198443",
            ),
            "import_final_use_2024" => (
                count = 1_460,
                sha256 =
                    "fc9880daed7aafe40c804f969cc6d61c1d08d5d8ed6613ed8bd657fd8d834224",
            ),
            "producer_use_commodity_controls_2024" => (
                count = 219,
                sha256 =
                    "ef577965059370abc16db5b339dc357ababe37e52c25b0d1a36c32046db95a6e",
            ),
            "producer_use_industry_controls_2024" => (
                count = 213,
                sha256 =
                    "efdd23571e57016a1234bf0ddf6924c16a763b626aac8f6ccd16e4acce04d54b",
            ),
            "producer_use_grand_controls_2024" => (
                count = 23,
                sha256 =
                    "58bfe4bda5de0d8725d25ad148dea197cd6a4eb724c1a47e4e6e0da481fbfeef",
            ),
            "producer_make_grand_output_2024" => (
                count = 1,
                sha256 =
                    "40e681ab0dd8c8461dcbbcc5b885649fb816db9d0fefdc9d1b8459a739d21cf9",
            ),
            "import_commodity_controls_2024" => (
                count = 146,
                sha256 =
                    "4cb90198a12d4d3587aabb3a4f8fe0da6a9e34606dcce5344412e49da603b5cb",
            ),
        )
        @test Set(
            member.projection_id for member in report.source_lineage_members
        ) == Set(keys(expected_projection_lineage))
        for (projection_id, expected) in expected_projection_lineage
            members = filter(
                member -> member.projection_id == projection_id,
                report.source_lineage_members,
            )
            @test length(members) == expected.count
            @test Set(member.projection_sha256 for member in members) ==
                Set([expected.sha256])
        end

        source_key_set = Set(
            member.canonical_source_key
                for member in report.source_lineage_members
        )
        parent_keys = reduce(
            vcat,
            (
                lineage.parent_source_keys
                    for lineage in report.target_lineages
            );
            init = String[],
        )
        @test length(parent_keys) == 18_826
        @test length(unique(parent_keys)) == 18_826
        @test issubset(Set(parent_keys), source_key_set)
        control_parent_keys = reduce(
            vcat,
            (
                lineage.parent_source_keys
                    for lineage in report.control_lineages
                    if !isempty(lineage.parent_source_keys)
            );
            init = String[],
        )
        @test length(control_parent_keys) == 602
        @test length(unique(control_parent_keys)) == 602
        @test isempty(
            intersect(Set(parent_keys), Set(control_parent_keys)),
        )
        @test union(
            Set(parent_keys),
            Set(control_parent_keys),
        ) == source_key_set
        @test count(
            lineage -> length(lineage.parent_source_keys) > 1,
            report.target_lineages,
        ) == 456
        @test all(
            length(lineage.parent_source_keys) ==
                length(lineage.parent_lineage_hashes)
                for lineage in report.target_lineages
        )
        @test all(
            issorted(lineage.parent_source_keys)
                for lineage in report.target_lineages
        )
        @test all(
            lineage.canonical_source_key ==
                only(lineage.parent_source_keys) &&
                lineage.lineage_hash ==
                only(lineage.parent_lineage_hashes)
                for lineage in report.target_lineages
                if length(lineage.parent_source_keys) == 1
        )
        four_by_four = only(
            lineage
                for lineage in report.target_lineages
                if lineage.owner_id ==
                "AR24:PRODUCER_INTERMEDIATE_USE:CORE:4A0:4A0"
        )
        @test length(four_by_four.parent_source_keys) == 16

        source =
            USProductionReconciliationLedger.load_projections(contract)
        projection =
            source.projections["producer_intermediate_use_2024"]
        original_raw = first(
            raw
                for raw in values(projection.cells)
                if raw.source_cell_kind == "numeric" &&
                raw.value != 0.0
        )
        changed_raw = USProductionReconciliationLedger.RawCell(
            original_raw.projection_id,
            original_raw.year,
            original_raw.row_position,
            original_raw.row_code,
            original_raw.row_type,
            original_raw.column_position,
            original_raw.column_code,
            original_raw.column_type,
            original_raw.value + 1.0,
            original_raw.source_cell_kind,
        )
        original_key = USProductionReconciliationLedger.raw_source_key(
            original_raw,
            projection,
        )
        @test USProductionReconciliationLedger.raw_source_key(
            changed_raw,
            projection,
        ) == original_key
        @test USProductionReconciliationLedger.raw_lineage_hash(
            original_key,
            changed_raw,
            projection,
            contract,
        ) !=
            USProductionReconciliationLedger.raw_lineage_hash(
            original_key,
            original_raw,
            projection,
            contract,
        )

        all_source_members =
            USProductionReconciliationLedger.build_raw_members(
            source.projections,
            contract,
        )
        member_by_key = Dict(
            member.canonical_source_key => member
                for member in values(all_source_members)
        )
        aggregate_parents = [
            member_by_key[key] for key in four_by_four.parent_source_keys
        ]
        direct_lineage = USProductionReconciliationLedger.target_lineage(
            four_by_four.owner_id,
            aggregate_parents,
            four_by_four.transformation_id,
            contract,
        )
        reversed_lineage =
            USProductionReconciliationLedger.target_lineage(
            four_by_four.owner_id,
            reverse(aggregate_parents),
            four_by_four.transformation_id,
            contract,
        )
        @test direct_lineage.canonical_source_key ==
            four_by_four.canonical_source_key
        @test direct_lineage.lineage_hash == four_by_four.lineage_hash
        @test reversed_lineage.canonical_source_key ==
            direct_lineage.canonical_source_key
        @test reversed_lineage.lineage_hash == direct_lineage.lineage_hash
        @test reversed_lineage.parent_source_keys ==
            direct_lineage.parent_source_keys
        duplicate_target_parent_error = captured_error(
            () -> USProductionReconciliationLedger.target_lineage(
                four_by_four.owner_id,
                [aggregate_parents[1], aggregate_parents[1]],
                four_by_four.transformation_id,
                contract,
            ),
        )
        @test duplicate_target_parent_error isa
            ProductionLedgerContractError
        @test occursin(
            "duplicate parent",
            duplicate_target_parent_error.detail,
        )

        changed_target_parent_index = findfirst(
            parent -> parent.source_cell_state == LEDGER_NUMERIC_STATE,
            aggregate_parents,
        )
        @test changed_target_parent_index !== nothing
        original_target_parent =
            aggregate_parents[changed_target_parent_index]
        target_parent_projection =
            source.projections[original_target_parent.projection_id]
        target_parent_raw = target_parent_projection.cells[
            (
                original_target_parent.row_code,
                original_target_parent.column_code,
            ),
        ]
        changed_target_raw =
            USProductionReconciliationLedger.RawCell(
            target_parent_raw.projection_id,
            target_parent_raw.year,
            target_parent_raw.row_position,
            target_parent_raw.row_code,
            target_parent_raw.row_type,
            target_parent_raw.column_position,
            target_parent_raw.column_code,
            target_parent_raw.column_type,
            target_parent_raw.value + 1.0,
            target_parent_raw.source_cell_kind,
        )
        changed_target_parent =
            USProductionReconciliationLedger.source_member(
            changed_target_raw,
            target_parent_projection,
            contract,
        )
        changed_target_parents = copy(aggregate_parents)
        changed_target_parents[changed_target_parent_index] =
            changed_target_parent
        value_changed_lineage =
            USProductionReconciliationLedger.target_lineage(
            four_by_four.owner_id,
            changed_target_parents,
            four_by_four.transformation_id,
            contract,
        )
        @test value_changed_lineage.canonical_source_key ==
            direct_lineage.canonical_source_key
        @test value_changed_lineage.lineage_hash !=
            direct_lineage.lineage_hash

        published_lineage = first(
            lineage
                for lineage in report.control_lineages
                if length(lineage.parent_source_keys) > 1 &&
                any(
                    member_by_key[key].source_cell_state ==
                    LEDGER_NUMERIC_STATE
                    for key in lineage.parent_source_keys
                )
        )
        published_parents = [
            member_by_key[key]
                for key in published_lineage.parent_source_keys
        ]
        direct_control_lineage =
            USProductionReconciliationLedger.control_key_and_hash(
            published_lineage.owner_id,
            published_parents,
            published_lineage.transformation_id,
            contract,
        )
        reversed_control_lineage =
            USProductionReconciliationLedger.control_key_and_hash(
            published_lineage.owner_id,
            reverse(published_parents),
            published_lineage.transformation_id,
            contract,
        )
        @test direct_control_lineage == reversed_control_lineage
        @test direct_control_lineage[1] ==
            published_lineage.canonical_control_key
        @test direct_control_lineage[2] ==
            published_lineage.lineage_hash
        duplicate_control_parent_error = captured_error(
            () -> USProductionReconciliationLedger.control_key_and_hash(
                published_lineage.owner_id,
                [published_parents[1], published_parents[1]],
                published_lineage.transformation_id,
                contract,
            ),
        )
        @test duplicate_control_parent_error isa
            ProductionLedgerContractError
        @test occursin(
            "duplicate parent",
            duplicate_control_parent_error.detail,
        )

        changed_control_parent_index = findfirst(
            parent -> parent.source_cell_state == LEDGER_NUMERIC_STATE,
            published_parents,
        )
        @test changed_control_parent_index !== nothing
        original_control_parent =
            published_parents[changed_control_parent_index]
        control_parent_projection =
            source.projections[original_control_parent.projection_id]
        control_parent_raw = control_parent_projection.cells[
            (
                original_control_parent.row_code,
                original_control_parent.column_code,
            ),
        ]
        changed_control_raw =
            USProductionReconciliationLedger.RawCell(
            control_parent_raw.projection_id,
            control_parent_raw.year,
            control_parent_raw.row_position,
            control_parent_raw.row_code,
            control_parent_raw.row_type,
            control_parent_raw.column_position,
            control_parent_raw.column_code,
            control_parent_raw.column_type,
            control_parent_raw.value + 1.0,
            control_parent_raw.source_cell_kind,
        )
        changed_control_parent =
            USProductionReconciliationLedger.source_member(
            changed_control_raw,
            control_parent_projection,
            contract,
        )
        changed_control_parents = copy(published_parents)
        changed_control_parents[changed_control_parent_index] =
            changed_control_parent
        value_changed_control_lineage =
            USProductionReconciliationLedger.control_key_and_hash(
            published_lineage.owner_id,
            changed_control_parents,
            published_lineage.transformation_id,
            contract,
        )
        @test value_changed_control_lineage[1] ==
            direct_control_lineage[1]
        @test value_changed_control_lineage[2] !=
            direct_control_lineage[2]
    end

    @testset "Candidate controls and lineage relations" begin
        @test length(report.controls) == 924
        @test length(report.control_lineages) == 924
        @test issorted(getfield.(report.controls, :control_id))
        @test length(unique(control.control_id for control in report.controls)) ==
            924
        @test length(
            unique(
                control.canonical_control_key
                    for control in report.controls
            ),
        ) == 924
        @test length(
            unique(control.lineage_hash for control in report.controls),
        ) == 924

        identities = filter(
            control ->
            control.control_kind == "EXACT_ACCOUNTING_IDENTITY",
            report.controls,
        )
        margins = filter(
            control ->
            control.control_kind == "MEASURED_PUBLISHED_MARGIN",
            report.controls,
        )
        @test length(identities) == 346
        @test sum(
            length(control.term_cell_ids) for control in identities
        ) == 27_080
        @test contract.expected[
            "candidate_identity_structural_rank",
        ] == 346
        @test USProductionReconciliationLedger.identity_structural_rank(
            report.controls,
        ) == 346
        @test all(control.rhs == 0.0 for control in identities)
        @test all(
            control.rhs_state == LEDGER_DERIVED_ZERO_STATE
                for control in identities
        )
        @test all(
            control.fixed_status ==
                "CANDIDATE_UNAPPROVED_NOT_SOLVER_ADMITTED"
                for control in identities
        )
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:IDENTITY:COMMODITY_USE:",
            ),
            identities,
        ) == 70
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:IDENTITY:COMMODITY_MAKE:",
            ),
            identities,
        ) == 70
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:IDENTITY:INDUSTRY_USE:",
            ),
            identities,
        ) == 68
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:IDENTITY:INDUSTRY_MAKE:",
            ),
            identities,
        ) == 68
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:IDENTITY:IMPORT_ALLOCATION:",
            ),
            identities,
        ) == 70

        @test length(margins) == 578
        @test count(control -> control.rhs !== nothing, margins) == 527
        @test count(
            control ->
            control.rhs_state == LEDGER_SELECTED_ZERO_STATE,
            margins,
        ) == 51
        @test all(
            control.fixed_status == "NOT_APPROVED_NOT_SOLVER_ADMITTED"
                for control in margins
        )
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:CONTROL:PRODUCER_USE_COMMODITY:",
            ),
            margins,
        ) == 210
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:CONTROL:PRODUCER_USE_INDUSTRY:",
            ),
            margins,
        ) == 204
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:CONTROL:PRODUCER_USE_GRAND:",
            ),
            margins,
        ) == 23
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:CONTROL:PRODUCER_MAKE_GRAND:",
            ),
            margins,
        ) == 1
        @test count(
            control ->
            startswith(
                control.control_id,
                "AR24:CONTROL:IMPORT_COMMODITY:",
            ),
            margins,
        ) == 140

        cell_ids = Set(cell.cell_id for cell in report.cells)
        @test all(
            length(control.term_cell_ids) ==
                length(control.coefficients)
                for control in report.controls
        )
        @test all(
            all(term_id in cell_ids for term_id in control.term_cell_ids)
                for control in report.controls
        )
        @test all(
            length(unique(control.term_cell_ids)) ==
                length(control.term_cell_ids)
                for control in report.controls
        )
        @test all(
            all(
                    coefficient != 0.0 && isfinite(coefficient)
                    for coefficient in control.coefficients
                )
                for control in report.controls
        )
        control_map = Dict(
            control.control_id => control for control in report.controls
        )
        @test Set(
            lineage.owner_id for lineage in report.control_lineages
        ) == Set(keys(control_map))
        @test all(
            lineage.canonical_control_key ==
                control_map[lineage.owner_id].canonical_control_key &&
                lineage.lineage_hash ==
                control_map[lineage.owner_id].lineage_hash &&
                lineage.term_cell_ids ==
                control_map[lineage.owner_id].term_cell_ids
                for lineage in report.control_lineages
        )
        @test sum(
            length(lineage.parent_source_keys)
                for lineage in report.control_lineages
        ) == 602

        @test length(report.relations) == 925
        @test length(
            unique(relation.relation_id for relation in report.relations),
        ) == 925
        @test all(
            relation.solver_weight_contribution == 0
                for relation in report.relations
        )
        common_estimand = only(
            relation
                for relation in report.relations
                if relation.relation_id ==
                "RELATION:F030_IO_CONTROL_TO_T10105_2024_SUM"
        )
        @test common_estimand.relation_kind ==
            "COMMON_ESTIMAND_INDEPENDENCE_UNRESOLVED"
        @test common_estimand.independence_status ==
            "DISTINCT_SOURCE_LINEAGE_EQUAL_ESTIMAND_NOT_INDEPENDENCE"
    end

    @testset "Value-free F030 and Used/Other overlays" begin
        @test length(report.overlays) == 588
        @test length(unique(overlay.overlay_id for overlay in report.overlays)) ==
            588
        @test issorted(getfield.(report.overlays, :overlay_id))
        f030_overlays = filter(
            overlay ->
            overlay.annotation_kind == "ANNUAL_INVENTORY_FLOW_VIEW",
            report.overlays,
        )
        used_other_overlays = filter(
            overlay ->
            overlay.annotation_kind == "USED_OTHER_2024_SOURCE_VIEW",
            report.overlays,
        )
        @test length(f030_overlays) == 70
        @test length(used_other_overlays) == 518
        @test length(unique(overlay.owner_id for overlay in report.overlays)) ==
            568
        @test count(
            overlay -> overlay.owner_kind == "CONTROL",
            used_other_overlays,
        ) == 10
        @test count(
            overlay -> overlay.owner_kind == "CELL",
            used_other_overlays,
        ) == 508
        @test length(
            intersect(
                Set(overlay.owner_id for overlay in f030_overlays),
                Set(overlay.owner_id for overlay in used_other_overlays),
            ),
        ) == 2
        @test all(
            overlay.owner_kind in ("CELL", "CONTROL")
                for overlay in report.overlays
        )
        @test all(
            occursin("no copied", lowercase(overlay.annotation)) ||
                occursin("no component", lowercase(overlay.annotation))
                for overlay in report.overlays
        )
    end

    @testset "Fail-closed internal, source-aware, and solver boundaries" begin
        @test production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )

        baseline_problem_hash =
            USProductionReconciliationLedger.ledger_problem_hash(
            report.cells,
            report.controls,
            report.source_lineage_members,
            report.target_lineages,
            report.control_lineages,
            report.overlays,
            report.relations,
            report.problem_scope_hash,
        )
        @test baseline_problem_hash == report.problem_hash

        target_lineage_index = findfirst(
            lineage -> length(lineage.parent_source_keys) > 1,
            report.target_lineages,
        )
        @test target_lineage_index !== nothing
        original_target_lineage =
            report.target_lineages[target_lineage_index]
        changed_target_lineage = replace_struct_field(
            original_target_lineage,
            :transformation_id,
            original_target_lineage.transformation_id * "_MUTATED",
        )
        changed_target_lineages = copy(report.target_lineages)
        changed_target_lineages[target_lineage_index] =
            changed_target_lineage
        @test USProductionReconciliationLedger.ledger_problem_hash(
            report.cells,
            report.controls,
            report.source_lineage_members,
            changed_target_lineages,
            report.control_lineages,
            report.overlays,
            report.relations,
            report.problem_scope_hash,
        ) != baseline_problem_hash
        report.target_lineages[target_lineage_index] =
            changed_target_lineage
        @test !production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )
        report.target_lineages[target_lineage_index] =
            original_target_lineage

        control_lineage_index = findfirst(
            lineage -> !isempty(lineage.parent_source_keys),
            report.control_lineages,
        )
        @test control_lineage_index !== nothing
        original_control_lineage =
            report.control_lineages[control_lineage_index]
        changed_control_lineage = replace_struct_field(
            original_control_lineage,
            :transformation_id,
            original_control_lineage.transformation_id * "_MUTATED",
        )
        changed_control_lineages = copy(report.control_lineages)
        changed_control_lineages[control_lineage_index] =
            changed_control_lineage
        @test USProductionReconciliationLedger.ledger_problem_hash(
            report.cells,
            report.controls,
            report.source_lineage_members,
            report.target_lineages,
            changed_control_lineages,
            report.overlays,
            report.relations,
            report.problem_scope_hash,
        ) != baseline_problem_hash
        report.control_lineages[control_lineage_index] =
            changed_control_lineage
        @test !production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )
        report.control_lineages[control_lineage_index] =
            original_control_lineage
        @test production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )

        original_member = report.source_lineage_members[2]
        report.source_lineage_members[2] =
            report.source_lineage_members[1]
        @test !production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )
        report.source_lineage_members[2] = original_member
        @test production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )

        numeric_index = findfirst(
            cell ->
            cell.cell_state == LEDGER_NUMERIC_STATE &&
                cell.raw_value !== nothing &&
                cell.raw_value > 0.0,
            report.cells,
        )
        @test numeric_index !== nothing
        original_cell = report.cells[numeric_index]
        report.cells[numeric_index] = replace_struct_field(
            original_cell,
            :raw_value,
            original_cell.raw_value + 1.0,
        )
        @test !production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )
        @test !production_reconciliation_ledger_source_controls_pass(
            report,
            LEDGER_CONTRACT_PATH,
        )
        report.cells[numeric_index] = original_cell
        @test production_reconciliation_ledger_internal_controls_pass(
            report,
            contract,
        )

        blocked_error = captured_error(
            () -> materialize_production_reconciliation_solver_input(report),
        )
        @test blocked_error isa ProductionSolverBlockedError
        @test blocked_error.blocker_ids == sort(contract.promotion_blockers)
        @test occursin(
            "production solver materialization is blocked",
            sprint(showerror, blocked_error),
        )
        @test report.solver_invocation_count == 0
        @test report.solver_input_cell_count == 0
        @test report.solver_input_control_count == 0
        @test report.approved_exact_control_count == 0
        @test report.approved_structural_zero_count == 0
        @test report.adjustment_record_count == 0
        @test !report.forecast_origin_admissible
        @test !report.promotion_ready
        @test !report.model_state_write
        @test report.accounting_gate_effect == "NONE"
        @test report.forecast_score_effect == "NONE"
    end

    @testset "Deterministic, self-describing report bytes" begin
        second_output_directory = mktempdir()
        second_written = write_production_reconciliation_ledger_report(
            second_output_directory,
            LEDGER_CONTRACT_PATH,
        )
        expected_filenames = [
            "control_lineages.csv",
            "lineage_relations.csv",
            "production_candidate_manifest.toml",
            "production_candidate_status.toml",
            "production_cells.csv",
            "production_controls.csv",
            "semantic_overlays.csv",
            "source_lineage_members.csv",
            "target_lineages.csv",
        ]
        @test sort(readdir(first_output_directory)) == expected_filenames
        @test sort(readdir(second_output_directory)) == expected_filenames
        for filename in expected_filenames
            @test read(joinpath(first_output_directory, filename)) ==
                read(joinpath(second_output_directory, filename))
        end
        @test first_written.report.problem_hash ==
            second_written.report.problem_hash
        @test first_written.cell_sha256 == second_written.cell_sha256
        @test first_written.control_sha256 ==
            second_written.control_sha256
        @test first_written.source_lineage_sha256 ==
            second_written.source_lineage_sha256
        @test first_written.target_lineage_sha256 ==
            second_written.target_lineage_sha256
        @test first_written.control_lineage_sha256 ==
            second_written.control_lineage_sha256
        @test first_written.overlay_sha256 ==
            second_written.overlay_sha256
        @test first_written.relation_sha256 ==
            second_written.relation_sha256
        @test first_written.status_sha256 == second_written.status_sha256
        @test first_written.manifest_sha256 ==
            second_written.manifest_sha256

        @test first(
            readlines(first_written.cell_path),
        ) == join(CELL_SCHEMA_FIELDS, ",")
        @test first(
            readlines(first_written.control_path),
        ) == join(CONTROL_SCHEMA_FIELDS, ",")
        @test first(
            readlines(first_written.control_lineage_path),
        ) == join(String.(fieldnames(ControlLineage)), ",")
        status = TOML.parsefile(first_written.status_path)
        @test status["candidate_cell_count"] == 17_422
        @test status["source_lineage_member_count"] == 19_428
        @test status["target_raw_source_leaf_count"] == 18_826
        @test status["control_raw_source_leaf_count"] == 602
        @test status["target_lineage_count"] == 17_422
        @test status["candidate_control_count"] == 924
        @test status["control_lineage_count"] == 924
        @test status["candidate_identity_count"] == 346
        @test status["candidate_identity_structural_rank"] == 346
        @test status["published_control_count"] == 578
        @test status["overlay_count"] == 588
        @test status["lineage_relation_count"] == 925
        @test status["solver_invocation_count"] == 0
        @test status["solver_input_cell_count"] == 0
        @test status["solver_input_control_count"] == 0
        @test !status["forecast_origin_admissible"]
        @test !status["promotion_ready"]
        @test !status["model_state_write"]
        manifest = TOML.parsefile(first_written.manifest_path)
        @test manifest["problem_hash"] == report.problem_hash
        @test manifest["contract_sha256"] == contract.source_sha256
        @test manifest["solver_invocation_count"] == 0
        @test !manifest["forecast_origin_admissible"]
        @test !manifest["promotion_ready"]
        @test length(manifest["output"]) == 8
    end

    @testset "Contract, artifact hash, and symlink rejection" begin
        changed_contract_directory = mktempdir()
        changed_contract_path =
            joinpath(changed_contract_directory, "changed_contract.toml")
        cp(LEDGER_CONTRACT_PATH, changed_contract_path)
        open(changed_contract_path, "a") do io
            println(io)
        end
        changed_contract_error = captured_error(
            () -> USProductionReconciliationLedger.load_contract(
                changed_contract_path,
            ),
        )
        @test changed_contract_error isa ProductionLedgerContractError
        @test changed_contract_error.location == "contract.sha256"

        contract_link_path =
            joinpath(mktempdir(), "contract-link.toml")
        symlink(LEDGER_CONTRACT_PATH, contract_link_path)
        contract_link_error = captured_error(
            () -> USProductionReconciliationLedger.load_contract(
                contract_link_path,
            ),
        )
        @test contract_link_error isa ProductionLedgerContractError
        @test contract_link_error.location == "contract.path"

        copied_root = mktempdir()
        copy_ledger_bound_tree(copied_root, contract)
        copied_artifact = joinpath(
            copied_root,
            contract.artifacts["after_redefinitions_cells"].relative_path,
        )
        open(copied_artifact, "a") do io
            println(io)
        end
        artifact_hash_error = captured_error(
            () -> USProductionReconciliationLedger.load_contract(
                LEDGER_CONTRACT_PATH;
                repo_root = copied_root,
            ),
        )
        @test artifact_hash_error isa ProductionLedgerContractError
        @test occursin(".sha256", artifact_hash_error.location)
        @test occursin("expected", artifact_hash_error.detail)
        cp(
            joinpath(
                LEDGER_REPO_ROOT,
                contract.artifacts[
                    "after_redefinitions_cells",
                ].relative_path,
            ),
            copied_artifact;
            force = true,
        )
        real_artifact = copied_artifact * ".real"
        cp(copied_artifact, real_artifact)
        rm(copied_artifact)
        symlink(real_artifact, copied_artifact)
        artifact_link_error = captured_error(
            () -> USProductionReconciliationLedger.load_contract(
                LEDGER_CONTRACT_PATH;
                repo_root = copied_root,
            ),
        )
        @test artifact_link_error isa ProductionLedgerContractError
        @test occursin(
            ".path",
            artifact_link_error.location,
        )
        @test occursin(
            "symbolic links are prohibited",
            artifact_link_error.detail,
        )
    end
end
