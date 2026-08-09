using SHA
using Test
using TOML

include("USPCEPriceAnalogueQualification.jl")
using .USPCEPriceAnalogueQualification

const PCE = USPCEPriceAnalogueQualification
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))

function fixture()
    periods = [
        "2025Q3",
        "2025Q4",
        "2026Q1",
        "2026Q2",
        "2026Q3",
        "2026Q4",
    ]
    path_ids = [1, 2, 3]
    implicit_price = [
        1.0 4.0 0.8
        1.01 2.0 0.9
        1.03 3.0 0.85
        1.02 2.5 0.95
        1.06 5.0 1.0
        1.09 4.0 1.08
    ]
    real = [
        100.0 80.0 120.0
        103.0 82.0 118.0
        104.0 85.0 119.0
        106.0 83.0 121.0
        107.0 88.0 125.0
        110.0 90.0 124.0
    ]
    nominal = implicit_price .* real
    return (; periods, path_ids, implicit_price, nominal, real)
end

function compute(f = fixture(); kwargs...)
    options = Dict{Symbol, Any}(
        :fixture_class => "SYNTHETIC_OPERATOR_TEST_FIXTURE",
        :fixture_id => "synthetic-pce-analogue-v1",
        :input_path_kind => "CALLER_SUPPLIED_SYNTHETIC_RAW_PATHS",
        :measurement_regime => "SYNTHETIC_POST_STEP_HOMOGENEOUS",
        :include_four_quarter => true,
        :truth_accessed => false,
        :artifact_accessed => false,
        :model_executed => false,
        :empirical_input => false,
        :opening_stitch_used => false,
    )
    merge!(options, Dict(kwargs))
    return compute_synthetic_analogue(
        f.periods,
        f.path_ids,
        f.nominal,
        f.real;
        options...,
    )
end

function copy_pinned_sources(destination_root, protocol)
    for source in protocol.document["source_files"]
        relative = source["path"]
        destination = joinpath(destination_root, relative)
        mkpath(dirname(destination))
        cp(joinpath(REPOSITORY_ROOT, relative), destination)
    end
    return destination_root
end

@testset "closed self-hashed protocol and source pins" begin
    protocol = validate_protocol()
    @test protocol.byte_sha256 == bytes2hex(SHA.sha256(read(PROTOCOL_PATH)))
    @test protocol.content_sha256 ==
        compute_protocol_content_sha256(protocol.document)
    @test protocol.document["contract"]["economic_object"] ==
        "beforeit-household-consumption-implicit-price-analogue.v1"
    @test protocol.document["contract"]["qualification_status"] ==
        "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
    @test protocol.document["contract"]["official_equivalence_status"] ==
        "NOT_VALIDATED"
    @test protocol.document["contract"]["tier1_total_pce_operator_approved"] ===
        false
    @test protocol.document["contract"]["tier1_core_pce_operator_approved"] ===
        false
    @test protocol.document["contract"]["origin_admissible"] === false
    @test protocol.document["contract"]["promotion_eligible"] === false
    @test all(
        selector["status"] == "DOCUMENTED_NOT_LOADED"
            for selector in protocol.document["direct_truth_selectors"]
    )
    @test getindex.(
        protocol.document["direct_truth_selectors"],
        "series_code",
    ) == ["DPCERG", "DPCCRG"]
    @test all(
        source["provider"] == "U.S. Bureau of Economic Analysis" &&
            startswith(source["url"], "https://www.bea.gov/")
            for source in protocol.document["official_sources"]
    )
    @test validate_source_pins()

    changed = deepcopy(protocol.document)
    changed["contract"]["qualification_status"] = "APPROVED"
    @test_throws AnalogueQualificationError validate_protocol_semantics(changed)

    changed = deepcopy(protocol.document)
    changed["boundaries"]["blockers"] =
        changed["boundaries"]["blockers"][1:(end - 1)]
    changed["artifact"]["content_sha256"] =
        compute_protocol_content_sha256(changed)
    @test_throws AnalogueQualificationError validate_protocol_semantics(changed)

    changed = deepcopy(protocol.document)
    changed["declarations"]["truth_access_allowed"] = true
    changed["artifact"]["content_sha256"] =
        compute_protocol_content_sha256(changed)
    @test_throws AnalogueQualificationError validate_protocol_semantics(changed)

    changed = deepcopy(protocol.document)
    changed["official_sources"][1]["url"] = "https://example.test/"
    changed["artifact"]["content_sha256"] =
        compute_protocol_content_sha256(changed)
    @test_throws AnalogueQualificationError validate_protocol_semantics(changed)

    changed = deepcopy(protocol.document)
    changed["direct_truth_selectors"][1]["status"] = "LOADED"
    changed["artifact"]["content_sha256"] =
        compute_protocol_content_sha256(changed)
    @test_throws AnalogueQualificationError validate_protocol_semantics(changed)

    mktemp() do path, io
        write(io, read(PROTOCOL_PATH))
        write(io, UInt8('\n'))
        close(io)
        @test_throws AnalogueQualificationError validate_protocol(path)
    end

    mktempdir() do temporary_root
        root = realpath(temporary_root)
        copy_pinned_sources(root, protocol)
        @test validate_source_pins(root)
        open(joinpath(root, "src", "utils", "data.jl"), "a") do io
            write(io, '\n')
        end
        @test_throws AnalogueQualificationError validate_source_pins(root)
    end

    mktempdir() do temporary_root
        root = realpath(temporary_root)
        copy_pinned_sources(root, protocol)
        rm(joinpath(root, "src", "markets", "search_and_matching.jl"))
        @test_throws AnalogueQualificationError validate_source_pins(root)
    end

    if !Sys.iswindows()
        mktempdir() do temporary_root
            root = realpath(temporary_root)
            copy_pinned_sources(root, protocol)
            pinned = joinpath(root, "src", "utils", "data.jl")
            external = tempname()
            cp(pinned, external)
            rm(pinned)
            symlink(external, pinned)
            @test_throws AnalogueQualificationError validate_source_pins(root)
            rm(external)
        end
    end
