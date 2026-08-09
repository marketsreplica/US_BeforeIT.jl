using Test
using TOML

include(joinpath(@__DIR__, "USRealGDPBridgeDecompositionV1.jl"))
using .USRealGDPBridgeDecompositionV1

const Bridge = USRealGDPBridgeDecompositionV1
const REPO = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))

function bridge_error(f)
    try
        f()
        return nothing
    catch error
        error isa BridgeDecompositionError || rethrow()
        return error
    end
end

function copy_pinned_sources()
    document = TOML.parsefile(PROTOCOL_PATH)
    root = realpath(mktempdir())
    for source in document["sources"]
        destination = joinpath(root, source["path"])
        mkpath(dirname(destination))
        cp(joinpath(REPO, source["path"]), destination)
    end
    return root, document
end

function observation(period, level; kwargs...)
    return official_observation(;
        period,
        level_text = level,
        artifact_sha256 = repeat("a", 64),
        release_id = "r2026q2_advance",
        vintage_id = "2026-07-30T12:30:00Z",
        kwargs...,
    )
end

@testset "frozen protocol and source closure" begin
    document = validate_protocol()
    @test document["artifact"]["content_sha256"] ==
        "7bf5c554e466f9cf1fdb78574b84590f37a1cc7251e02a3cb69c7a18c3ed4bff"
    @test Bridge.protocol_content_sha256(document) ==
        document["artifact"]["content_sha256"]
    @test length(document["sources"]) == 15
    @test all(value -> value === false, values(document["gates"]))
    @test document["current_evidence"]["blocking_reasons"] == sort(
        document["current_evidence"]["blocking_reasons"],
    )

    restamped = deepcopy(document)
    restamped["current_evidence"]["official_concept_bridge"] = true
    restamped["artifact"]["content_sha256"] = Bridge.protocol_content_sha256(restamped)
    @test bridge_error(() -> Bridge._validate_protocol_semantics(restamped)) !== nothing

    root, copied = copy_pinned_sources()
    @test Bridge.validate_source_pins(copied, root)
    first_path = joinpath(root, copied["sources"][1]["path"])
    open(first_path, "a") do io
        write(io, "\n")
    end
    @test bridge_error(() -> Bridge.validate_source_pins(copied, root)) !== nothing

    root, copied = copy_pinned_sources()
    first_path = joinpath(root, copied["sources"][1]["path"])
    target = first_path * ".target"
    mv(first_path, target)
    symlink(target, first_path)
    @test bridge_error(() -> Bridge.validate_source_pins(copied, root)) !== nothing

    root, copied = copy_pinned_sources()
    first_path = joinpath(root, copied["sources"][1]["path"])
    target = first_path * ".hardlink"
    hardlink(first_path, target)
    @test bridge_error(() -> Bridge.validate_source_pins(copied, root)) !== nothing
end

@testset "official A191RX project transform" begin
    previous = observation("2026Q1", "100.000")
    current = observation("2026Q2", "101.500")
    result = official_project_log_growth(previous, current)
    @test result.period == "2026Q2"
    @test result.value_text == "5.955444997500"
    @test result.scaled_integer == 5_955_444_997_500
    @test result.scale == 12
    @test result.declared_identity_fields_equal
    @test !result.source_artifact_reopened
    @test !result.publisher_authenticated
    @test !result.origin_bound
    @test !result.bea_compounded_headline_formula_used
    @test result.source_level_tokens == ["100.000", "101.500"]

    scaled = official_project_log_growth(
        observation("2026Q1", "1000.00"),
        observation("2026Q2", "1015.00"),
    )
    @test scaled.value_text == result.value_text
    bea_headline = 100 * ((101.5 / 100.0)^4 - 1)
    @test !isapprox(parse(Float64, result.value_text), bea_headline; atol = 1.0e-6)

    @test bridge_error(() -> official_project_log_growth(previous, observation("2026Q3", "101.5"))) !== nothing
    @test bridge_error(() -> official_project_log_growth(previous, observation("2026Q2", "101.5"; release_id = "other"))) !== nothing
    @test bridge_error(() -> official_project_log_growth(previous, observation("2026Q2", "101.5"; vintage_id = "other"))) !== nothing
    @test bridge_error(() -> official_project_log_growth(previous, observation("2026Q2", "101.5"; artifact_sha256 = repeat("b", 64)))) !== nothing
    @test bridge_error(() -> observation("2026Q1", "0")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "-1")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "01.0")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "1e2")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "NaN")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "1234567890123456789.000")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "1.0000000")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "١.٠٠٠")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "100"; table_id = "T10105")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "100"; series_code = "A191RC")) !== nothing
    @test bridge_error(() -> observation("2026Q1", "100"; unit = "billions")) !== nothing
end

