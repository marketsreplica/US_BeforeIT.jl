#!/usr/bin/env julia

module USOpeningAccountingCandidate

    using Dates
    using JLD2
    using LinearAlgebra
    using Random
    using SHA
    using TOML

    import BeforeIT as Bit

    include(joinpath(@__DIR__, "USJuliaExecutionEnvelope.jl"))
    using .USJuliaExecutionEnvelope
    include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
    using .USSupplyMakeDiagnostics
    include(joinpath(@__DIR__, "UST10105Controls.jl"))
    using .UST10105Controls

    export BUILD_SCHEMA,
        CANONICAL_BYTE_BUILD,
        CANDIDATE_SCHEMA,
        CandidateBuildMode,
        ExecutionEnvelopeMismatch,
        MANIFEST_SCHEMA,
        PORTABLE_SEMANTIC_BUILD,
        SemanticExecutionPreconditionMismatch,
        build_candidate,
        build_configured_candidates,
        current_execution_envelope,
        load_build_config,
        semantic_sha256,
        source_tree_digest,
        validate_build_environment,
        validate_candidate,
        write_candidate

    const BUILD_SCHEMA =
        "beforeit-us-opening-accounting-candidate-build.v1"
    const CANDIDATE_SCHEMA =
        "beforeit-us-opening-accounting-candidate.v1"
    const MANIFEST_SCHEMA =
        "beforeit-us-opening-accounting-candidates-manifest.v1"
    const RECONCILIATION_SCHEMA =
        "beforeit-opening-macro-reconciliation.v1"
    const CONTROL_SOURCE =
        "BEA_NIPA_T10105_CURRENT_DOLLAR_SAAR_DIVIDED_BY_4"
    const SOURCE_TOLERANCE = 1.0
    const MODEL_TOLERANCE = 1.0e-6
    const SIMULATED_QUARTERS = 4
    const SOURCE_TREE_DIGEST_ALGORITHM =
        "sha256(sorted_posix_relative_path + NUL + lowercase_file_sha256 + LF)"
    const REPO_ROOT =
        normpath(joinpath(@__DIR__, "..", "..", ".."))
    @enum CandidateBuildMode begin
        CANONICAL_BYTE_BUILD
        PORTABLE_SEMANTIC_BUILD
    end
    const EXECUTABLE_INPUT_PATHS = Dict(
        "builder_path" =>
            "scripts/us/accounting/build_opening_accounting_candidate.jl",
        "execution_envelope_module_path" =>
            "scripts/us/accounting/USJuliaExecutionEnvelope.jl",
        "supply_make_reader_path" =>
            "scripts/us/accounting/USSupplyMakeDiagnostics.jl",
        "t10105_reader_path" =>
            "scripts/us/accounting/UST10105Controls.jl",
        "julia_project_path" => "scripts/us/Project.toml",
        "julia_manifest_path" => "scripts/us/Manifest.toml",
    )
    const VERIFIED_CONFIG_RECEIPTS =
        IdDict{
        Any,
        NamedTuple{
            (:path, :sha256, :semantic_sha256),
            Tuple{String, String, String},
        },
    }()
    const INTRINSIC_PROTECTED_PATHS = Set(
        normpath.(
            joinpath.(
                Ref(REPO_ROOT),
                [
                    "data/us/calibration/US_2024_calibration_object.jld2",
                    "data/us/calibration/US_2026Q1_nowcast_object.jld2",
                    "data/us/baselines/US_2024Q4_structural.jld2",
                    "data/us/baselines/US_2026Q1_nowcast.jld2",
                ],
            ),
        ),
    )
    const REJECTED_INVENTORY_ALIAS_KEYS = Set(
        [
            "S_s",
            "commodity_balance_supply_s",
            "commodity_balance_modeled_uses_s",
            "inventory_statistical_discrepancy_s",
            "commodity_balance_residual_s",
        ],
    )

    const LEGACY_COMMODITY_KEYS = Set(
        [
            "S_s",
            "commodity_balance_supply_s",
            "commodity_balance_modeled_uses_s",
            "inventory_statistical_discrepancy_s",
            "commodity_balance_residual_s",
            "domestic_commodity_output_g",
            "commodity_supply_g",
            "modeled_commodity_uses_g",
            "unreconciled_commodity_gap_g",
            "commodity_balance_closure_applied",
            "commodity_output_codes",
        ],
    )
    const OPENING_CONTROL_KEYS = Set(
        vcat(
            [
                "use_opening_macro_controls",
                "opening_macro_control_source",
                "opening_macro_control_unit",
                "opening_macro_control_absolute_tolerance",
            ],
            collect(Bit.OPENING_MACRO_NUMERIC_KEYS),
        ),
    )

    sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
    file_sha256(path) = sha256_hex(read(path))

    function source_tree_digest(directory::AbstractString)
        root = abspath(normpath(String(directory)))
        isdir(root) ||
            throw(ArgumentError("runtime source tree is missing: $root"))
        paths = String[]
        for (walk_root, _, files) in walkdir(root; follow_symlinks = false)
            for filename in files
                endswith(filename, ".jl") || continue
                path = joinpath(walk_root, filename)
                islink(path) &&
                    throw(
                    ArgumentError(
                        "runtime Julia source cannot be a symlink: $path",
                    ),
                )
                push!(paths, path)
            end
        end
        isempty(paths) &&
            throw(ArgumentError("runtime source tree contains no Julia sources"))
        sort!(
            paths;
            by = path -> replace(relpath(path, root), '\\' => '/'),
        )
        io = IOBuffer()
        relative_paths = String[]
        for path in paths
            relative_path = replace(relpath(path, root), '\\' => '/')
            push!(relative_paths, relative_path)
            write(io, codeunits(relative_path))
            write(io, UInt8(0))
            write(io, codeunits(file_sha256(path)))
            write(io, UInt8('\n'))
        end
        return (
            sha256 = sha256_hex(take!(io)),
            file_count = length(paths),
            relative_paths,
            algorithm = SOURCE_TREE_DIGEST_ALGORITHM,
        )
    end

    function checked_relative_path(repo_root::AbstractString, relative_path)
        text = String(relative_path)
        isabspath(text) &&
            throw(ArgumentError("candidate configuration paths must be relative"))
        root = dirname(
            joinpath(normpath(String(repo_root)), ".candidate-path-sentinel"),
        )
        resolved = normpath(joinpath(root, text))
        prefix = root * Base.Filesystem.path_separator
        (resolved == root || startswith(resolved, prefix)) ||
            throw(ArgumentError("candidate path escapes the repository root"))
        return resolved
    end

    function expect_sha256(value, location)
        text = String(value)
        occursin(r"^[0-9a-f]{64}$", text) ||
            throw(ArgumentError("$location must be a lowercase SHA-256"))
        return text
    end

    function validate_file_hash(path, expected, location)
        isfile(path) || throw(ArgumentError("$location is missing: $path"))
        actual = file_sha256(path)
        actual == expect_sha256(expected, "$location.sha256") ||
            throw(ArgumentError("$location SHA-256 mismatch"))
        return actual
    end

    function validate_bound_path(
            repo_root,
            configured_path,
            expected_relative_path,
            location,
        )
        actual = checked_relative_path(repo_root, configured_path)
        expected =
            checked_relative_path(repo_root, expected_relative_path)
        actual == expected ||
            throw(
            ArgumentError(
                "$location must bind $expected_relative_path",
            ),
        )
        return actual
    end

    function load_build_config(
            path::AbstractString;
            repo_root::AbstractString = normpath(
                joinpath(@__DIR__, "..", "..", ".."),
            ),
        )
        config = TOML.parsefile(path)
        get(config, "schema_version", "") == BUILD_SCHEMA ||
            throw(ArgumentError("unsupported candidate-build schema"))
        get(config, "classification", "") ==
            "REVISED_CURRENT_VINTAGE_DIAGNOSTIC" ||
            throw(ArgumentError("candidate classification is not fail-closed"))
        get(config, "promotion_status", "") ==
            "RESEARCH_ONLY_NOT_PROMOTED" ||
            throw(ArgumentError("candidate promotion status is not fail-closed"))
        get(config, "forecast_origin_admissible", true) === false ||
            throw(ArgumentError("candidate must not be origin-admissible"))
        Float64(get(config, "scale", NaN)) > 0 ||
            throw(ArgumentError("candidate scale must be positive"))
        get(config, "opening_macro_control_source", "") == CONTROL_SOURCE ||
            throw(ArgumentError("candidate opening-control source mismatch"))
        Float64(
            get(
                config,
                "opening_macro_control_absolute_tolerance",
                NaN,
            ),
        ) == SOURCE_TOLERANCE ||
            throw(ArgumentError("candidate source tolerance mismatch"))
        validate_execution_envelope_table(
            get(config, "execution_envelope", nothing),
            "candidate execution_envelope",
        )
        get(config, "runtime_source_tree_digest_algorithm", "") ==
            SOURCE_TREE_DIGEST_ALGORITHM ||
            throw(
            ArgumentError(
                "candidate runtime source-tree digest algorithm mismatch",
            ),
        )

        candidates = get(config, "candidate", Any[])
        isempty(candidates) &&
            throw(ArgumentError("candidate configuration is empty"))
        candidate_ids = String[
            String(candidate["candidate_id"]) for candidate in candidates
        ]
        length(unique(candidate_ids)) == length(candidate_ids) ||
            throw(ArgumentError("candidate identifiers must be unique"))
        output_paths =
            String[String(candidate["output_path"]) for candidate in candidates]
        length(unique(output_paths)) == length(output_paths) ||
            throw(ArgumentError("candidate output paths must be unique"))

        protected = get(config, "protected_artifact", Any[])
        isempty(protected) &&
            throw(ArgumentError("candidate configuration has no protected artifacts"))
        protected_paths = Set(
            checked_relative_path(repo_root, artifact["path"])
                for artifact in protected
        )
        resolved_output_paths = Set(
            checked_relative_path(repo_root, output_path)
                for output_path in output_paths
        )
        isempty(intersect(protected_paths, resolved_output_paths)) ||
            throw(
            ArgumentError(
                "candidate output path collides with a protected legacy artifact",
            ),
        )
        candidate_output_root =
            checked_relative_path(repo_root, "data/us/accounting/candidates")
        output_prefix =
            candidate_output_root * Base.Filesystem.path_separator
        all(
            path -> startswith(path, output_prefix) &&
                splitext(path)[2] == ".jld2",
            resolved_output_paths,
        ) ||
            throw(
            ArgumentError(
                "candidate outputs must be JLD2 files under data/us/accounting/candidates",
            ),
        )
        manifest_path = checked_relative_path(
            repo_root,
            config["validation_manifest_path"],
        )
        validation_root =
            checked_relative_path(repo_root, "data/us/validation")
        manifest_prefix =
            validation_root * Base.Filesystem.path_separator
        startswith(manifest_path, manifest_prefix) &&
            splitext(manifest_path)[2] == ".toml" ||
            throw(
            ArgumentError(
                "candidate manifest must be a TOML file under data/us/validation",
            ),
        )
        manifest_path in protected_paths &&
            throw(
            ArgumentError(
                "candidate manifest collides with a protected legacy artifact",
            ),
        )
        manifest_path in resolved_output_paths &&
            throw(
            ArgumentError(
                "candidate manifest collides with a candidate artifact",
            ),
        )

        for (key, hash_key) in (
                (
                    "t10105_fixture_directory",
                    "t10105_manifest_sha256",
                ),
                (
                    "supply_make_fixture_directory",
                    "supply_make_manifest_sha256",
                ),
            )
            directory = checked_relative_path(repo_root, config[key])
            validate_file_hash(
                joinpath(directory, "manifest.toml"),
                config[hash_key],
                hash_key,
            )
        end
        t10105_directory =
            checked_relative_path(repo_root, config["t10105_fixture_directory"])
        validate_file_hash(
            joinpath(t10105_directory, "quarterly_controls.csv"),
            config["t10105_controls_sha256"],
            "t10105_controls",
        )
        supply_directory = checked_relative_path(
            repo_root,
            config["supply_make_fixture_directory"],
        )
        validate_file_hash(
            joinpath(supply_directory, "cells.csv"),
            config["supply_make_cells_sha256"],
            "supply_make_cells",
        )
        mapping_path =
            checked_relative_path(repo_root, config["sector_mapping_path"])
        validate_file_hash(
            mapping_path,
            config["sector_mapping_sha256"],
            "sector_mapping",
        )
        for (path_key, hash_key, location) in (
                (
                    "builder_path",
                    "builder_sha256",
                    "candidate_builder",
                ),
                (
                    "execution_envelope_module_path",
                    "execution_envelope_module_sha256",
                    "candidate_execution_envelope_module",
                ),
                (
                    "supply_make_reader_path",
                    "supply_make_reader_sha256",
                    "candidate_supply_make_reader",
                ),
                (
                    "t10105_reader_path",
                    "t10105_reader_sha256",
                    "candidate_t10105_reader",
                ),
                (
                    "julia_project_path",
                    "julia_project_sha256",
                    "candidate_julia_project",
                ),
                (
                    "julia_manifest_path",
                    "julia_manifest_sha256",
                    "candidate_julia_manifest",
                ),
            )
            environment_path = validate_bound_path(
                repo_root,
                config[path_key],
                EXECUTABLE_INPUT_PATHS[path_key],
                location,
            )
            validate_file_hash(
                environment_path,
                config[hash_key],
                location,
            )
        end
        builder_path = checked_relative_path(repo_root, config["builder_path"])
        builder_path == normpath(abspath(@__FILE__)) ||
            throw(
            ArgumentError(
                "candidate builder binding differs from executing source",
            ),
        )
        active_project = Base.active_project()
        active_project === nothing &&
            throw(ArgumentError("candidate Julia project is not active"))
        normpath(abspath(active_project)) ==
            checked_relative_path(repo_root, config["julia_project_path"]) ||
            throw(
            ArgumentError(
                "candidate Julia project binding differs from active project",
            ),
        )
        runtime_source_tree = validate_bound_path(
            repo_root,
            config["runtime_source_tree_path"],
            "src",
            "candidate_runtime_source_tree",
        )
        digest = source_tree_digest(runtime_source_tree)
        raw_file_count = get(config, "runtime_source_tree_file_count", nothing)
        raw_file_count isa Integer && !(raw_file_count isa Bool) ||
            throw(
            ArgumentError(
                "candidate runtime source-tree file count must be an integer",
            ),
        )
        Int(raw_file_count) == digest.file_count ||
            throw(
            ArgumentError(
                "candidate runtime source-tree file count mismatch",
            ),
        )
        digest.sha256 ==
            expect_sha256(
            get(config, "runtime_source_tree_sha256", ""),
            "candidate runtime source tree",
        ) ||
            throw(
            ArgumentError(
                "candidate runtime source-tree SHA-256 mismatch",
            ),
        )

        for artifact in protected
            artifact_path =
                checked_relative_path(repo_root, artifact["path"])
            validate_file_hash(
                artifact_path,
                artifact["sha256"],
                String(artifact["artifact_role"]),
            )
        end
        for candidate in candidates
            Date(String(candidate["origin_period"]))
            seed = candidate["diagnostic_seed"]
            seed isa Integer && !(seed isa Bool) ||
                throw(ArgumentError("diagnostic seed must be an integer"))
            base_path = checked_relative_path(
                repo_root,
                candidate["base_calibration_path"],
            )
            validate_file_hash(
                base_path,
                candidate["base_calibration_sha256"],
                "$(candidate["candidate_id"]).base_calibration",
            )
            checked_relative_path(repo_root, candidate["output_path"])
        end
        VERIFIED_CONFIG_RECEIPTS[config] = (
            path = normpath(abspath(path)),
            sha256 = file_sha256(path),
            semantic_sha256 = semantic_sha256(config),
        )
        return config
    end

    function _semantic_write(io::IO, value)
        if value isa AbstractDict
            entries =
                sort!(collect(pairs(value)); by = pair -> String(first(pair)))
            print(io, "M", length(entries), "{")
            for (key, entry) in entries
                _semantic_write(io, String(key))
                _semantic_write(io, entry)
            end
            print(io, "}")
        elseif value isa NamedTuple
            print(io, "N", length(value), "{")
            for name in keys(value)
                _semantic_write(io, String(name))
                _semantic_write(io, getproperty(value, name))
            end
            print(io, "}")
        elseif value isa AbstractArray
            print(io, "A", string(eltype(value)), ":", join(size(value), ","), "[")
            for entry in value
                _semantic_write(io, entry)
            end
            print(io, "]")
        elseif value isa Tuple
            print(io, "T", length(value), "[")
            for entry in value
                _semantic_write(io, entry)
            end
            print(io, "]")
        elseif value isa AbstractString
            bytes = codeunits(String(value))
            print(io, "S", length(bytes), ":")
            write(io, bytes)
        elseif value isa Symbol
            _semantic_write(io, String(value))
        elseif value isa Bool
            print(io, value ? "B1" : "B0")
        elseif value isa AbstractFloat
            print(io, "F", string(typeof(value)), ":", bitstring(value))
        elseif value isa Integer
            print(io, "I", string(typeof(value)), ":", value, ";")
        elseif value isa Nothing
            print(io, "Z")
        elseif value isa Date || value isa DateTime
            print(io, "D", string(typeof(value)), ":")
            _semantic_write(io, string(value))
        else
            throw(
                ArgumentError(
                    "unsupported semantic-hash value type $(typeof(value))",
                ),
            )
        end
        return io
    end

    function semantic_sha256(value)
        io = IOBuffer()
        _semantic_write(io, value)
        return sha256_hex(take!(io))
    end

    function source_aware_calibration(
            base::Bit.CalibrationData,
            t10105_fixture,
            supply_make_fixture,
            sector_mapping,
            config,
        )
        report = diagnose_supply_make(
            supply_make_fixture.use,
            supply_make_fixture.supply;
            expected_supply_commodity_count = 73,
            expected_supply_industry_count = 71,
            expected_use_commodity_count = 70,
        )
        controls_pass(report) ||
            throw(
            ArgumentError(
                "candidate supply/make fixture fails published source controls",
            ),
        )
        length(report.residuals) == 755 ||
            throw(
            ArgumentError(
                "candidate supply/make report must contain 755 controls",
            ),
        )

        model_codes = String.(sector_mapping["model"]["codes"])
        length(model_codes) == 68 ||
            throw(ArgumentError("candidate mapping must contain 68 sectors"))
        Set(report.commodity_output.codes) ==
            union(Set(model_codes), Set(["Other", "Used"])) ||
            throw(
            ArgumentError(
                "candidate commodity-output codes do not match the model core",
            ),
        )
        Set(report.industry_output.codes) == Set(model_codes) ||
            throw(
            ArgumentError(
                "candidate industry-output codes do not match the model core",
            ),
        )
        commodity_output =
            Float64[report.commodity_output[code] for code in model_codes]
        industry_output_t017 =
            Float64[report.industry_output[code] for code in model_codes]
        industry_output_t018 = Float64[
            sum(
                    cell_value(
                        supply_make_fixture.use,
                        "T018",
                        source_code;
                        required = true,
                    )
                    for source_code in
                    (
                        code == "4A0" ?
                        ("441", "445", "452", "4A0") :
                        (code,)
                    )
                )
                for code in model_codes
        ]
        maximum(abs, industry_output_t017 - industry_output_t018) <= 2.0 ||
            throw(
            ArgumentError(
                "candidate Table 262 T017 and Table 259 T018 controls diverge",
            ),
        )

        figaro = deepcopy(base.figaro)
        figaro["use_explicit_commodity_output"] = true
        figaro["diagnose_commodity_balance"] = true
        figaro["use_commodity_balance_inventory"] = false
        figaro["domestic_commodity_output_basic_price"] =
            reshape(commodity_output, :, 1)
        figaro["commodity_output_codes"] = copy(model_codes)
        figaro["commodity_output_basis"] =
            "BEA_TABLE_262_T007_COMMODITY_BASIC_PRICE"
        figaro["industry_output_codes"] = copy(model_codes)
        figaro["industry_output_basis"] =
            "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE"
        figaro["source_industry_output_basic_price"] =
            reshape(industry_output_t018, :, 1)
        figaro["supply_industry_output_basis"] =
            "BEA_TABLE_262_T017_INDUSTRY_BASIC_PRICE"
        figaro["supply_industry_output_basic_price_t017"] =
            reshape(industry_output_t017, :, 1)
        figaro["use_opening_macro_controls"] = true
        figaro["opening_macro_control_source"] =
            String(config["opening_macro_control_source"])
        figaro["opening_macro_control_unit"] =
            Bit.OPENING_MACRO_CONTROL_UNIT
        figaro["opening_macro_control_absolute_tolerance"] =
            Float64(config["opening_macro_control_absolute_tolerance"])

        data = deepcopy(base.data)
        periods = Date.(Bit.num2date.(data["quarters_num"]))
        periods == t10105_fixture.frame.period ||
            throw(
            ArgumentError(
                "base calibration and T10105 fixture quarter axes differ",
            ),
        )
        data["nominal_gdp_quarterly"] ==
            t10105_fixture.frame.nominal_gdp_quarterly ||
            throw(
            ArgumentError(
                "base nominal GDP differs from the pinned T10105 fixture",
            ),
        )
        merge!(
            data,
            materialize_control_series(t10105_fixture.frame, periods),
        )
        object = Bit.CalibrationData(
            deepcopy(base.calibration),
            figaro,
            data,
            deepcopy(base.ea),
            base.max_calibration_date,
            base.estimation_date,
        )
        provenance = Dict{String, Any}(
            "source_controls_pass" => true,
            "supply_make_control_count" => length(report.residuals),
            "supply_make_controls_pass" => true,
            "balancing_applied" => report.balancing_applied,
            "transformation" => String(report.transformation),
            "modeled_commodity_output_sum" => sum(commodity_output),
            "table_259_industry_output_sum" => sum(industry_output_t018),
            "table_262_industry_output_sum" => sum(industry_output_t017),
            "other_and_used_allocation" =>
                "EXPLICIT_UNALLOCATED_CLOSURE_ACCOUNTS",
        )
        return (; object, provenance)
    end

    function core_source_values(controls)
        return Dict{String, Float64}(
            "nominal_gdp" => controls.nominal_gdp,
            "nominal_household_consumption" =>
                controls.nominal_household_consumption,
            "nominal_government_consumption_and_investment" =>
                controls.nominal_government_consumption_and_investment,
            "nominal_gross_private_domestic_investment" =>
                controls.nominal_capitalformation,
            "nominal_fixed_investment" =>
                controls.nominal_fixed_capitalformation,
            "nominal_inventory_investment" =>
                controls.nominal_inventory_investment,
            "nominal_exports" => controls.nominal_exports,
            "nominal_imports" => controls.nominal_imports,
        )
    end

    function core_model_values(implied)
        return Dict{String, Float64}(
            "nominal_gdp" => implied.nominal_gdp,
            "nominal_household_consumption" =>
                implied.nominal_household_consumption,
            "nominal_government_consumption_and_investment" =>
                implied.nominal_government_consumption,
            "nominal_gross_private_domestic_investment" =>
                implied.nominal_capitalformation,
            "nominal_fixed_investment" =>
                implied.nominal_fixed_capitalformation,
            "nominal_inventory_investment" =>
                implied.nominal_capitalformation -
                implied.nominal_fixed_capitalformation,
            "nominal_exports" => implied.nominal_exports,
            "nominal_imports" => implied.nominal_imports,
        )
    end

    function core_observed_values(model)
        data = model.data
        return Dict{String, Float64}(
            "nominal_gdp" => first(data.nominal_gdp),
            "nominal_household_consumption" =>
                first(data.nominal_household_consumption),
            "nominal_government_consumption_and_investment" =>
                first(data.nominal_government_consumption),
            "nominal_gross_private_domestic_investment" =>
                first(data.nominal_capitalformation),
            "nominal_fixed_investment" =>
                first(data.nominal_fixed_capitalformation),
            "nominal_inventory_investment" =>
                first(data.nominal_inventory_investment),
            "nominal_exports" => first(data.nominal_exports),
            "nominal_imports" => first(data.nominal_imports),
        )
    end

    function reconciliation_metadata(
            parameters,
            initial_conditions;
            diagnostic_seed::Int,
        )
        controls = Bit.validated_opening_macro_controls(initial_conditions)
        controls === nothing &&
            throw(ArgumentError("candidate is missing opening macro controls"))
        Random.seed!(diagnostic_seed)
        model = Bit.Model(
            deepcopy(parameters),
            deepcopy(initial_conditions),
        )
        implied = Bit.model_implied_opening_macro(model)
        source_values = core_source_values(controls)
        model_values = core_model_values(implied)
        observed_values = core_observed_values(model)
        model_minus_source = Dict(
            key => model_values[key] - source_values[key]
                for key in sort!(collect(keys(source_values)))
        )
        observed_minus_source = Dict(
            key => observed_values[key] - source_values[key]
                for key in sort!(collect(keys(source_values)))
        )
        maximum_component_gap = maximum(abs, values(model_minus_source))
        maximum_observation_gap =
            maximum(abs, values(observed_minus_source))
        observed_residuals = Bit.get_accounting_residuals(model.data)
        observed_expenditure_residual =
            first(observed_residuals.gdp_and_expenditure)
        observed_investment_residual =
            observed_values[
            "nominal_gross_private_domestic_investment",
        ] -
            observed_values["nominal_fixed_investment"] -
            observed_values["nominal_inventory_investment"]
        observation_pass =
            maximum_observation_gap <= MODEL_TOLERANCE &&
            abs(observed_expenditure_residual) <= controls.tolerance &&
            abs(observed_investment_residual) <= controls.tolerance
        observation_pass ||
            throw(
            ArgumentError(
                "candidate observation row does not match its source controls",
            ),
        )
        latent_pass =
            maximum_component_gap <= MODEL_TOLERANCE &&
            abs(implied.expenditure_residual) <= MODEL_TOLERANCE
        latent_pass &&
            throw(
            ArgumentError(
                "candidate unexpectedly reconciles the latent model state",
            ),
        )
        return Dict{String, Any}(
            "schema_version" => RECONCILIATION_SCHEMA,
            "diagnostic_seed" => diagnostic_seed,
            "source" => controls.source,
            "unit" => controls.unit,
            "source_rounding_tolerance" => controls.tolerance,
            "model_numeric_tolerance" => MODEL_TOLERANCE,
            "observation_layer_gate" => "PASS_AT_SOURCE_ROUNDING",
            "latent_state_reconciliation_gate" => "FAIL",
            "structural_supply_use_gate" => "FAIL",
            "inventory_stock_gate" =>
                "FAIL_MISSING_INDEPENDENT_QUARTER_END_STOCK",
            "full_accounting_gate" => "FAIL",
            "forecast_promotion_gate" => "FAIL",
            "source_values" => source_values,
            "observed_values" => observed_values,
            "model_implied_values" => model_values,
            "observed_minus_source" => observed_minus_source,
            "model_minus_source" => model_minus_source,
            "source_expenditure_residual" =>
                controls.expenditure_residual,
            "source_private_investment_residual" =>
                controls.investment_residual,
            "observed_expenditure_residual" =>
                observed_expenditure_residual,
            "observed_private_investment_residual" =>
                observed_investment_residual,
            "model_implied_expenditure_residual" =>
                implied.expenditure_residual,
            "maximum_absolute_observation_gap" =>
                maximum_observation_gap,
            "maximum_absolute_component_gap" =>
                maximum_component_gap,
            "opening_fixed_dwellings_projection" =>
                controls.nominal_fixed_capitalformation_dwellings,
            "opening_fixed_dwellings_treatment" =>
                "STRUCTURAL_SHARE_PROJECTION_NOT_INDEPENDENT_SOURCE_CONTROL",
            "inventory_stock_status" =>
                "MISSING_INDEPENDENT_QUARTER_END_STOCK",
            "note" =>
                "The observed first row is source-anchored. The separately " *
                "reported model-implied row retains the latent state/demand " *
                "wedge; observation anchoring does not reconcile or promote it.",
        )
    end

    function compare_with_legacy(
            base,
            parameters,
            initial_conditions,
            origin,
            scale,
        )
        legacy_parameters, legacy_initial_conditions =
            Bit.get_params_and_initial_conditions(
            base,
            origin;
            scale,
            use_growth_rate_ar1 = false,
        )
        parameter_keys = Set(keys(parameters))
        legacy_parameter_keys = Set(keys(legacy_parameters))
        parameter_keys == legacy_parameter_keys ||
            throw(
            ArgumentError(
                "candidate changed the calibrated parameter key set",
            ),
        )
        get(legacy_parameters, "use_commodity_balance_inventory", false) ===
            true ||
            throw(
            ArgumentError(
                "legacy input does not enable commodity-balance inventory",
            ),
        )
        get(parameters, "use_commodity_balance_inventory", true) ===
            false ||
            throw(
            ArgumentError(
                "candidate did not disable commodity-balance inventory",
            ),
        )
        parameter_exclusions = Set(["use_commodity_balance_inventory"])
        shared_parameter_keys =
            setdiff(parameter_keys, parameter_exclusions)
        all(
            key -> isequal(parameters[key], legacy_parameters[key]),
            shared_parameter_keys,
        ) ||
            throw(
            ArgumentError(
                "candidate changed an unaffected calibrated parameter",
            ),
        )
        candidate_initial_keys = Set(keys(initial_conditions))
        legacy_initial_keys = Set(keys(legacy_initial_conditions))
        removed_initial_keys =
            setdiff(legacy_initial_keys, candidate_initial_keys)
        added_initial_keys =
            setdiff(candidate_initial_keys, legacy_initial_keys)
        removed_initial_keys == REJECTED_INVENTORY_ALIAS_KEYS ||
            throw(
            ArgumentError(
                "candidate initial-condition removals differ from the approved inventory aliases",
            ),
        )
        expected_added_initial_keys =
            union(OPENING_CONTROL_KEYS, Set(["commodity_output_codes"]))
        added_initial_keys == expected_added_initial_keys ||
            throw(
            ArgumentError(
                "candidate initial-condition additions differ from the approved source-control fields",
            ),
        )
        initial_exclusions =
            union(LEGACY_COMMODITY_KEYS, OPENING_CONTROL_KEYS)
        shared_initial_keys = setdiff(
            intersect(
                candidate_initial_keys,
                legacy_initial_keys,
            ),
            initial_exclusions,
        )
        all(
            key -> isequal(
                initial_conditions[key],
                legacy_initial_conditions[key],
            ),
            shared_initial_keys,
        ) ||
            throw(
            ArgumentError(
                "candidate changed an unaffected initial condition",
            ),
        )
        return Dict{String, Any}(
            "unaffected_parameters_bit_identical" => true,
            "unaffected_parameter_count" => length(shared_parameter_keys),
            "unaffected_initial_conditions_bit_identical" => true,
            "unaffected_initial_condition_count" =>
                length(shared_initial_keys),
            "removed_initial_condition_keys" =>
                sort!(collect(removed_initial_keys)),
            "added_initial_condition_keys" =>
                sort!(collect(added_initial_keys)),
            "intentional_parameter_change" =>
                "use_commodity_balance_inventory=true_to_false",
            "intentional_initial_condition_changes" => [
                "remove_discrepancy_derived_S_s_and_inventory_aliases",
                "add_unreconciled_T007_commodity_gap_diagnostic",
                "add_source_anchored_opening_observation_controls",
            ],
        )
    end

    function simulated_accounting_metadata(
            parameters,
            initial_conditions;
            diagnostic_seed::Int,
        )
        Random.seed!(diagnostic_seed)
        model = Bit.Model(
            deepcopy(parameters),
            deepcopy(initial_conditions),
        )
        Bit.run!(model, SIMULATED_QUARTERS; parallel = false)
        residuals = Bit.get_accounting_residuals(model.data)
        maximum_nominal_after_opening =
            maximum(abs, residuals.gdp_and_expenditure[2:end])
        maximum_real_after_opening =
            maximum(abs, residuals.gdp_and_expenditure_real[2:end])
        maximum_income =
            maximum(abs, residuals.income_and_production)
        maximum_nominal_after_opening <= MODEL_TOLERANCE ||
            throw(
            ArgumentError(
                "candidate simulated nominal accounting identity fails",
            ),
        )
        maximum_real_after_opening <= MODEL_TOLERANCE ||
            throw(
            ArgumentError(
                "candidate simulated real accounting identity fails",
            ),
        )
        maximum_income <= MODEL_TOLERANCE ||
            throw(
            ArgumentError(
                "candidate simulated income identity fails",
            ),
        )
        return Dict{String, Any}(
            "gate" => "PASS_AFTER_OPENING",
            "simulated_quarters" => SIMULATED_QUARTERS,
            "diagnostic_seed" => diagnostic_seed,
            "maximum_nominal_gdp_expenditure_residual_after_opening" =>
                maximum_nominal_after_opening,
            "maximum_real_gdp_expenditure_residual_after_opening" =>
                maximum_real_after_opening,
            "maximum_income_production_residual" => maximum_income,
            "model_numeric_tolerance" => MODEL_TOLERANCE,
        )
    end

    function build_candidate(
            config,
            candidate;
            repo_root::AbstractString = normpath(
                joinpath(@__DIR__, "..", "..", ".."),
            ),
            config_sha256::AbstractString = "",
            execution_mode::CandidateBuildMode = CANONICAL_BYTE_BUILD,
        )
        config_hash =
            expect_sha256(config_sha256, "candidate build contract")
        haskey(VERIFIED_CONFIG_RECEIPTS, config) ||
            throw(
            ArgumentError(
                "candidate build configuration lacks a verified file receipt",
            ),
        )
        config_receipt = VERIFIED_CONFIG_RECEIPTS[config]
        config_receipt.sha256 == config_hash ||
            throw(
            ArgumentError(
                "candidate build-contract SHA-256 differs from its verified receipt",
            ),
        )
        config_receipt.semantic_sha256 == semantic_sha256(config) ||
            throw(
            ArgumentError(
                "candidate build configuration changed after verification",
            ),
        )
        config_receipt.path ==
            checked_relative_path(
            repo_root,
            "scripts/us/accounting/opening_macro_candidates.toml",
        ) ||
            throw(
            ArgumentError(
                "candidate build contract is not the governed repository contract",
            ),
        )
        execution_assessment =
        if execution_mode == CANONICAL_BYTE_BUILD
            validate_build_environment(config)
            USJuliaExecutionEnvelope.assess_execution_envelope(config)
        else
            validate_portable_semantic_environment(config)
        end
        execution_envelope = execution_assessment.actual
        base_path = checked_relative_path(
            repo_root,
            candidate["base_calibration_path"],
        )
        base_sha256 = validate_file_hash(
            base_path,
            candidate["base_calibration_sha256"],
            "base_calibration",
        )
        payload = JLD2.load(base_path)
        Set(keys(payload)) == Set(["calibration_object", "metadata"]) ||
            throw(ArgumentError("base calibration artifact has unexpected keys"))
        base = payload["calibration_object"]
        base isa Bit.CalibrationData ||
            throw(ArgumentError("base artifact does not contain CalibrationData"))

        t10105_directory =
            checked_relative_path(repo_root, config["t10105_fixture_directory"])
        supply_directory = checked_relative_path(
            repo_root,
            config["supply_make_fixture_directory"],
        )
        mapping_path =
            checked_relative_path(repo_root, config["sector_mapping_path"])
        t10105_fixture = load_t10105_fixture(t10105_directory)
        supply_make_fixture = load_canonical_fixture(supply_directory)
        sector_mapping = TOML.parsefile(mapping_path)
        calibration = source_aware_calibration(
            base,
            t10105_fixture,
            supply_make_fixture,
            sector_mapping,
            config,
        )
        origin = DateTime(Date(String(candidate["origin_period"])))
        scale = Float64(config["scale"])
        parameters, initial_conditions =
            Bit.get_params_and_initial_conditions(
            calibration.object,
            origin;
            scale,
            use_growth_rate_ar1 = false,
        )
        diagnostic_seed = Int(candidate["diagnostic_seed"])
        reconciliation = reconciliation_metadata(
            parameters,
            initial_conditions;
            diagnostic_seed,
        )
        legacy_comparison = compare_with_legacy(
            base,
            parameters,
            initial_conditions,
            origin,
            scale,
        )
        simulation = simulated_accounting_metadata(
            parameters,
            initial_conditions;
            diagnostic_seed,
        )
        present_inventory_aliases = intersect(
            Set(keys(initial_conditions)),
            REJECTED_INVENTORY_ALIAS_KEYS,
        )
        isempty(present_inventory_aliases) ||
            throw(
            ArgumentError(
                "candidate contains rejected inventory aliases: " *
                    join(sort!(collect(present_inventory_aliases)), ", "),
            ),
        )
        get(
            initial_conditions,
            "commodity_balance_closure_applied",
            true,
        ) === false ||
            throw(ArgumentError("candidate applies a commodity closure"))
        unreconciled_gap = initial_conditions["unreconciled_commodity_gap_g"]

        metadata = Dict{String, Any}(
            "schema_version" => CANDIDATE_SCHEMA,
            "candidate_id" => String(candidate["candidate_id"]),
            "kind" => String(candidate["kind"]),
            "origin_period" => string(Date(origin)),
            "classification" => String(config["classification"]),
            "promotion_status" => String(config["promotion_status"]),
            "forecast_origin_admissible" => false,
            "build_contract_path" =>
                relpath(config_receipt.path, repo_root),
            "build_contract_sha256" => config_hash,
            "build_environment" => merge(
                execution_envelope,
                Dict{String, Any}(
                    "execution_validation_mode" =>
                        string(execution_mode),
                    "canonical_execution_envelope_match" =>
                        execution_assessment.canonical_match,
                    "canonical_execution_envelope_mismatches" =>
                        copy(execution_assessment.mismatches),
                    "declared_canonical_execution_envelope" =>
                        deepcopy(execution_assessment.expected),
                    "byte_identity_eligible" =>
                        execution_mode == CANONICAL_BYTE_BUILD,
                    "builder_path" => String(config["builder_path"]),
                    "builder_sha256" => String(config["builder_sha256"]),
                    "execution_envelope_module_path" =>
                        String(config["execution_envelope_module_path"]),
                    "execution_envelope_module_sha256" =>
                        String(config["execution_envelope_module_sha256"]),
                    "supply_make_reader_path" =>
                        String(config["supply_make_reader_path"]),
                    "supply_make_reader_sha256" =>
                        String(config["supply_make_reader_sha256"]),
                    "t10105_reader_path" =>
                        String(config["t10105_reader_path"]),
                    "t10105_reader_sha256" =>
                        String(config["t10105_reader_sha256"]),
                    "julia_project_path" =>
                        String(config["julia_project_path"]),
                    "julia_project_sha256" =>
                        String(config["julia_project_sha256"]),
                    "julia_manifest_path" =>
                        String(config["julia_manifest_path"]),
                    "julia_manifest_sha256" =>
                        String(config["julia_manifest_sha256"]),
                    "runtime_source_tree_path" =>
                        String(config["runtime_source_tree_path"]),
                    "runtime_source_tree_digest_algorithm" =>
                        String(
                        config[
                            "runtime_source_tree_digest_algorithm",
                        ],
                    ),
                    "runtime_source_tree_file_count" =>
                        Int(config["runtime_source_tree_file_count"]),
                    "runtime_source_tree_sha256" =>
                        String(config["runtime_source_tree_sha256"]),
                    "thread_contract" =>
                        "single_thread_julia_and_blas",
                    "byte_reproducibility_scope" =>
                        BYTE_REPRODUCIBILITY_SCOPE,
                    "cross_machine_byte_determinism_claimed" => false,
                ),
            ),
            "base_calibration" => Dict{String, Any}(
                "path" => String(candidate["base_calibration_path"]),
                "sha256" => base_sha256,
                "role" => "FROZEN_LEGACY_RESEARCH_INPUT",
            ),
            "source_controls" => Dict{String, Any}(
                "fixture_directory" =>
                    String(config["t10105_fixture_directory"]),
                "manifest_sha256" =>
                    String(config["t10105_manifest_sha256"]),
                "controls_sha256" =>
                    String(config["t10105_controls_sha256"]),
                "raw_source_sha256" =>
                    UST10105Controls.APPROVED_SOURCE_SHA256,
                "raw_source_metadata_sha256" =>
                    UST10105Controls.APPROVED_SOURCE_METADATA_SHA256,
                "information_track" =>
                    "REVISED_MIXED_VINTAGE_DIAGNOSTIC",
                "origin_admissible" => false,
            ),
            "supply_make" => merge(
                calibration.provenance,
                Dict{String, Any}(
                    "fixture_directory" =>
                        String(config["supply_make_fixture_directory"]),
                    "manifest_sha256" =>
                        String(config["supply_make_manifest_sha256"]),
                    "cells_sha256" =>
                        String(config["supply_make_cells_sha256"]),
                    "sector_mapping_sha256" =>
                        String(config["sector_mapping_sha256"]),
                ),
            ),
            "opening_macro_reconciliation" => reconciliation,
            "legacy_comparison" => legacy_comparison,
            "simulated_accounting" => simulation,
            "commodity_diagnostic" => Dict{String, Any}(
                "interpretation" =>
                    "SIGNED_UNRECONCILED_COMMODITY_MEASUREMENT_GAP",
                "annual_sum" => sum(unreconciled_gap),
                "closure_applied" => false,
                "mapped_to_inventory_flow" => false,
                "mapped_to_inventory_stock" => false,
            ),
            "gate_split" => Dict{String, Any}(
                "opening_macro_control_identity" =>
                    "PASS_AT_SOURCE_ROUNDING",
                "latent_state_reconciliation" => "FAIL",
                "structural_supply_use" => "FAIL",
                "inventory_stock" =>
                    "FAIL_MISSING_INDEPENDENT_QUARTER_END_STOCK",
                "overall_accounting_promotion" => "FAIL",
                "forecast_promotion" => "FAIL",
            ),
        )
        semantic_payload = Dict{String, Any}(
            "parameters" => parameters,
            "initial_conditions" => initial_conditions,
            "metadata" => metadata,
        )
        semantic_hash = semantic_sha256(semantic_payload)
        metadata["semantic_sha256"] = semantic_hash
        result = (;
            parameters,
            initial_conditions,
            metadata,
            semantic_sha256 = semantic_hash,
        )
        validate_candidate(result)
        return result
    end

    function validate_candidate(result)
        metadata = result.metadata
        get(metadata, "schema_version", "") == CANDIDATE_SCHEMA ||
            throw(ArgumentError("candidate metadata schema mismatch"))
        get(metadata, "promotion_status", "") ==
            "RESEARCH_ONLY_NOT_PROMOTED" ||
            throw(ArgumentError("candidate promotion status is unsafe"))
        get(metadata, "forecast_origin_admissible", true) === false ||
            throw(ArgumentError("candidate is incorrectly origin-admissible"))
        environment = metadata["build_environment"]
        recorded_envelope =
            validate_runtime_execution_envelope_table(
            Dict{String, Any}(
                key => get(environment, key, nothing)
                    for key in EXECUTION_ENVELOPE_KEYS
            ),
            "candidate recorded execution envelope",
        )
        declared_envelope = validate_execution_envelope_table(
            get(
                environment,
                "declared_canonical_execution_envelope",
                nothing,
            ),
            "candidate declared canonical execution envelope",
        )
        recorded_mismatches = String[
            "$key expected $(repr(declared_envelope[key])) got " *
                repr(recorded_envelope[key])
                for key in EXECUTION_ENVELOPE_KEYS
                if !isequal(declared_envelope[key], recorded_envelope[key])
        ]
        declared_mismatches = get(
            environment,
            "canonical_execution_envelope_mismatches",
            nothing,
        )
        declared_mismatches isa AbstractVector &&
            all(entry -> entry isa AbstractString, declared_mismatches) ||
            throw(
            ArgumentError(
                "candidate execution-envelope mismatches must be strings",
            ),
        )
        String.(declared_mismatches) == recorded_mismatches ||
            throw(
            ArgumentError(
                "candidate execution-envelope mismatches are inconsistent",
            ),
        )
        canonical_match =
            get(environment, "canonical_execution_envelope_match", nothing)
        canonical_match isa Bool ||
            throw(
            ArgumentError(
                "candidate canonical execution-envelope match must be Boolean",
            ),
        )
        canonical_match == isempty(recorded_mismatches) ||
            throw(
            ArgumentError(
                "candidate canonical execution-envelope match is inconsistent",
            ),
        )
        mode = get(environment, "execution_validation_mode", "")
        mode in (
            string(CANONICAL_BYTE_BUILD),
            string(PORTABLE_SEMANTIC_BUILD),
        ) ||
            throw(ArgumentError("candidate execution validation mode is invalid"))
        byte_identity_eligible =
            get(environment, "byte_identity_eligible", nothing)
        byte_identity_eligible isa Bool ||
            throw(
            ArgumentError(
                "candidate byte-identity eligibility must be Boolean",
            ),
        )
        if mode == string(CANONICAL_BYTE_BUILD)
            canonical_match ||
                throw(
                ArgumentError(
                    "canonical candidate recorded a noncanonical execution envelope",
                ),
            )
            byte_identity_eligible ||
                throw(
                ArgumentError(
                    "canonical candidate must remain byte-identity eligible",
                ),
            )
        else
            byte_identity_eligible &&
                throw(
                ArgumentError(
                    "portable semantic candidate must not be byte-identity eligible",
                ),
            )
            recorded_envelope["julia_thread_count"] == 1 ||
                throw(
                ArgumentError(
                    "portable semantic candidate must use one Julia thread",
                ),
            )
            recorded_envelope["blas_thread_count"] == 1 ||
                throw(
                ArgumentError(
                    "portable semantic candidate must use one BLAS thread",
                ),
            )
        end
        get(environment, "byte_reproducibility_scope", "") ==
            BYTE_REPRODUCIBILITY_SCOPE ||
            throw(
            ArgumentError(
                "candidate byte-reproducibility scope is missing",
            ),
        )
        get(
            environment,
            "cross_machine_byte_determinism_claimed",
            true,
        ) === false ||
            throw(
            ArgumentError(
                "candidate must not claim cross-machine byte determinism",
            ),
        )
        for (path_key, hash_key) in (
                ("builder_path", "builder_sha256"),
                (
                    "execution_envelope_module_path",
                    "execution_envelope_module_sha256",
                ),
                ("supply_make_reader_path", "supply_make_reader_sha256"),
                ("t10105_reader_path", "t10105_reader_sha256"),
                ("julia_project_path", "julia_project_sha256"),
                ("julia_manifest_path", "julia_manifest_sha256"),
            )
            get(environment, path_key, "") ==
                EXECUTABLE_INPUT_PATHS[path_key] ||
                throw(
                ArgumentError(
                    "candidate executable input path $path_key is invalid",
                ),
            )
            expect_sha256(
                get(environment, hash_key, ""),
                "candidate executable input $hash_key",
            )
        end
        get(environment, "runtime_source_tree_path", "") == "src" ||
            throw(ArgumentError("candidate runtime source-tree path is invalid"))
        get(
            environment,
            "runtime_source_tree_digest_algorithm",
            "",
        ) == SOURCE_TREE_DIGEST_ALGORITHM ||
            throw(
            ArgumentError(
                "candidate runtime source-tree digest algorithm is invalid",
            ),
        )
        source_file_count =
            get(environment, "runtime_source_tree_file_count", nothing)
        source_file_count isa Integer && !(source_file_count isa Bool) &&
            source_file_count > 0 ||
            throw(
            ArgumentError(
                "candidate runtime source-tree file count is invalid",
            ),
        )
        expect_sha256(
            get(environment, "runtime_source_tree_sha256", ""),
            "candidate runtime source tree",
        )
        gate_split = metadata["gate_split"]
        get(gate_split, "opening_macro_control_identity", "") ==
            "PASS_AT_SOURCE_ROUNDING" ||
            throw(ArgumentError("candidate observation gate does not pass"))
        for gate in (
                "latent_state_reconciliation",
                "structural_supply_use",
                "overall_accounting_promotion",
                "forecast_promotion",
            )
            get(gate_split, gate, "") == "FAIL" ||
                throw(ArgumentError("candidate $gate must remain failed"))
        end
        present_inventory_aliases = intersect(
            Set(keys(result.initial_conditions)),
            REJECTED_INVENTORY_ALIAS_KEYS,
        )
        isempty(present_inventory_aliases) ||
            throw(
            ArgumentError(
                "candidate unexpectedly contains rejected inventory aliases",
            ),
        )
        get(
            result.initial_conditions,
            "commodity_balance_closure_applied",
            true,
        ) === false ||
            throw(ArgumentError("candidate commodity gap was closed"))
        declared = String(metadata["semantic_sha256"])
        metadata_without_hash = deepcopy(metadata)
        delete!(metadata_without_hash, "semantic_sha256")
        computed = semantic_sha256(
            Dict{String, Any}(
                "parameters" => result.parameters,
                "initial_conditions" => result.initial_conditions,
                "metadata" => metadata_without_hash,
            ),
        )
        declared == computed == result.semantic_sha256 ||
            throw(ArgumentError("candidate semantic SHA-256 mismatch"))
        return result
    end

    function write_candidate(
            result,
            output_path::AbstractString;
            protected_paths = String[],
        )
        validate_candidate(result)
        get(
            result.metadata["build_environment"],
            "execution_validation_mode",
            "",
        ) == string(CANONICAL_BYTE_BUILD) ||
            throw(
            ArgumentError(
                "portable semantic candidates cannot be written as byte-golden artifacts",
            ),
        )
        target = abspath(normpath(String(output_path)))
        protected = union(
            INTRINSIC_PROTECTED_PATHS,
            Set(abspath.(normpath.(String.(protected_paths)))),
        )
        target in protected &&
            throw(
            ArgumentError(
                "refusing to overwrite a protected legacy artifact",
            ),
        )
        mkpath(dirname(target))
        temporary_path, io = mktemp(dirname(target))
        close(io)
        try
            jldopen(temporary_path, "w") do file
                file["parameters"] = result.parameters
                file["initial_conditions"] = result.initial_conditions
                file["metadata"] = result.metadata
            end
            loaded = JLD2.load(temporary_path)
            validate_candidate(
                (;
                    parameters = loaded["parameters"],
                    initial_conditions = loaded["initial_conditions"],
                    metadata = loaded["metadata"],
                    semantic_sha256 =
                        loaded["metadata"]["semantic_sha256"],
                ),
            )
            mv(temporary_path, target; force = true)
        finally
            isfile(temporary_path) && rm(temporary_path)
        end
        return (;
            path = target,
            raw_sha256 = file_sha256(target),
            semantic_sha256 = result.semantic_sha256,
        )
    end

    function candidate_manifest_entry(candidate, result, written, repo_root)
        reconciliation = result.metadata["opening_macro_reconciliation"]
        return Dict{String, Any}(
            "candidate_id" => String(candidate["candidate_id"]),
            "kind" => String(candidate["kind"]),
            "origin_period" => String(candidate["origin_period"]),
            "artifact_path" => relpath(written.path, repo_root),
            "artifact_sha256" => written.raw_sha256,
            "semantic_sha256" => written.semantic_sha256,
            "classification" => "REVISED_CURRENT_VINTAGE_DIAGNOSTIC",
            "origin_admissible" => false,
            "promotion_status" => "RESEARCH_ONLY_NOT_PROMOTED",
            "opening_macro_control_identity" =>
                "PASS_AT_SOURCE_ROUNDING",
            "latent_state_reconciliation" => "FAIL",
            "structural_supply_use" => "FAIL",
            "inventory_stock" =>
                "FAIL_MISSING_INDEPENDENT_QUARTER_END_STOCK",
            "overall_accounting_promotion" => "FAIL",
            "diagnostic_seed" => Int(candidate["diagnostic_seed"]),
            "source_expenditure_residual" =>
                reconciliation["source_expenditure_residual"],
            "observed_expenditure_residual" =>
                reconciliation["observed_expenditure_residual"],
            "model_implied_expenditure_residual" =>
                reconciliation["model_implied_expenditure_residual"],
            "maximum_absolute_component_gap" =>
                reconciliation["maximum_absolute_component_gap"],
            "unreconciled_commodity_gap_annual_sum" =>
                result.metadata["commodity_diagnostic"]["annual_sum"],
            "source_values" => reconciliation["source_values"],
            "model_implied_values" =>
                reconciliation["model_implied_values"],
            "model_minus_source" =>
                reconciliation["model_minus_source"],
        )
    end

    function snapshot_protected(config, repo_root)
        return Dict(
            String(artifact["path"]) => validate_file_hash(
                    checked_relative_path(repo_root, artifact["path"]),
                    artifact["sha256"],
                    String(artifact["artifact_role"]),
                )
                for artifact in config["protected_artifact"]
        )
    end

    function write_manifest(path, manifest)
        mkpath(dirname(path))
        temporary_path, io = mktemp(dirname(path))
        try
            TOML.print(io, manifest; sorted = true)
            close(io)
            mv(temporary_path, path; force = true)
        finally
            isopen(io) && close(io)
            isfile(temporary_path) && rm(temporary_path)
        end
        return path
    end

    function build_configured_candidates(
            config_path::AbstractString = joinpath(
                @__DIR__,
                "opening_macro_candidates.toml",
            );
            repo_root::AbstractString = normpath(
                joinpath(@__DIR__, "..", "..", ".."),
            ),
        )
        config = load_build_config(config_path; repo_root)
        execution_envelope = validate_build_environment(config)
        config_hash = file_sha256(config_path)
        before = snapshot_protected(config, repo_root)
        protected_paths = [
            checked_relative_path(repo_root, artifact["path"])
                for artifact in config["protected_artifact"]
        ]
        entries = Dict{String, Any}[]
        outputs = NamedTuple[]
        for candidate in config["candidate"]
            result = build_candidate(
                config,
                candidate;
                repo_root,
                config_sha256 = config_hash,
            )
            output_path =
                checked_relative_path(repo_root, candidate["output_path"])
            written = write_candidate(
                result,
                output_path;
                protected_paths,
            )
            push!(
                entries,
                candidate_manifest_entry(
                    candidate,
                    result,
                    written,
                    repo_root,
                ),
            )
            push!(outputs, (; result, written))
        end
        after = snapshot_protected(config, repo_root)
        before == after ||
            throw(ArgumentError("candidate build mutated a legacy artifact"))
        manifest = Dict{String, Any}(
            "schema_version" => MANIFEST_SCHEMA,
            "build_contract_path" => relpath(config_path, repo_root),
            "build_contract_sha256" => config_hash,
            "builder_path" => String(config["builder_path"]),
            "builder_sha256" => String(config["builder_sha256"]),
            "execution_envelope_module_path" =>
                String(config["execution_envelope_module_path"]),
            "execution_envelope_module_sha256" =>
                String(config["execution_envelope_module_sha256"]),
            "supply_make_reader_path" =>
                String(config["supply_make_reader_path"]),
            "supply_make_reader_sha256" =>
                String(config["supply_make_reader_sha256"]),
            "t10105_reader_path" =>
                String(config["t10105_reader_path"]),
            "t10105_reader_sha256" =>
                String(config["t10105_reader_sha256"]),
            "julia_project_path" => String(config["julia_project_path"]),
            "julia_project_sha256" =>
                String(config["julia_project_sha256"]),
            "julia_manifest_path" => String(config["julia_manifest_path"]),
            "julia_manifest_sha256" =>
                String(config["julia_manifest_sha256"]),
            "runtime_source_tree_path" =>
                String(config["runtime_source_tree_path"]),
            "runtime_source_tree_digest_algorithm" =>
                String(config["runtime_source_tree_digest_algorithm"]),
            "runtime_source_tree_file_count" =>
                Int(config["runtime_source_tree_file_count"]),
            "runtime_source_tree_sha256" =>
                String(config["runtime_source_tree_sha256"]),
            "execution_envelope" => execution_envelope,
            "byte_reproducibility_scope" =>
                BYTE_REPRODUCIBILITY_SCOPE,
            "cross_machine_byte_determinism_claimed" => false,
            "classification" => String(config["classification"]),
            "information_track" => "REVISED_MIXED_VINTAGE_DIAGNOSTIC",
            "forecast_origin_admissible" => false,
            "promotion_status" => String(config["promotion_status"]),
            "legacy_artifacts_unchanged" => true,
            "candidate_count" => length(entries),
            "candidate" => entries,
        )
        manifest_path =
            checked_relative_path(repo_root, config["validation_manifest_path"])
        write_manifest(manifest_path, manifest)
        return (; config, manifest, manifest_path, outputs)
    end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    using .USOpeningAccountingCandidate
    result =
        USOpeningAccountingCandidate.build_configured_candidates()
    println("Built ", length(result.outputs), " opening-accounting candidates")
    for output in result.outputs
        println("  ", output.written.path)
        println("    SHA-256: ", output.written.raw_sha256)
    end
    println("  manifest: ", result.manifest_path)
end
