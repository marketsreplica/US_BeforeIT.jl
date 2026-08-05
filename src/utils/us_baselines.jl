using JLD2

const US_BASELINE_FILES = Dict(
    :structural_2024Q4 => joinpath(
        dir,
        "data",
        "us",
        "baselines",
        "US_2024Q4_structural.jld2",
    ),
    :nowcast_2026Q1 => joinpath(
        dir,
        "data",
        "us",
        "baselines",
        "US_2026Q1_nowcast.jld2",
    ),
)

const US_CALIBRATION_FILES = Dict(
    :structural_2024Q4 => joinpath(
        dir,
        "data",
        "us",
        "calibration",
        "US_2024_calibration_object.jld2",
    ),
    :nowcast_2026Q1 => joinpath(
        dir,
        "data",
        "us",
        "calibration",
        "US_2026Q1_nowcast_object.jld2",
    ),
)

function normalize_us_vintage(vintage)
    value = lowercase(replace(String(vintage), "-" => "", "_" => ""))
    if value in ("structural", "2024q4", "structural2024q4")
        return :structural_2024Q4
    elseif value in ("nowcast", "current", "2026q1", "nowcast2026q1")
        return :nowcast_2026Q1
    end
    throw(
        ArgumentError(
            "Unknown U.S. vintage '$vintage'. Use 2024Q4/structural or 2026Q1/nowcast.",
        ),
    )
end

"""
    available_us_baselines()

Return the U.S. structural and nowcast baseline vintages understood by the
package. An artifact is loadable once its file is installed under `data/us`.
"""
available_us_baselines() = sort!(collect(keys(US_BASELINE_FILES)))

"""
    load_us_baseline(vintage=:nowcast)

Load a versioned U.S. parameter/initial-condition artifact. Accepted aliases
are `2024Q4`/`structural` and `2026Q1`/`nowcast`/`current`.
"""
function load_us_baseline(vintage = :nowcast)
    normalized = normalize_us_vintage(vintage)
    path = US_BASELINE_FILES[normalized]
    isfile(path) || error("U.S. baseline artifact is not installed: $path")
    artifact = JLD2.load(path)
    return (
        parameters = artifact["parameters"],
        initial_conditions = artifact["initial_conditions"],
        metadata = artifact["metadata"],
        path = path,
    )
end

"""
    load_us_calibration(vintage=:nowcast)

Load the calibration object behind a versioned U.S. baseline. Accepted aliases
are `2024Q4`/`structural` and `2026Q1`/`nowcast`/`current`.
"""
function load_us_calibration(vintage = :nowcast)
    normalized = normalize_us_vintage(vintage)
    path = US_CALIBRATION_FILES[normalized]
    isfile(path) || error("U.S. calibration artifact is not installed: $path")
    artifact = JLD2.load(path)
    return (
        calibration_object = artifact["calibration_object"],
        metadata = artifact["metadata"],
        path = path,
    )
end