@testset "core3 identity alias" begin
    source = [1.0, -0.0, 3.25, nextfloat(4.0)]
    result = validate_core3_alias(
        join(["real", "gdp"], "_"),
        join(["real", "gdp", "growth"], "_"),
        source,
        copy(source),
    )
    @test result.mapping == "identity_alias_no_second_transformation"
    @test result.factor == 1
    @test result.bitwise_equal
    @test !result.official_origin_admissible

    changed = copy(source)
    changed[end] = nextfloat(changed[end])
    @test bridge_error(() -> validate_core3_alias("real_gdp", "real_gdp_growth", source, changed)) !== nothing
    @test bridge_error(() -> validate_core3_alias("real_gdp_level", "real_gdp_growth", source, source)) !== nothing
    @test bridge_error(() -> validate_core3_alias("real_gdp", "real_gdp", source, source)) !== nothing
    @test bridge_error(() -> validate_core3_alias("real_gdp", "real_gdp_growth", Float32.(source), Float32.(source))) !== nothing
    @test bridge_error(() -> validate_core3_alias(SubString("real_gdp", 1), "real_gdp_growth", source, source)) !== nothing
    @test bridge_error(() -> validate_core3_alias("real_gdp", "real_gdp_growth", source, [1.0, 0.0, 3.25, nextfloat(4.0)])) !== nothing
    @test bridge_error(() -> validate_core3_alias("real_gdp", "real_gdp_growth", [1.0, NaN], [1.0, NaN])) !== nothing
end

@testset "ABM measurement-basis decomposition" begin
    periods = ["2026Q1", "2026Q2", "2026Q3", "2026Q4", "2027Q1"]
    levels = [100.0, 101.0, 103.0, 102.0, 104.0]
    bases = [
        "model_implied_opening",
        "completed_post_step_flow",
        "completed_post_step_flow",
        "completed_post_step_flow",
        "completed_post_step_flow",
    ]
    horizons = qualify_abm_path(periods, levels, bases)
    @test length(horizons) == 4
    @test !horizons[1].same_completed_flow_basis
    @test !horizons[1].mechanical_growth_candidate
    @test all(item -> item.same_completed_flow_basis, horizons[2:4])
    @test all(item -> item.mechanical_growth_candidate, horizons[2:4])
    @test all(item -> !item.official_fisher_chain_bridge_validated, horizons)
    @test all(item -> !item.scoring_eligible, horizons)
    @test horizons[1].target_period == "2026Q2"
    @test horizons[4].target_period == "2027Q1"

    synthetic_same_basis = qualify_abm_path(
        periods,
        levels,
        fill("completed_post_step_flow", 5),
    )
    @test all(item -> item.same_completed_flow_basis, synthetic_same_basis)
    @test all(item -> !item.official_fisher_chain_bridge_validated, synthetic_same_basis)

    @test bridge_error(() -> qualify_abm_path(periods[1:4], levels, bases)) !== nothing
    @test bridge_error(() -> qualify_abm_path(["2026Q1", "2026Q3"], [1.0, 2.0], bases[1:2])) !== nothing
    @test bridge_error(() -> qualify_abm_path(periods, [100.0, 0.0, 1.0, 1.0, 1.0], bases)) !== nothing
    @test bridge_error(() -> qualify_abm_path(periods, [100.0, Inf, 1.0, 1.0, 1.0], bases)) !== nothing
    @test bridge_error(() -> qualify_abm_path(periods, levels, ["unknown"; bases[2:end]])) !== nothing
    @test bridge_error(() -> qualify_abm_path(SubString.(periods, 1), levels, bases)) !== nothing
    @test bridge_error(() -> qualify_abm_path(periods, Float32.(levels), bases)) !== nothing
end

@testset "source-rederived current assessment and action ceiling" begin
    result = current_assessment()
    @test result.status == "REAL_GDP_BRIDGE_DECOMPOSED_NONADMITTING"
    @test result.official_transform_mechanics
    @test result.core3_alias_mechanics
    @test !result.abm_h1_same_basis
    @test result.abm_h2_h4_same_basis
    @test !result.official_concept_bridge
    @test !result.historical_origin
    @test !result.operator_approved
    @test !result.bridge_truth_artifact_accessed
    @test !result.bridge_model_executed
    @test !result.bridge_forecast_emitted
    @test !result.bridge_score_emitted
    @test !result.bridge_origin_admitted
    @test !result.bridge_promotion_eligible
    @test !result.bridge_production_eligible
    @test canonical_sha256(result) ==
        "230186825885e003b406014a75079b3a965a0612eb70937b47a3e71894863969"
    @test canonical_sha256(result) == EXPECTED_RESULT_SHA256
    @test validate_result(result) == result

    forged = merge(result, (official_concept_bridge = true,))
    @test bridge_error(() -> validate_result(forged)) !== nothing
    forged = merge(result, (blocking_reasons = String[],))
    @test bridge_error(() -> validate_result(forged)) !== nothing
    for action in (
            :run_model,
            :load_truth,
            :emit_forecast,
            :score,
            :admit_origin,
            :approve_operator,
            :mutate_registry,
            :promote,
            :register_production,
        )
        @test bridge_error(() -> refuse_prohibited_action(action)) !== nothing
    end
    @test bridge_error(() -> refuse_prohibited_action(:unknown)) !== nothing

    source = read(joinpath(@__DIR__, "USRealGDPBridgeDecompositionV1.jl"), String)
    for forbidden in ("Downloads", "HTTP.", "include(", "run(", "Base.require", "eval(")
        @test !occursin(forbidden, source)
    end
end
