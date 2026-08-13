using SHA
using Test
using TOML

include("USABMGDPOperatorQualification.jl")
using .USABMGDPOperatorQualification

const GDP = USABMGDPOperatorQualification
const REPO_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))

function fixture()
    periods = ["2025Q4", "2026Q1", "2026Q2", "2026Q3", "2026Q4"]
    path_ids = [1, 2, 3]
    real = [
        100.0 90.0 120.0
        101.0 92.0 119.0
        103.0 95.0 121.0
        102.0 96.0 124.0
        105.0 98.0 128.0
    ]
    deflator = [
        1.0 1.1 0.95
        1.01 1.11 0.96
        1.03 1.12 0.97
        1.04 1.15 0.99
        1.06 1.16 1.0
    ]
    nominal = real .* deflator
    return (; periods, path_ids, real, nominal, deflator)
end

function compute(f = fixture(); kwargs...)
    options = Dict{Symbol, Any}(
        :fixture_class => "SYNTHETIC_OPERATOR_TEST_FIXTURE",
        :fixture_id => "synthetic-gdp-operator-v1",
        :path_kind => "RAW_MODEL_UNCORRECTED_SYNTHETIC",
        :truth_accessed => false,
        :empirical_path => false,
        :class_h_used => false,
        :bridge_adjusted => false,
        :origin_reanchored => false,
    )
    merge!(options, Dict(kwargs))
    return compute_synthetic_operators(
        f.periods,
        f.path_ids,
        f.real,
        f.nominal;
        options...,
    )
end

@testset "frozen protocol and source pins" begin
    protocol = validate_protocol()
    @test protocol.sha256 == bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    @test protocol.document["qualification_status"] ==
        "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
    @test protocol.document["historical_identity_validation_status"] ==
        "NOT_RUN"
    @test protocol.document["official_concept_validation_status"] ==
        "NOT_RUN"
    @test protocol.document["operator_count"] == 2
    @test getindex.(protocol.document["operators"], "target_id") ==
        ["real_gdp", "gdp_deflator"]
    @test all(
        operator["concept_bridge_status"] == "PENDING_VALIDATION"
            for operator in protocol.document["operators"]
    )
    @test protocol.document["declarations"]["synthetic_fixture_only"] ===
        true
    @test all(
        protocol.document["declarations"][key] === false
            for key in keys(protocol.document["declarations"])
            if key ∉ ("synthetic_fixture_only", "raw_model_only")
    )
    @test protocol.document["declarations"]["raw_model_only"] === true
    @test validate_source_pins()

    document = TOML.parsefile(PROTOCOL_PATH)
    changed = deepcopy(document)
    changed["qualification_status"] = "APPROVED"
    @test_throws GDPOperatorQualificationError validate_protocol_semantics(
        changed,
    )
    changed = deepcopy(document)
    changed["operators"][1]["formula"] = "100*(x_t/x_tm1-1)"
    @test_throws GDPOperatorQualificationError validate_protocol_semantics(
        changed,
    )
    changed = deepcopy(document)
    changed["operators"][2]["forbidden_model_fields"] = String[]
    @test_throws GDPOperatorQualificationError validate_protocol_semantics(
        changed,
    )
    changed = deepcopy(document)
    changed["declarations"]["promotion_eligible"] = true
    @test_throws GDPOperatorQualificationError validate_protocol_semantics(
        changed,
    )
    changed = deepcopy(document)
    pop!(changed, "blockers")
    @test_throws GDPOperatorQualificationError validate_protocol_semantics(
        changed,
    )

    mktemp() do path, io
        write(io, read(PROTOCOL_PATH))
        write(io, UInt8('\n'))
        close(io)
        @test_throws GDPOperatorQualificationError validate_protocol(path)
    end

    mktempdir() do root
        for source in protocol.document["source_files"]
            destination = joinpath(root, source["path"])
            mkpath(dirname(destination))
            cp(joinpath(REPO_ROOT, source["path"]), destination)
        end
        open(joinpath(root, "src", "utils", "data.jl"), "a") do io
            write(io, '\n')
        end
        @test_throws GDPOperatorQualificationError validate_source_pins(root)
    end

    if !Sys.iswindows()
        mktempdir() do root
            mktempdir() do outside
                for source in protocol.document["source_files"]
                    destination = joinpath(root, source["path"])
                    mkpath(dirname(destination))
                    cp(joinpath(REPO_ROOT, source["path"]), destination)
                end
                pinned = joinpath(root, "src", "utils", "data.jl")
                external = joinpath(outside, "data.jl")
                cp(pinned, external)
                rm(pinned)
                symlink(external, pinned)
                @test_throws GDPOperatorQualificationError validate_source_pins(
                    root,
                )
            end
        end
    end
end