end

@testset "pathwise mechanics, exact mapping, and four-quarter option" begin
    f = fixture()
    nominal_before = copy(f.nominal)
    real_before = copy(f.real)
    result = compute(f)

    @test f.nominal == nominal_before
    @test f.real == real_before
    @test result.fixture_class == "SYNTHETIC_OPERATOR_TEST_FIXTURE"
    @test result.fixture_id == "synthetic-pce-analogue-v1"
    @test result.economic_object ==
        "beforeit-household-consumption-implicit-price-analogue.v1"
    @test result.input_path_kind == "CALLER_SUPPLIED_SYNTHETIC_RAW_PATHS"
    @test result.measurement_regime == "SYNTHETIC_POST_STEP_HOMOGENEOUS"
    @test result.input_periods == f.periods
    @test result.path_ids == f.path_ids
    @test result.implicit_price_analogue ≈ f.implicit_price
    @test result.qoq_target_periods == f.periods[2:end]
    @test result.four_quarter_target_periods == f.periods[5:end]
    @test size(result.annualized_qoq_log_change) == (5, 3)
    @test size(something(result.four_quarter_log_change)) == (2, 3)

    expected_qoq = 400.0 .* (
        log.(f.implicit_price[2:end, :]) .-
            log.(f.implicit_price[1:(end - 1), :])
    )
    expected_four_quarter = 100.0 .* (
        log.(f.implicit_price[5:end, :]) .-
            log.(f.implicit_price[1:(end - 4), :])
    )
    @test result.annualized_qoq_log_change ≈ expected_qoq
    @test something(result.four_quarter_log_change) ≈ expected_four_quarter
    for path in axes(f.implicit_price, 2)
        for row in 2:size(f.implicit_price, 1)
            @test result.annualized_qoq_log_change[row - 1, path] ≈
                400.0 * log(
                f.implicit_price[row, path] /
                    f.implicit_price[row - 1, path],
            )
        end
        for row in 5:size(f.implicit_price, 1)
            @test something(result.four_quarter_log_change)[row - 4, path] ≈
                100.0 * log(
                f.implicit_price[row, path] /
                    f.implicit_price[row - 4, path],
            )
        end
    end

    @test result.mechanics_status ==
        "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
    @test result.official_equivalence_status == "NOT_VALIDATED"
    @test result.truth_accessed === false
    @test result.artifact_accessed === false
    @test result.model_executed === false
    @test result.empirical_input === false
    @test result.opening_stitch_used === false
    @test result.origin_admissible === false
    @test result.promotion_eligible === false

    without_h4 = compute(f; include_four_quarter = false)
    @test without_h4.four_quarter_log_change === nothing
    @test isempty(without_h4.four_quarter_target_periods)
    @test without_h4.annualized_qoq_log_change ≈
        result.annualized_qoq_log_change

    swapped = merge(
        f,
        (
            nominal = f.nominal[:, [3, 2, 1]],
            real = f.real[:, [3, 2, 1]],
        ),
    )
    swapped_result = compute(swapped)
    @test swapped_result.path_ids == [1, 2, 3]
    @test swapped_result.annualized_qoq_log_change ≈
        result.annualized_qoq_log_change[:, [3, 2, 1]]
    @test something(swapped_result.four_quarter_log_change) ≈
        something(result.four_quarter_log_change)[:, [3, 2, 1]]

    repeated = compute(f)
    @test repeated.implicit_price_analogue == result.implicit_price_analogue
    @test repeated.annualized_qoq_log_change ==
        result.annualized_qoq_log_change
    @test repeated.four_quarter_log_change == result.four_quarter_log_change
