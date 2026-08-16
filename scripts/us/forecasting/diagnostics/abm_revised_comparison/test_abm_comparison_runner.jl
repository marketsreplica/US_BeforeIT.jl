#!/usr/bin/env julia

# Runner regression tests for the ABM comparison.
#
# These cover the failure modes an external review reproduced against the previous
# runner: a cache that could be silently reused under a different calibration, a
# truncated run that still called itself a complete comparison, an --also-score
# source admitted on its variant label alone, and an origin that lost paths but
# still counted as whole. Each test asserts the refusal, not merely the absence of
# a wrong answer.
#
# The last test re-scores the committed v2 headline cache and asserts its
# score_summaries.csv is byte-identical to the committed file, which is what makes
# the published numbers auditable from this suite.

using SHA
using Test
using TOML

const HERE = @__DIR__
const REPO_ROOT = normpath(joinpath(HERE, "..", "..", "..", "..", ".."))

const RUNNER = joinpath(HERE, "run_revised_data_abm_comparison.jl")

# The companion loader lives in the runner script, and the runner includes the
# comparison module and defines the ABM/BASE aliases. Including the runner here
# means these tests exercise the real entry path rather than a re-implementation
# of it; `main` does not execute because PROGRAM_FILE is this test file.
include(RUNNER)

const FIXTURE_DIRECTORY =
    normpath(joinpath(HERE, "..", "revised_data", "fixtures"))
const BASELINE_CALIBRATION =
    joinpath(REPO_ROOT, "data", "us", "calibration", "US_2024_calibration_object.jld2")
const RECONCILED_CALIBRATION = joinpath(
    REPO_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object_reconciled.jld2",
)
const COMMITTED_V1_HEADLINE = joinpath(
    REPO_ROOT,
    "output",
    "us_forecasting",
    "abm_v2_comparison",
    "v1_headline",
)
const COMMITTED_V2_HEADLINE = joinpath(
    REPO_ROOT,
    "output",
    "us_forecasting",
    "abm_v2_comparison",
    "v2_headline",
)

load_panel() = BASE.load_revised_quarterly_panel(
    joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
    joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
)

"""
    tiny_origins(panel, count)

The first `count` scored origins, so a test cache costs seconds rather than hours.
"""
function tiny_origins(panel, count)
    all_origins = [
        (index, panel.periods[index]) for
            index in BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1)
    ]
    return all_origins[1:count]
end

function generate_tiny_cache(directory, calibration_path; paths = 4, origins = 2)
    mkpath(directory)
    panel = load_panel()
    selected = tiny_origins(panel, origins)
    identity = ABM.build_cache_identity(
        ABM.HEADLINE_VARIANT,
        selected;
        paths = paths,
        calibration_path = calibration_path,
        panel = panel,
    )
    ABM.ACTIVE_CALIBRATION_PATH[] = calibration_path
    simulated = ABM.simulate_abm_ensembles(
        ABM.HEADLINE_VARIANT,
        selected;
        paths = paths,
        cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
        diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
        calibration_path = calibration_path,
        identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
        identity = identity,
        progress = false,
    )
    return (; panel, selected, identity, simulated)
end