@testset "pathwise formulas, date mapping, and invariance" begin
    f = fixture()
    result = compute(f)
    @test result.fixture_class == "SYNTHETIC_OPERATOR_TEST_FIXTURE"
    @test result.fixture_id == "synthetic-gdp-operator-v1"
    @test result.path_kind == "RAW_MODEL_UNCORRECTED_SYNTHETIC"
    @test result.target_periods == f.periods[2:end]
    @test result.path_ids == f.path_ids
    @test size(result.real_gdp_growth) == (4, 3)
    @test size(result.gdp_deflator_inflation) == (4, 3)
    @test result.real_gdp_growth ≈
        400 .* log.(f.real[2:end, :] ./ f.real[1:(end - 1), :])
    @test result.gdp_deflator_inflation ≈
        400 .*
        log.(f.deflator[2:end, :] ./ f.deflator[1:(end - 1), :])
    @test result.gdp_deflator_inflation ≈
        400 .* log.(f.nominal[2:end, :] ./ f.nominal[1:(end - 1), :]) .-
        result.real_gdp_growth
    @test result.mechanics_status ==
        "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
    @test result.concept_bridge_status == "PENDING_VALIDATION"
    @test result.truth_accessed === false
    @test result.score_emitted === false
    @test result.origin_admissible === false
    @test result.promotion_eligible === false

    rescaled = merge(
        f,
        (
            real = 17.0 .* f.real,
            nominal = 23.0 .* f.nominal,
        ),
    )
    scaled_result = compute(rescaled)
    @test scaled_result.real_gdp_growth ≈ result.real_gdp_growth
    @test scaled_result.gdp_deflator_inflation ≈
        result.gdp_deflator_inflation

    mean_first_real =
        400 .* log.(
        vec(sum(f.real[2:end, :], dims = 2)) ./
            vec(sum(f.real[1:(end - 1), :], dims = 2)),
    )
    pathwise_mean = vec(sum(result.real_gdp_growth, dims = 2)) ./ 3
    @test any(abs.(mean_first_real .- pathwise_mean) .> 1.0e-8)

    exact_changes = [0.0, 1.0, -2.0, 3.0, 4.0]
    exact_levels = 100.0 .* exp.(cumsum(exact_changes) ./ 400.0)
    exact_real = repeat(reshape(exact_levels, :, 1), 1, 3)
    exact_result = compute(
        merge(f, (real = exact_real, nominal = 2.0 .* exact_real)),
    )
    @test exact_result.real_gdp_growth[:, 1] ≈ exact_changes[2:end]
    @test all(abs.(exact_result.gdp_deflator_inflation) .< 1.0e-12)
    @test exact_result.real_gdp_growth[end, 1] ≈
        400.0 * log(exact_levels[end] / exact_levels[end - 1])
    @test exact_result.real_gdp_growth ==
        compute(merge(f, (real = exact_real, nominal = 2.0 .* exact_real))).real_gdp_growth

    extreme_real = repeat(
        reshape(
            [
                nextfloat(0.0),
                floatmax(Float64),
                nextfloat(0.0),
                floatmax(Float64),
                1.0,
            ],
            :,
            1,
        ),
        1,
        3,
    )
    extreme_nominal = reverse(extreme_real; dims = 1)
    extreme_result =
        compute(merge(f, (real = extreme_real, nominal = extreme_nominal)))
    @test all(isfinite, extreme_result.real_gdp_growth)
    @test all(isfinite, extreme_result.gdp_deflator_inflation)
end

@testset "fail-closed input and action boundary" begin
    f = fixture()
    @test_throws GDPOperatorQualificationError compute(
        f;
        fixture_class = "EMPIRICAL_ABM_PATH",
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        path_kind = "BRIDGE_ADJUSTED",
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        truth_accessed = true,
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        empirical_path = true,
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        class_h_used = true,
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        bridge_adjusted = true,
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        origin_reanchored = true,
    )
    @test_throws GDPOperatorQualificationError compute(
        f;
        fixture_id = "actual-2026Q1",
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (periods = ["2025Q4", "2026Q2", "2026Q3", "2026Q4", "2027Q1"],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (periods = ["2025Q4", " 2026Q1", "2026Q2", "2026Q3", "2026Q4"],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (periods = ["2025Q4"], real = f.real[1:1, :], nominal = f.nominal[1:1, :])),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (path_ids = [1, 3, 2],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (path_ids = [1, 2],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (path_ids = [1, 2, true],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (path_ids = [1, 2, big(typemax(Int)) + 1],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (real = f.real[1:(end - 1), :],)),
    )
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (nominal = f.nominal[:, 1:2],)),
    )

    zero_real = copy(f.real)
    zero_real[2, 1] = 0.0
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (real = zero_real,)),
    )
    negative_nominal = copy(f.nominal)
    negative_nominal[3, 2] = -1.0
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (nominal = negative_nominal,)),
    )
    nonfinite_real = copy(f.real)
    nonfinite_real[4, 3] = Inf
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (real = nonfinite_real,)),
    )
    boolean_levels = fill(true, size(f.real))
    @test_throws GDPOperatorQualificationError compute(
        merge(f, (real = boolean_levels,)),
    )

    for action in (
            :run_model,
            :load_truth,
            :emit_forecast,
            :score,
            :infer,
            :admit_origin,
            :approve_tier1_operator,
            :promote,
            :register_production,
        )
        @test_throws GDPOperatorQualificationError refuse_prohibited_action(
            action,
        )
    end
    @test_throws GDPOperatorQualificationError refuse_prohibited_action(
        :unknown,
    )
end