end

@testset "path-specific rebase invariance and Jensen fixture" begin
    f = fixture()
    original = compute(f)
    nominal_scale = reshape([7.0, 0.25, 33.0], 1, :)
    rebased = compute(merge(f, (nominal = f.nominal .* nominal_scale,)))
    @test rebased.implicit_price_analogue ≈
        f.implicit_price .* nominal_scale
    @test rebased.annualized_qoq_log_change ≈
        original.annualized_qoq_log_change
    @test something(rebased.four_quarter_log_change) ≈
        something(original.four_quarter_log_change)

    unit_change = reshape([0.5, 9.0, 1.25], 1, :)
    jointly_rebased = compute(
        merge(
            f,
            (
                nominal = f.nominal .* unit_change,
                real = f.real .* unit_change,
            ),
        ),
    )
    @test jointly_rebased.implicit_price_analogue ≈
        original.implicit_price_analogue
    @test jointly_rebased.annualized_qoq_log_change ≈
        original.annualized_qoq_log_change
    @test something(jointly_rebased.four_quarter_log_change) ≈
        something(original.four_quarter_log_change)

    periods = ["2026Q1", "2026Q2"]
    path_ids = [1, 2]
    real = ones(Float64, 2, 2)
    nominal = [1.0 4.0; 2.0 2.0]
    jensen = compute_synthetic_analogue(
        periods,
        path_ids,
        nominal,
        real;
        fixture_class = "SYNTHETIC_OPERATOR_TEST_FIXTURE",
        fixture_id = "synthetic-jensen-fixture",
        input_path_kind = "CALLER_SUPPLIED_SYNTHETIC_RAW_PATHS",
        measurement_regime = "SYNTHETIC_POST_STEP_HOMOGENEOUS",
        include_four_quarter = false,
        truth_accessed = false,
        artifact_accessed = false,
        model_executed = false,
        empirical_input = false,
        opening_stitch_used = false,
    )
    pathwise_mean = sum(jensen.annualized_qoq_log_change[1, :]) / 2
    transform_of_mean = 400.0 * log(
        (sum(jensen.implicit_price_analogue[2, :]) / 2) /
            (sum(jensen.implicit_price_analogue[1, :]) / 2),
    )
    @test pathwise_mean ≈ 0.0 atol = 1.0e-12
    @test abs(transform_of_mean - pathwise_mean) > 1.0
end