@testset "ABM comparison runner regressions" begin

    @testset "cache poisoning is refused, not silently reused" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            @test length(generated.simulated.diagnostics) == 2
            @test isfile(joinpath(directory, ABM.CACHE_IDENTITY_FILENAME))

            # Same variant, same origins, different calibration artifact: the run
            # that reused this cache previously reported "already cached".
            poisoned = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = RECONCILED_CALIBRATION,
                panel = generated.panel,
            )
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = RECONCILED_CALIBRATION,
                    identity_path =
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = poisoned,
                    progress = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            # Whichever calibration field is compared first, the refusal must name
            # the calibration, not fall through to a silent reuse.
            @test thrown.field in
                ("calibration_object_path", "calibration_object_sha256")
            message = sprint(showerror, thrown)
            @test occursin("cache identity mismatch", message)
            println("  refusal (cache poisoning): ", message)

            # A changed path count is refused on its own field.
            wrong_paths = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 8,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            path_error = nothing
            try
                ABM.validate_cache_identity(
                    wrong_paths,
                    ABM.read_cache_identity(
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    ),
                )
            catch error
                path_error = error
            end
            @test path_error isa ABM.CacheIdentityError
            @test path_error.field == "paths_requested"
            println("  refusal (path count): ", sprint(showerror, path_error))
        end
    end

    @testset "an unauthenticated cache cannot be adopted by accident" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            rm(joinpath(directory, ABM.CACHE_IDENTITY_FILENAME))
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = BASELINE_CALIBRATION,
                    identity_path =
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = generated.identity,
                    progress = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test occursin("--adopt-cache-identity", sprint(showerror, thrown))
            println("  refusal (legacy cache): ", sprint(showerror, thrown))
        end
    end

    @testset "a truncated run is smoke-only and cannot be reported" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        @test canonical == 61

        # One origin's worth of coverage must never earn a ranking.
        smoke = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v1_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = 1,
            path_incomplete_origins = 0,
        )
        @test !isempty(smoke)
        @test all(row -> row.status == "INSUFFICIENT_ORIGINS_SMOKE_ONLY", smoke)
        @test all(row -> isnan(row.weighted_macro_average_cellwise_rmse_ratio), smoke)

        mktempdir() do directory
            open(joinpath(directory, "manifest.toml"), "w") do io
                println(io, "sample_is_canonical = false")
                println(io, "abm_observed_origin_count = 1")
                println(io, "abm_canonical_origin_count = $canonical")
            end
            report = joinpath(HERE, "report_v2_comparison.jl")
            output = IOBuffer()
            ok = try
                run(
                    pipeline(
                        `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(REPO_ROOT, "scripts", "us")) $report $directory`;
                        stdout = output,
                        stderr = output,
                    ),
                )
                true
            catch
                false
            end
            text = String(take!(output))
            @test !ok
            @test occursin("refusing to report", text)
            println(
                "  refusal (report on smoke run): ",
                first(split(strip(replace(text, "\n" => " ")), "Stacktrace")),
            )
        end
    end

    @testset "partial path loss makes an origin incomplete" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        degraded = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v1_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = canonical,
            path_incomplete_origins = 1,
        )
        @test all(row -> row.status == "INCOMPLETE_PATH_COVERAGE_NOT_RANKED", degraded)

        # The accounting helper is what the manifest and the status both read.
        whole = ABM.ABMOriginDiagnostic(
            "headline", 40, "2010Q2", "2010Q2", "2010-06-30", 0, 12, 40, 52,
            500, 500, 0, 0.0, 0.0,
        )
        lossy = ABM.ABMOriginDiagnostic(
            "headline", 41, "2010Q3", "2010Q3", "2010-09-30", 0, 12, 41, 53,
            500, 499, 1, 0.0, 0.0,
        )
        complete, incomplete, minimum_used =
            ABM.path_complete_origins([whole, lossy])
        @test complete == 1
        @test incomplete == 1
        @test minimum_used == 499
    end

    @testset "also-score integration: the real loader refuses each forgery" begin
        # These call load_extra_abm_column itself. The previous version of this
        # testset re-implemented a three-field comparison by hand and never touched
        # the loader, which is precisely why the holes below reached CI green.
        mktempdir() do root
            source = joinpath(root, "companion")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION)
            identity_path = joinpath(source, ABM.CACHE_IDENTITY_FILENAME)
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            own_origins = [entry[1] for entry in generated.selected]

            # Baseline: an honest companion is accepted.
            accepted = load_extra_abm_column(source, own, own_origins)
            @test accepted[1].name == "headline"
            @test length(accepted[4]) == length(own_origins)

            function refuse(mutate!, label)
                document = ABM.read_cache_identity(identity_path)
                mutate!(document)
                ABM.write_cache_identity(identity_path, document)
                thrown = nothing
                try
                    load_extra_abm_column(source, own, own_origins)
                catch error
                    thrown = error
                end
                @test thrown isa ABM.CacheIdentityError
                println("  refusal ($label): ", sprint(showerror, thrown))
                # restore
                ABM.write_cache_identity(identity_path, generated.identity)
                return thrown
            end

            forged_code = refuse(
                document -> document["comparison_code_sha256"] = repeat("a", 64),
                "forged comparison_code_sha256",
            )
            @test forged_code.field == "comparison_code_sha256"

            forged_julia = refuse(
                document -> document["julia_version"] = "1.11.0",
                "forged julia_version",
            )
            @test forged_julia.field == "julia_version"

            forged_runtime = refuse(
                document -> document["runtime_source_tree_sha256"] = repeat("b", 64),
                "forged runtime_source_tree_sha256",
            )
            @test forged_runtime.field == "runtime_source_tree_sha256"

            # Missing diagnostics: coverage and path accounting are unknowable.
            diagnostics_path = joinpath(source, "abm_origin_diagnostics.csv")
            saved = read(diagnostics_path)
            rm(diagnostics_path)
            missing_diagnostics = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                missing_diagnostics = error
            end
            @test missing_diagnostics isa ABM.CacheIdentityError
            @test missing_diagnostics.field == "abm_origin_diagnostics.csv"
            println(
                "  refusal (missing diagnostics): ",
                sprint(showerror, missing_diagnostics),
            )
            write(diagnostics_path, saved)

            # Incomplete companion paths: a smaller ensemble wearing the same label.
            rows = ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
            degraded = [
                ABM.ABMOriginDiagnostic(
                        row.variant, row.origin_index, row.origin_period,
                        row.build_period, row.calibration_date, row.burn_in_quarters,
                        row.simulated_quarters, row.t_prime, row.t_max,
                        row.paths_requested, row.paths_requested - 1, 1,
                        row.calibration_seconds, row.simulation_seconds,
                    ) for row in rows
            ]
            rm(diagnostics_path)
            ABM.append_struct_csv(diagnostics_path, degraded, ABM.ABMOriginDiagnostic)
            incomplete = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                incomplete = error
            end
            @test incomplete isa ABM.CacheIdentityError
            @test incomplete.field == "paths_used"
            println("  refusal (incomplete paths): ", sprint(showerror, incomplete))
            rm(diagnostics_path)
            write(diagnostics_path, saved)
        end
    end

    @testset "the forged one-origin companion is refused" begin
        # The reviewer's exact scenario: a self-consistent companion covering ONE
        # origin, offered to a primary run covering more. Previously accepted, and
        # it produced COMPLETE_MATCHED with minimum_common_counts=[1].
        mktempdir() do root
            source = joinpath(root, "one_origin")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION; origins = 1)
            @test length(generated.simulated.diagnostics) == 1

            panel = load_panel()
            primary_selected = tiny_origins(panel, 2)
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                primary_selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = panel,
            )
            thrown = nothing
            try
                load_extra_abm_column(
                    source,
                    own,
                    [entry[1] for entry in primary_selected],
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "origin_indices"
            message = sprint(showerror, thrown)
            @test occursin("must cover exactly the same origins", message)
            println("  refusal (forged one-origin companion): ", message)
        end
    end

    @testset "combined canonicality is the minimum over included columns" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        # A primary with canonical coverage plus a narrower companion must not be
        # ranked: the common cell set is the companion's, not the primary's.
        combined = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v2_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = 1,          # narrowest included column
            path_incomplete_origins = 0,
        )
        @test all(row -> row.status == "INSUFFICIENT_ORIGINS_SMOKE_ONLY", combined)
    end

    @testset "an interrupted cache is detected on resume" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            cache_path = joinpath(directory, "abm_ensemble_summaries.csv")
            lines = readlines(cache_path)
            # Drop three rows from the final origin: the ensemble append survived
            # partially before the process died.
            write(cache_path, join(lines[1:(end - 3)], "\n") * "\n")

            repaired = ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                cache_path = cache_path,
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                identity = generated.identity,
                progress = false,
            )
            # The truncated origin is regenerated, so every origin is whole again.
            counts = Dict{Int, Int}()
            for row in repaired.summaries
                counts[row.origin_index] = get(counts, row.origin_index, 0) + 1
            end
            @test all(==(ABM.ENSEMBLE_ROWS_PER_ORIGIN), values(counts))
            @test length(counts) == 2

            # Under no-repair the same cache is refused by named origin.
            write(cache_path, join(lines[1:(end - 3)], "\n") * "\n")
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = cache_path,
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = BASELINE_CALIBRATION,
                    identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = generated.identity,
                    progress = false,
                    allow_repair = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "ensemble_row_count"
            println("  refusal (interrupted cache): ", sprint(showerror, thrown))
        end
    end

    @testset "forced recompute removes every run-owned artifact" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            failures_path = joinpath(directory, "abm_path_failures.log")
            write(failures_path, "stale failure from an earlier run\n")
            @test isfile(failures_path)

            ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                path_failures_path = failures_path,
                identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                identity = generated.identity,
                force_recompute = true,
                progress = false,
            )
            # The stale log must not survive beside the regenerated cache.
            @test !isfile(failures_path) || isempty(read(failures_path, String))
            println("  forced recompute cleared the stale path-failure log")
        end
    end

    @testset "migration preserves provenance instead of laundering it" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME)

            # Recreate a schema-1 document carrying its own code hashes and an
            # adoption flag, as the committed caches did.
            schema1 = Dict{String, Any}()
            for field in ABM.CACHE_IDENTITY_FIELDS_V1
                schema1[field] = generated.identity[field]
            end
            schema1["schema_version"] = ABM.CACHE_IDENTITY_SCHEMA_V1
            schema1["comparison_code_sha256"] = repeat("c", 64)
            schema1["base_diagnostic_code_sha256"] = repeat("d", 64)
            schema1["adopted_from_legacy_cache"] = true
            open(identity_path, "w") do io
                for field in ABM.CACHE_IDENTITY_FIELDS_V1
                    value = schema1[field]
                    rendered = value isa AbstractString ? "\"$(value)\"" :
                        value isa AbstractVector ? "[$(join(value, ", "))]" :
                        string(value)
                    println(io, "$(field) = $(rendered)")
                end
                println(io, "adopted_from_legacy_cache = true")
            end

            upgraded = ABM.upgrade_cache_identity(
                ABM.read_cache_identity(identity_path),
                generated.identity,
            )
            # The schema-1 code hashes survive verbatim.
            @test upgraded["original_schema1_comparison_code_sha256"] == repeat("c", 64)
            @test upgraded["original_schema1_base_diagnostic_code_sha256"] ==
                repeat("d", 64)
            # Adoption is sticky.
            @test upgraded["adopted_from_legacy_cache"] === true
            @test upgraded["upgraded_from_schema_1"] === true
            @test "origin_indices" in upgraded["migration_verified_fields"]

            ABM.write_cache_identity(identity_path, upgraded)
            written = ABM.read_cache_identity(identity_path)
            @test written["adopted_from_legacy_cache"] === true
            @test written["original_schema1_comparison_code_sha256"] == repeat("c", 64)
            println(
                "  migration preserved original schema-1 hashes and kept adoption sticky",
            )

            # And it still refuses when an experiment-describing field disagrees.
            schema1_bad = copy(schema1)
            schema1_bad["paths_requested"] = 999
            thrown = nothing
            try
                ABM.upgrade_cache_identity(schema1_bad, generated.identity)
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "paths_requested"
            println("  refusal (migration, changed experiment): ", sprint(showerror, thrown))
        end
    end

    @testset "companion parity covers runner and environment manifest" begin
        mktempdir() do root
            source = joinpath(root, "companion")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION)
            identity_path = joinpath(source, ABM.CACHE_IDENTITY_FILENAME)
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            own_origins = [entry[1] for entry in generated.selected]
            for field in ("environment_manifest_sha256", "runner_sha256")
                document = ABM.read_cache_identity(identity_path)
                document[field] = repeat("e", 64)
                ABM.write_cache_identity(identity_path, document)
                thrown = nothing
                try
                    load_extra_abm_column(source, own, own_origins)
                catch error
                    thrown = error
                end
                @test thrown isa ABM.CacheIdentityError
                @test thrown.field == field
                println("  refusal (companion $field): ", sprint(showerror, thrown))
                ABM.write_cache_identity(identity_path, generated.identity)
            end
        end
    end

    @testset "origin-set expansion refreshes the identity" begin
        mktempdir() do directory
            panel = load_panel()
            one = tiny_origins(panel, 1)
            two = tiny_origins(panel, 2)
            generate_tiny_cache(directory, BASELINE_CALIBRATION; origins = 1)
            identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME)
            @test length(ABM.read_cache_identity(identity_path)["origin_indices"]) == 1

            expanded_identity = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                two;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = panel,
            )
            result = ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                two;
                paths = 4,
                cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                identity_path = identity_path,
                identity = expanded_identity,
                progress = false,
            )
            @test length(result.diagnostics) == 2
            # The stored identity must now describe the expanded cache, not the
            # single origin it began with.
            stored = ABM.read_cache_identity(identity_path)
            @test Set(stored["origin_indices"]) ==
                Set(getfield.(result.diagnostics, :origin_index))
            @test length(stored["origin_indices"]) == 2
            println("  identity refreshed after 1 -> 2 origin expansion")
        end
    end

    @testset "interruption repair is durable and idempotent" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            cache_path = joinpath(directory, "abm_ensemble_summaries.csv")
            diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv")
            lines = readlines(cache_path)
            write(cache_path, join(lines[1:(end - 3)], "\n") * "\n")

            function resume()
                return ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = cache_path,
                    diagnostics_path = diagnostics_path,
                    calibration_path = BASELINE_CALIBRATION,
                    identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = generated.identity,
                    progress = false,
                )
            end

            resume()
            # (a) reread from disk: the pruned rows must be gone, not merely
            # filtered in memory.
            on_disk = ABM.read_struct_csv(cache_path, ABM.EnsembleSummary)
            counts = Dict{Int, Int}()
            for row in on_disk
                counts[row.origin_index] = get(counts, row.origin_index, 0) + 1
            end
            @test all(==(ABM.ENSEMBLE_ROWS_PER_ORIGIN), values(counts))
            @test length(on_disk) == 2 * ABM.ENSEMBLE_ROWS_PER_ORIGIN
            disk_diagnostics =
                ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
            @test length(disk_diagnostics) == 2
            @test length(unique(getfield.(disk_diagnostics, :origin_index))) == 2
            rows_after_first = length(on_disk)

            # (b) a second resume must be a no-op: no re-detection, no growth.
            resume()
            second = ABM.read_struct_csv(cache_path, ABM.EnsembleSummary)
            @test length(second) == rows_after_first
            @test length(
                ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic),
            ) == 2
            println(
                "  repair durable on disk ($rows_after_first rows) and idempotent across resumes",
            )
        end
    end

    @testset "effective generation provenance distinguishes migrated caches" begin
        # Two migrated identities whose re-baselined hashes agree but whose real
        # generation hashes differ must not be judged equivalent.
        a = Dict{String, Any}(
            "upgraded_from_schema_1" => true,
            "comparison_code_sha256" => repeat("1", 64),
            "base_diagnostic_code_sha256" => repeat("2", 64),
            "original_schema1_comparison_code_sha256" => repeat("a", 64),
            "original_schema1_base_diagnostic_code_sha256" => repeat("b", 64),
        )
        b = copy(a)
        b["original_schema1_comparison_code_sha256"] = repeat("c", 64)
        pa = ABM.effective_generation_provenance(a)
        pb = ABM.effective_generation_provenance(b)
        @test pa.migrated && pb.migrated
        @test pa.comparison == repeat("a", 64)      # the generating hash, not the re-baselined one
        @test pa.comparison != pb.comparison
        # A non-migrated identity reports its own current hashes.
        native = Dict{String, Any}(
            "comparison_code_sha256" => repeat("9", 64),
            "base_diagnostic_code_sha256" => repeat("8", 64),
        )
        @test ABM.effective_generation_provenance(native).comparison == repeat("9", 64)
        @test ABM.effective_generation_provenance(native).migrated == false
        println("  effective provenance separates caches the re-baselined hashes conflate")
    end

    @testset "the committed v1/v2 pairing shares generation provenance" begin
        if isdir(COMMITTED_V1_HEADLINE) && isdir(COMMITTED_V2_HEADLINE)
            v1 = ABM.read_cache_identity(
                joinpath(COMMITTED_V1_HEADLINE, ABM.CACHE_IDENTITY_FILENAME),
            )
            v2 = ABM.read_cache_identity(
                joinpath(COMMITTED_V2_HEADLINE, ABM.CACHE_IDENTITY_FILENAME),
            )
            pv1 = ABM.effective_generation_provenance(v1)
            pv2 = ABM.effective_generation_provenance(v2)
            @test pv1.comparison !== nothing
            @test pv1.comparison == pv2.comparison
            @test pv1.base_diagnostic == pv2.base_diagnostic
            @test pv1.migrated && pv2.migrated
            println(
                "  committed pairing shares generation provenance ",
                first(pv1.comparison, 12),
            )
        else
            @test true
        end
    end

    @testset "an orphaned ensemble block is detected and pruned" begin
        # The inverse interruption: both origins complete, then the SECOND
        # diagnostic row is lost. Previously the orphaned 60 rows vanished from
        # detection and regeneration appended beside them -> 180 rows on disk.
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            cache_path = joinpath(directory, "abm_ensemble_summaries.csv")
            diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv")
            rows = ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
            @test length(rows) == 2
            kept = [rows[1]]
            rm(diagnostics_path)
            ABM.append_struct_csv(diagnostics_path, kept, ABM.ABMOriginDiagnostic)

            result = ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                cache_path = cache_path,
                diagnostics_path = diagnostics_path,
                calibration_path = BASELINE_CALIBRATION,
                identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                identity = generated.identity,
                progress = false,
            )
            on_disk = ABM.read_struct_csv(cache_path, ABM.EnsembleSummary)
            @test length(on_disk) == 2 * ABM.ENSEMBLE_ROWS_PER_ORIGIN
            @test length(result.diagnostics) == 2
            @test length(
                ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic),
            ) == 2
            println(
                "  orphaned block pruned and regenerated: $(length(on_disk)) rows on disk (not 180)",
            )
        end
    end

    @testset "the forecast grid must be the exact expected set" begin
        base = ABM.EnsembleSummary(
            "headline", 40, "2010Q2", "2010Q3", "real_gdp", 1, 4,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        )
        exact = [
            ABM.EnsembleSummary(
                    base.variant, base.origin_index, base.origin_period,
                    base.target_period, target, horizon, base.paths_used,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                ) for target in ABM.ABM_TARGET_IDS, horizon in 1:ABM.SIMULATION_HORIZON
        ]
        @test ABM.origin_grid_complete(vec(exact))

        # Substitute a horizon-13 cell: still 60 unique pairs, wrong grid.
        smuggled = copy(vec(exact))
        smuggled[1] = ABM.EnsembleSummary(
            base.variant, base.origin_index, base.origin_period,
            base.target_period, "real_gdp", ABM.SIMULATION_HORIZON + 1,
            base.paths_used, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        )
        @test length(smuggled) == ABM.ENSEMBLE_ROWS_PER_ORIGIN
        @test !ABM.origin_grid_complete(smuggled)
        println("  a horizon-13 cell no longer passes as a complete grid")
    end

    @testset "a stale identity self-heals on the next run" begin
        # Simulate a run that appended its origins but died before refreshing the
        # identity: the document still claims one origin while the cache holds two.
        mktempdir() do directory
            panel = load_panel()
            two = tiny_origins(panel, 2)
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME)
            stale = copy(generated.identity)
            stale["origin_indices"] = [two[1][1]]
            ABM.write_cache_identity(identity_path, stale)
            @test length(ABM.read_cache_identity(identity_path)["origin_indices"]) == 1

            before = read(joinpath(directory, "abm_ensemble_summaries.csv"))
            result = ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                two;
                paths = 4,
                cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                identity_path = identity_path,
                identity = ABM.build_cache_identity(
                    ABM.HEADLINE_VARIANT, two;
                    paths = 4,
                    calibration_path = BASELINE_CALIBRATION,
                    panel = panel,
                ),
                progress = false,
            )
            healed = ABM.read_cache_identity(identity_path)
            @test Set(healed["origin_indices"]) ==
                Set(getfield.(result.diagnostics, :origin_index))
            @test length(healed["origin_indices"]) == 2
            # Nothing was regenerated: the cache bytes are untouched.
            @test read(joinpath(directory, "abm_ensemble_summaries.csv")) == before
            println("  stale identity healed with no regeneration")
        end
    end

    @testset "loader rejects both live grid forgeries through the real path" begin
        # Both of these previously passed the loader: it row-counted and Set-deduped
        # instead of using the module helpers. These go through
        # load_extra_abm_column, not the helper, so a loader that drifts from the
        # module fails here.
        mktempdir() do root
            source = joinpath(root, "companion")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION)
            cache_path = joinpath(source, "abm_ensemble_summaries.csv")
            diagnostics_path = joinpath(source, "abm_origin_diagnostics.csv")
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            own_origins = [entry[1] for entry in generated.selected]
            pristine_cache = read(cache_path)
            pristine_diagnostics = read(diagnostics_path)

            # Repro 1: substitute a unique horizon-13 cell. Row count stays 60 and
            # every pair is still unique, so a count-and-dedup check passes.
            rows = ABM.read_struct_csv(cache_path, ABM.EnsembleSummary)
            victim = findfirst(
                row -> row.origin_index == own_origins[1] &&
                    row.target_id == "real_gdp" && row.horizon == 1,
                rows,
            )
            @test victim !== nothing
            original = rows[victim]
            rows[victim] = ABM.EnsembleSummary(
                original.variant, original.origin_index, original.origin_period,
                original.target_period, original.target_id,
                ABM.SIMULATION_HORIZON + 1, original.paths_used,
                original.ensemble_mean, original.ensemble_median,
                original.ensemble_sd, original.monte_carlo_standard_error,
                original.percentile_05, original.percentile_10,
                original.percentile_25, original.percentile_75,
                original.percentile_90, original.percentile_95,
            )
            ABM.rewrite_struct_csv(cache_path, rows, ABM.EnsembleSummary)
            thrown = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "ensemble_row_count"
            println("  refusal (loader, horizon-13 substitution): ", sprint(showerror, thrown))
            write(cache_path, pristine_cache)

            # Repro 2: duplicate a companion diagnostic row. Set membership of
            # origins is unchanged, so a Set-based check passes.
            diagnostics =
                ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
            ABM.rewrite_struct_csv(
                diagnostics_path,
                vcat(diagnostics, [diagnostics[1]]),
                ABM.ABMOriginDiagnostic,
            )
            duplicated = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                duplicated = error
            end
            @test duplicated isa ABM.CacheIdentityError
            @test duplicated.field == "abm_origin_diagnostics.csv"
            println("  refusal (loader, duplicated diagnostic): ", sprint(showerror, duplicated))
            write(diagnostics_path, pristine_diagnostics)

            # And an untampered companion still loads.
            @test load_extra_abm_column(source, own, own_origins)[1].name == "headline"
        end
    end

    @testset "the numerical kernel digest is enforced on every run" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME)
            stored = ABM.read_cache_identity(identity_path)
            @test haskey(stored, "numerical_kernel_sha256")
            @test stored["numerical_kernel_sha256"] ==
                bytes2hex(SHA.sha256(read(ABM.NUMERICAL_KERNEL_PATH)))

            # Even a MIGRATED identity must not excuse a changed kernel: the kernel
            # is not a harness field.
            @test !("numerical_kernel_sha256" in ABM.HARNESS_IDENTITY_FIELDS)
            migrated = copy(stored)
            migrated["upgraded_from_schema_1"] = true
            migrated["original_schema1_comparison_code_sha256"] = repeat("a", 64)
            migrated["original_schema1_base_diagnostic_code_sha256"] = repeat("b", 64)
            migrated["numerical_kernel_sha256"] = repeat("f", 64)
            thrown = nothing
            try
                ABM.validate_cache_identity(generated.identity, migrated)
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "numerical_kernel_sha256"
            println("  refusal (migrated identity, changed kernel): ", sprint(showerror, thrown))
        end
    end

    @testset "generation primitives exist only in sealed files" begin
        # Structural boundary. The review's principle: calling a sealed function does
        # not seal its arguments or the control flow around it. So every primitive
        # that can produce or perturb a forecast number must appear ONLY in files
        # whose digest is enforced on every run.
        kernel = read(ABM.NUMERICAL_KERNEL_PATH, String)
        harness = read(
            joinpath(@__DIR__, "USRevisedDataABMComparison.jl"),
            String,
        )
        runner = read(RUNNER, String)

        primitives = (
            "Bit.Model(",
            "Bit.step!",
            "Bit.collect_data!",
            "Random.seed!",
            "Bit.get_params_and_initial_conditions",
            "path_seed(",
            "simulate_path(",
            "summarize_ensemble(",
        )
        for primitive in primitives
            @test occursin(primitive, kernel)
            @test !occursin(primitive, harness)
            @test !occursin(primitive, runner)
        end
        println(
            "  all $(length(primitives)) generation primitives confined to the sealed kernel",
        )

        # The whole per-origin operation is one sealed entry point, so the harness
        # cannot re-derive origin dates, quarters or seeds around it.
        @test occursin("function generate_origin_ensemble(", kernel)
        @test occursin("generate_origin_ensemble(", harness)
        # The generation DECISIONS must be kernel-side. The harness may still record
        # simulated_quarters as identity/manifest metadata -- recording a value is
        # not choosing it -- so the assertion targets the assignments that drive the
        # simulation, not every mention of the quantity.
        for decision in (
                "shift_period(origin_period",
                "quarters = SIMULATION_HORIZON + variant.burn_in_quarters",
                "seed_stream_name(variant.name)",
                "for path in 1:paths",
            )
            @test occursin(decision, kernel)
            @test !occursin(decision, harness)
        end
        println("  origin dates, quarters, the path loop and seed arguments are kernel-side")
    end

    @testset "a comparison-only change is non-numerical by construction" begin
        # The reviewer's repro was: perturb the seed call site (then in the harness)
        # so every number moves while only comparison_code_sha256 changes -- a field
        # a migrated identity skips. That repro class is now impossible: the seed call
        # site is in the kernel, so the same edit moves numerical_kernel_sha256, which
        # is enforced for migrated and native identities alike.
        @test occursin("path_seed(", read(ABM.NUMERICAL_KERNEL_PATH, String))

        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            stored = ABM.read_cache_identity(
                joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
            )
            # A migrated identity skips the harness hash ...
            migrated = copy(stored)
            migrated["upgraded_from_schema_1"] = true
            migrated["original_schema1_comparison_code_sha256"] = repeat("a", 64)
            migrated["original_schema1_base_diagnostic_code_sha256"] = repeat("b", 64)
            migrated["comparison_code_sha256"] = repeat("9", 64)
            @test ABM.validate_cache_identity(generated.identity, migrated) === nothing

            # ... but never the kernel, which is where every number now comes from.
            migrated["numerical_kernel_sha256"] = repeat("f", 64)
            thrown = nothing
            try
                ABM.validate_cache_identity(generated.identity, migrated)
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "numerical_kernel_sha256"
            println(
                "  comparison-only change accepted (non-numerical by construction); ",
                "kernel change refused on `", thrown.field, "`",
            )
        end
    end

    @testset "committed v2 headline cache validates and re-scores byte-identically" begin
        if !isdir(COMMITTED_V2_HEADLINE) || !isdir(COMMITTED_V1_HEADLINE)
            @info "committed v2 headline run absent; skipping"
            @test true
        else
            identity_path =
                joinpath(COMMITTED_V2_HEADLINE, ABM.CACHE_IDENTITY_FILENAME)
            stored = ABM.read_cache_identity(identity_path)
            @test stored["variant"] == "headline_v2"
            @test stored["paths_requested"] == 500
            @test stored["seed_contract_id"] == ABM.SEED_CONTRACT_ID

            panel = load_panel()
            @test stored["panel_sha256"] == panel.panel_sha256

            # The cache must still describe the artifact it claims.
            calibration =
                joinpath(REPO_ROOT, stored["calibration_object_path"])
            @test isfile(calibration)
            @test bytes2hex(SHA.sha256(read(calibration))) ==
                stored["calibration_object_sha256"]

            # And the committed score table must be exactly what this code produces
            # from that cache.
            # The committed table is a joint run: both ABM columns scored on
            # identical common cells, so the re-score must supply the v1 column too.
            committed = read(joinpath(COMMITTED_V2_HEADLINE, "score_summaries.csv"))
            mktempdir() do root
                directory = joinpath(root, "v2")
                companion = joinpath(root, "v1")
                mkpath(directory)
                mkpath(companion)
                for name in (
                        "abm_ensemble_summaries.csv",
                        "abm_origin_diagnostics.csv",
                        ABM.CACHE_IDENTITY_FILENAME,
                    )
                    cp(
                        joinpath(COMMITTED_V2_HEADLINE, name),
                        joinpath(directory, name),
                    )
                    cp(joinpath(COMMITTED_V1_HEADLINE, name), joinpath(companion, name))
                end
                output = IOBuffer()
                run(
                    pipeline(
                        `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(REPO_ROOT, "scripts", "us")) $RUNNER $directory 500 headline_v2 --also-score=$companion`;
                        stdout = output,
                        stderr = output,
                    ),
                )
                rescored = read(joinpath(directory, "score_summaries.csv"))
                @test rescored == committed
                println(
                    "  committed cache re-scored: score_summaries.csv byte-identical ",
                    "($(length(committed)) bytes)",
                )
            end
        end
    end

end
