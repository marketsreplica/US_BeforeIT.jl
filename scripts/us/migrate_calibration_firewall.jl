#!/usr/bin/env julia

module USCalibrationFirewallMigration

    using JLD2
    using SHA

    import BeforeIT as Bit

    const SCRIPT_DIR = @__DIR__
    const REPO_ROOT = normpath(joinpath(SCRIPT_DIR, "..", ".."))
    const POLICY_PARAMETER_NAMES = ("rho", "r_star", "xi_pi", "xi_gamma")
    const DEFAULT_ARTIFACT_PATHS = (
        joinpath(
            REPO_ROOT,
            "data",
            "us",
            "baselines",
            "US_2024Q4_structural.jld2",
        ),
        joinpath(
            REPO_ROOT,
            "data",
            "us",
            "baselines",
            "US_2026Q1_nowcast.jld2",
        ),
        joinpath(
            REPO_ROOT,
            "data",
            "us",
            "calibration",
            "US_2024_calibration_object.jld2",
        ),
        joinpath(
            REPO_ROOT,
            "data",
            "us",
            "calibration",
            "US_2026Q1_nowcast_object.jld2",
        ),
    )

    file_sha256(path::AbstractString) =
        open(path, "r") do input
        return bytes2hex(SHA.sha256(input))
    end

    function remove_embedded_corrections!(metadata::AbstractDict)
        measurement = get(metadata, "output_measurement", nothing)
        measurement isa AbstractDict || return String[]
        series = get(measurement, "series", nothing)
        series isa AbstractDict || return String[]
        cleaned = String[]
        for (name, entry) in series
            entry isa AbstractDict || continue
            haskey(entry, "path_correction") || continue
            pop!(entry, "path_correction")
            push!(cleaned, String(name))
        end
        return sort!(cleaned)
    end

    function restored_policy_parameters!(
            payload::AbstractDict,
            metadata::AbstractDict,
        )
        haskey(payload, "parameters") || return Dict{String, Float64}()
        parameters = payload["parameters"]
        parameters isa AbstractDict ||
            error("Baseline parameters must be a dictionary")
        legacy = get(metadata, "forecast_calibration", nothing)
        if !(legacy isa AbstractDict)
            firewall = get(metadata, "calibration_firewall", nothing)
            firewall isa AbstractDict &&
                get(firewall, "raw_parameters", false) === true &&
                return Dict{String, Float64}()
            error(
                "Baseline has neither legacy pre-override values nor a valid raw-parameter firewall marker",
            )
        end
        estimated = get(legacy, "estimated_parameters", nothing)
        estimated isa AbstractDict ||
            error("Legacy baseline metadata does not preserve pre-override parameters")
        Set(String.(keys(estimated))) == Set(POLICY_PARAMETER_NAMES) ||
            error("Legacy pre-override policy parameter set is incomplete")

        restored = Dict{String, Float64}()
        for name in POLICY_PARAMETER_NAMES
            haskey(parameters, name) ||
                error("Baseline is missing policy parameter $name")
            value = estimated[name]
            value isa Real && isfinite(value) ||
                error("Preserved pre-override parameter $name is invalid")
            restored[name] = Float64(value)
            parameters[name] = Float64(value)
        end
        return restored
    end

    function write_payload_atomically(path::AbstractString, payload::AbstractDict)
        directory = dirname(path)
        mkpath(directory)
        temporary_path, stream = mktemp(directory)
        close(stream)
        rm(temporary_path)
        try
            JLD2.jldopen(temporary_path, "w") do output
                for (key, value) in payload
                    output[String(key)] = value
                end
            end
            mv(temporary_path, path; force = true)
        finally
            isfile(temporary_path) && rm(temporary_path)
        end
        return path
    end

    function validate_migrated_artifact(path::AbstractString)
        payload = JLD2.load(path)
        metadata = get(payload, "metadata", nothing)
        metadata isa AbstractDict || error("$path has no metadata dictionary")
        !haskey(metadata, "forecast_calibration") ||
            error("$path still embeds forecast calibration")
        firewall = get(metadata, "calibration_firewall", nothing)
        firewall isa AbstractDict ||
            error("$path has no calibration firewall metadata")
        get(firewall, "schema_version", nothing) ==
            "beforeit-calibration-firewall.v1" ||
            error("$path has an unsupported calibration firewall schema")
        get(firewall, "raw_parameters", nothing) ===
            haskey(payload, "parameters") ||
            error("$path has an incorrect raw-parameter artifact marker")
        get(firewall, "forecast_error_fitted_parameters", true) === false ||
            error("$path permits forecast-error-fitted raw parameters")
        get(firewall, "postprocessing_embedded", true) === false ||
            error("$path embeds postprocessing")
        measurement = get(metadata, "output_measurement", Dict{String, Any}())
        series = get(measurement, "series", Dict{String, Any}())
        all(
            entry -> !(entry isa AbstractDict) ||
                !haskey(entry, "path_correction"),
            values(series),
        ) || error("$path still embeds output path corrections")
        return payload
    end

    function migrate_artifact!(path::AbstractString)
        isfile(path) || error("Calibration artifact is not installed: $path")
        original_sha256 = file_sha256(path)
        payload = JLD2.load(path)
        metadata = get(payload, "metadata", nothing)
        metadata isa AbstractDict || error("$path has no metadata dictionary")

        existing_firewall = get(metadata, "calibration_firewall", nothing)
        if !haskey(metadata, "forecast_calibration") &&
                existing_firewall isa AbstractDict
            validate_migrated_artifact(path)
            return (
                path = String(path),
                changed = false,
                original_sha256,
                migrated_sha256 = original_sha256,
                restored_parameters = String[],
                removed_corrections = String[],
            )
        end

        restored = restored_policy_parameters!(payload, metadata)
        removed_corrections = remove_embedded_corrections!(metadata)
        pop!(metadata, "forecast_calibration", nothing)
        metadata["calibration_firewall"] = Dict{String, Any}(
            "schema_version" => "beforeit-calibration-firewall.v1",
            "raw_parameters" => haskey(payload, "parameters"),
            "forecast_error_fitted_parameters" => false,
            "postprocessing_embedded" => false,
            "migration_method" =>
                "restore_preserved_pre_override_values_and_remove_class_h_metadata",
            "source_artifact_sha256" => original_sha256,
            "restored_parameters" => sort!(collect(keys(restored))),
            "removed_output_corrections" => removed_corrections,
            "migration_tool_version" =>
                "beforeit-us-calibration-firewall-migration.v1",
            "note" =>
                "Class-H policy overrides and damped path corrections remain in scripts/us/forecast_calibration.toml and forecast outputs only.",
        )

        write_payload_atomically(path, payload)
        validate_migrated_artifact(path)
        return (
            path = String(path),
            changed = true,
            original_sha256,
            migrated_sha256 = file_sha256(path),
            restored_parameters = sort!(collect(keys(restored))),
            removed_corrections,
        )
    end

    function migrate_all!(paths = DEFAULT_ARTIFACT_PATHS)
        return [migrate_artifact!(path) for path in paths]
    end

    function main()
        results = migrate_all!()
        for result in results
            action = result.changed ? "migrated" : "already clean"
            println(
                action,
                ": ",
                relpath(result.path, REPO_ROOT),
                " (",
                result.migrated_sha256,
                ")",
            )
        end
        return nothing
    end

end

if abspath(PROGRAM_FILE) == @__FILE__
    USCalibrationFirewallMigration.main()
end