@testset "strict typed input and structural fail-closed boundary" begin
    f = fixture()

    zero_nominal = copy(f.nominal)
    zero_nominal[2, 1] = 0.0
    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = zero_nominal,)),
    )
    negative_real = copy(f.real)
    negative_real[3, 2] = -1.0
    @test_throws AnalogueQualificationError compute(
        merge(f, (real = negative_real,)),
    )
    infinite_nominal = copy(f.nominal)
    infinite_nominal[4, 3] = Inf
    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = infinite_nominal,)),
    )
    nan_real = copy(f.real)
    nan_real[5, 1] = NaN
    @test_throws AnalogueQualificationError compute(merge(f, (real = nan_real,)))

    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = trues(size(f.nominal)),)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = ones(Int, size(f.nominal)),)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (real = Float32.(f.real),)),
    )
    with_missing = Matrix{Union{Missing, Float64}}(f.nominal)
    with_missing[2, 2] = missing
    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = with_missing,)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = @view(f.nominal[:, :]),)),
    )

    @test_throws AnalogueQualificationError compute(
        merge(f, (nominal = f.nominal[1:(end - 1), :],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (real = f.real[:, 1:2],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(
            f,
            (
                nominal = zeros(Float64, length(f.periods), 0),
                real = zeros(Float64, length(f.periods), 0),
                path_ids = Int[],
            ),
        ),
    )

    @test_throws AnalogueQualificationError compute(
        merge(f, (path_ids = [3, 2, 1],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (path_ids = [0, 1, 2],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (path_ids = [1, 2],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (path_ids = UInt[1, 2, 3],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (path_ids = Any[1, 2, true],)),
    )

    gap_periods = copy(f.periods)
    gap_periods[3] = "2026Q2"
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = gap_periods,)),
    )
    duplicate_periods = copy(f.periods)
    duplicate_periods[4] = duplicate_periods[3]
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = duplicate_periods,)),
    )
    whitespace_periods = copy(f.periods)
    whitespace_periods[1] = " 2025Q3"
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = whitespace_periods,)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = ["2025Q3"], nominal = f.nominal[1:1, :], real = f.real[1:1, :])),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = f.periods[1:(end - 1)],)),
    )
    @test_throws AnalogueQualificationError compute(
        merge(f, (periods = Tuple(f.periods),)),
    )

    four_rows = merge(
        f,
        (
            periods = f.periods[1:4],
            nominal = f.nominal[1:4, :],
            real = f.real[1:4, :],
        ),
    )
    @test_throws AnalogueQualificationError compute(four_rows)
    four_rows_qoq = compute(four_rows; include_four_quarter = false)
    @test size(four_rows_qoq.annualized_qoq_log_change) == (3, 3)
    @test four_rows_qoq.four_quarter_log_change === nothing
    @test_throws AnalogueQualificationError compute(f; include_four_quarter = 1)
end

@testset "empirical opening stitch and prohibited actions remain closed" begin
    f = fixture()
    @test_throws AnalogueQualificationError compute(
        f;
        fixture_class = "EMPIRICAL_PATH",
    )
    @test_throws AnalogueQualificationError compute(
        f;
        fixture_id = "actual-2026Q1",
    )
    @test_throws AnalogueQualificationError compute(
        f;
        input_path_kind = "MODEL_OUTPUT",
    )
    @test_throws AnalogueQualificationError compute(
        f;
        measurement_regime = "OPENING_AND_POST_STEP_MIXED",
    )
    @test_throws AnalogueQualificationError compute(f; truth_accessed = true)
    @test_throws AnalogueQualificationError compute(f; artifact_accessed = true)
    @test_throws AnalogueQualificationError compute(f; model_executed = true)
    @test_throws AnalogueQualificationError compute(f; empirical_input = true)
    @test_throws AnalogueQualificationError compute(f; opening_stitch_used = true)
    @test_throws AnalogueQualificationError compute(f; truth_accessed = 0)

    for action in PROHIBITED_ACTIONS
        @test_throws AnalogueQualificationError refuse_prohibited_action(action)
    end
    @test :execute_opening_to_first_step_empirical in PROHIBITED_ACTIONS
    @test_throws AnalogueQualificationError refuse_prohibited_action(:unknown)
    @test_throws AnalogueQualificationError refuse_prohibited_action(
        "run_model",
    )

    module_text = read(
        joinpath(@__DIR__, "USPCEPriceAnalogueQualification.jl"),
        String,
    )
    @test !occursin(r"using\s+(HTTP|Downloads|BeforeIT)", module_text)
    @test !occursin("data/us/raw", module_text)
    @test !occursin(r"\binclude\s*\(", module_text)
end
