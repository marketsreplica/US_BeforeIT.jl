#!/usr/bin/env julia

using DataFrames
using Dates
using Test

include(joinpath(@__DIR__, "USBitemporal.jl"))
using .USBitemporal

function fixture()
    rows = DataFrame(
        series_id = String[],
        reference_period_start = Date[],
        reference_period_end = Date[],
        value = Union{Missing, Float64}[],
        release_timestamp_utc = DateTime[],
        realtime_start = Date[],
        realtime_end = Date[],
        source_release_id = String[],
        source_url_or_file = String[],
        raw_sha256 = String[],
        retrieved_at_utc = DateTime[],
        unit = String[],
        frequency = String[],
        seasonal_adjustment = String[],
        annual_rate_flag = Bool[],
        stock_flow_index_rate = String[],
        price_basis = String[],
        classification = String[],
        classification_vintage = String[],
        transformation_version = String[],
        quality_status = String[],
    )
    function add!(
            series,
            value,
            release,
            realtime_start,
            realtime_end,
            release_id,
            hash_character;
            quality_status = "APPROVED",
        )
        return push!(
            rows,
            (
                series_id = series,
                reference_period_start = Date(2020, 1, 1),
                reference_period_end = Date(2020, 3, 31),
                value,
                release_timestamp_utc = release,
                realtime_start,
                realtime_end,
                source_release_id = release_id,
                source_url_or_file = "fixture/$release_id.csv",
                raw_sha256 = repeat(hash_character, 64),
                retrieved_at_utc = release + Hour(1),
                unit = "index",
                frequency = "Q",
                seasonal_adjustment = "SA",
                annual_rate_flag = false,
                stock_flow_index_rate = "index",
                price_basis = "not_applicable",
                classification = "aggregate",
                classification_vintage = "not_applicable",
                transformation_version = "level.v1",
                quality_status,
            ),
        )
    end
    add!(
        "gdp",
        100.0,
        DateTime(2020, 4, 29, 12, 30),
        Date(2020, 4, 29),
        Date(2020, 6, 24),
        "gdp-advance",
        "a",
    )
    add!(
        "gdp",
        102.0,
        DateTime(2020, 6, 25, 12, 30),
        Date(2020, 6, 25),
        Date(9999, 12, 31),
        "gdp-third",
        "b",
    )
    add!(
        "rate",
        0.01,
        DateTime(2020, 4, 30, 14, 0),
        Date(2020, 4, 30),
        Date(9999, 12, 31),
        "rate-april",
        "c",
    )
    add!(
        "future",
        999.0,
        DateTime(2020, 7, 1, 12, 0),
        Date(2020, 7, 1),
        Date(9999, 12, 31),
        "future-release",
        "d",
    )
    add!(
        "dubious",
        7.0,
        DateTime(2020, 4, 29, 12, 30),
        Date(2020, 4, 29),
        Date(9999, 12, 31),
        "dubious-release",
        "e";
        quality_status = "DUBIOUS",
    )
    return rows
end

@testset "bitemporal as-of snapshots prevent look-ahead" begin
    observations = fixture()
    @test validate_observations(observations) === observations

    april_origin = DateTime(2020, 4, 30, 14, 0)
    april = asof_snapshot(
        observations,
        april_origin;
        required_series = ["gdp", "rate"],
    )
    @test Set(april.series_id) == Set(["gdp", "rate"])
    @test only(april[april.series_id .== "gdp", :value]) == 100.0
    @test only(april[april.series_id .== "rate", :value]) == 0.01
    @test all(april.release_timestamp_utc .<= april_origin)

    before_june_revision = asof_snapshot(
        observations,
        DateTime(2020, 6, 25, 9, 0),
    )
    @test only(
        before_june_revision[
            before_june_revision.series_id .== "gdp",
            :value,
        ],
    ) == 100.0

    june = asof_snapshot(
        observations,
        DateTime(2020, 6, 25, 12, 30),
    )
    @test only(june[june.series_id .== "gdp", :value]) == 102.0
    @test "future" ∉ june.series_id
    @test "dubious" ∉ june.series_id

    with_dubious = asof_snapshot(
        observations,
        april_origin;
        allowed_quality_statuses = Set(["APPROVED", "DUBIOUS"]),
    )
    @test "dubious" in with_dubious.series_id
    @test_throws BitemporalValidationError asof_snapshot(
        observations,
        april_origin;
        required_series = ["not_available"],
    )
end

@testset "origin manifests are immutable to post-origin rows" begin
    observations = fixture()
    origin = DateTime(2020, 4, 30, 14, 0)
    manifest = origin_manifest(
        observations,
        origin;
        required_series = ["gdp", "rate"],
    )
    @test manifest.schema_version == "beforeit-us-origin-manifest.v1"
    @test manifest.row_count == 2
    @test occursin(r"^[0-9a-f]{64}$", manifest.snapshot_sha256)
    @test all(
        occursin(r"^[0-9a-f]{64}$", digest)
            for digest in manifest.row_sha256
    )

    changed_future = deepcopy(observations)
    changed_future[
        changed_future.series_id .== "future",
        :value,
    ] .= -999.0
    @test origin_manifest(changed_future, origin).snapshot_sha256 ==
        manifest.snapshot_sha256

    changed_eligible = deepcopy(observations)
    changed_eligible[
        changed_eligible.source_release_id .== "gdp-advance",
        :value,
    ] .= 101.0
    @test origin_manifest(changed_eligible, origin).snapshot_sha256 !=
        manifest.snapshot_sha256
end

@testset "bitemporal schema and ambiguity fail closed" begin
    observations = fixture()

    missing_column = select(observations, Not(:raw_sha256))
    @test_throws BitemporalValidationError validate_observations(
        missing_column,
    )

    unknown_column = transform(observations, :value => identity => :extra)
    @test_throws BitemporalValidationError validate_observations(
        unknown_column,
    )

    bad_hash = deepcopy(observations)
    bad_hash[1, :raw_sha256] = "not-a-hash"
    @test_throws BitemporalValidationError validate_observations(bad_hash)

    retrieved_before_release = deepcopy(observations)
    retrieved_before_release[1, :retrieved_at_utc] =
        retrieved_before_release[1, :release_timestamp_utc] - Second(1)
    @test_throws BitemporalValidationError validate_observations(
        retrieved_before_release,
    )

    release_outside_realtime_interval = deepcopy(observations)
    release_outside_realtime_interval[1, :realtime_start] = Date(2020, 4, 30)
    @test_throws BitemporalValidationError validate_observations(
        release_outside_realtime_interval,
    )

    duplicate = vcat(observations, observations[1:1, :])
    @test_throws BitemporalValidationError validate_observations(duplicate)

    ambiguous = deepcopy(observations)
    tied = deepcopy(observations[1:1, :])
    tied[1, :source_release_id] = "gdp-advance-alternate"
    tied[1, :raw_sha256] = repeat("f", 64)
    append!(ambiguous, tied)
    @test_throws BitemporalValidationError asof_snapshot(
        ambiguous,
        DateTime(2020, 4, 30, 14, 0),
    )

    missing_value = deepcopy(observations)
    missing_value[1, :value] = missing
    @test_throws BitemporalValidationError validate_observations(
        missing_value,
    )
end
