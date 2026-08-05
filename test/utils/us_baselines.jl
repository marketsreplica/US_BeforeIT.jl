using Test

function metadata_value(metadata, name::String)
    return get(metadata, name, get(metadata, Symbol(name), nothing))
end

@testset "U.S. baseline loader" begin
    @test Set(Bit.available_us_baselines()) ==
        Set((:structural_2024Q4, :nowcast_2026Q1))
    @test_throws ArgumentError Bit.load_us_baseline(:unknown)
    @test_throws ArgumentError Bit.load_us_calibration(:unknown)

    baseline_cases = (
        (
            vintage = :structural,
            aliases = ("2024-Q4", :structural_2024Q4),
            period = "2024-Q4",
        ),
        (
            vintage = :nowcast,
            aliases = ("current", "2026-Q1", :nowcast_2026Q1),
            period = "2026-Q1",
        ),
    )
    for case in baseline_cases
        normalized = Bit.normalize_us_vintage(case.vintage)
        path = Bit.US_BASELINE_FILES[normalized]
        for alias in case.aliases
            @test Bit.normalize_us_vintage(alias) == normalized
        end
        if isfile(path)
            artifact = Bit.load_us_baseline(case.vintage)
            @test artifact.path == path
            @test metadata_value(artifact.metadata, "country") == "US"
            @test metadata_value(artifact.metadata, "period") == case.period
            @test metadata_value(
                artifact.metadata,
                "structural_reference_year",
            ) == 2024
            @test metadata_value(artifact.metadata, "sector_count") == 68
            @test artifact.parameters["G"] == 68
        else
            @test_throws ErrorException Bit.load_us_baseline(case.vintage)
        end
    end

    for vintage in (:structural, :nowcast)
        normalized = Bit.normalize_us_vintage(vintage)
        path = Bit.US_CALIBRATION_FILES[normalized]
        if isfile(path)
            artifact = Bit.load_us_calibration(vintage)
            @test artifact.path == path
            @test metadata_value(artifact.metadata, "country") == "US"
            @test metadata_value(artifact.metadata, "sector_count") == 68
            intermediate_consumption =
                artifact.calibration_object.figaro["intermediate_consumption"]
            @test size(intermediate_consumption, 1) == 68
            @test size(intermediate_consumption, 2) == 68
        else
            @test_throws ErrorException Bit.load_us_calibration(vintage)
        end
    end
end
