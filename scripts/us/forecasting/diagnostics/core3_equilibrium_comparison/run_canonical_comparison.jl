using SHA

const COMPONENT_DIR = @__DIR__
const MODULE_PATH = joinpath(COMPONENT_DIR, "USCore3EquilibriumComparison.jl")
const EXPECTED_COMPARISON_MODULE_SHA256 =
    "35fa2c699adee61bcb16d7eaf5b40a941122f851a5fcceb8e9e9e6f729025659"

struct ModulePreincludeError <: Exception
    message::String
end

Base.showerror(io::IO, error::ModulePreincludeError) = print(io, error.message)
module_preinclude_fail(message) = throw(ModulePreincludeError(String(message)))

function reject_symbolic_module_path(path)
    current = abspath(path)
    while true
        islink(current) &&
            module_preinclude_fail("comparison module path contains a symbolic link: $current")
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return nothing
end

function module_file_metadata(file_status)
    return (
        file_status.device,
        file_status.inode,
        file_status.mode,
        file_status.nlink,
        file_status.uid,
        file_status.gid,
        file_status.size,
        file_status.mtime,
        file_status.ctime,
    )
end

function preinclude_comparison_module_then(
        callback::Function;
        module_path = MODULE_PATH,
        expected_sha256 = EXPECTED_COMPARISON_MODULE_SHA256,
    )
    occursin(r"^[0-9a-f]{64}$", expected_sha256) ||
        module_preinclude_fail("expected comparison module SHA-256 is malformed")
    absolute = abspath(module_path)
    reject_symbolic_module_path(absolute)
    isfile(absolute) || module_preinclude_fail("comparison module is not a regular file")
    before = stat(absolute)
    before.nlink == 1 ||
        module_preinclude_fail("comparison module must have exactly one hard link")
    bytes = read(absolute)
    after = stat(absolute)
    module_file_metadata(before) == module_file_metadata(after) ||
        module_preinclude_fail("comparison module metadata changed while read")
    length(bytes) == before.size ||
        module_preinclude_fail("comparison module byte count changed while read")
    digest = bytes2hex(SHA.sha256(bytes))
    digest == expected_sha256 || module_preinclude_fail(
        "comparison module SHA-256 mismatch: expected $expected_sha256, got $digest",
    )
    return callback(digest)
end

const PREINCLUDE_COMPARISON_MODULE_SHA256 = preinclude_comparison_module_then() do digest
    Base.include(@__MODULE__, MODULE_PATH)
    digest
end
using .USCore3EquilibriumComparison

const M = USCore3EquilibriumComparison

result = run_canonical_comparison()

println("protocol_sha256\t", result.protocol_sha256)
println("archive_sha256\t", result.archive_sha256)
println("truth_attachment_sha256\t", result.truth_attachment_sha256)
println("result_sha256\t", result.content_sha256)
println("status\t", result.status)
println("model_selection_timing\t", result.model_selection_timing)
println("point_error_sign\t", result.point_error_sign)
println("mathematical_scores_computed\t", result.mathematical_scores_computed)
println("repository_scoring_eligible\t", result.repository_scoring_eligible)
println("all_gates_false\t", all(iszero, values(result.gates)))
println()
println(
    join(
        (
            "POINT_DENSITY_FULL",
            "model",
            "target",
            "horizon",
            "n",
            "mean_error",
            "rmse",
            "mae",
            "mase",
            "empirical_m2_crps",
            "wis_50_80_95",
            "coverage_50",
            "width_50",
            "coverage_80",
            "width_80",
            "coverage_95",
            "width_95",
        ),
        '\t',
    ),
)
for cell in result.point_density_scores
    cell.regime == "FULL" || continue
    println(
        join(
            (
                "POINT_DENSITY_FULL",
                cell.model_id,
                cell.target_name,
                cell.horizon,
                cell.n,
                cell.mean_error,
                cell.rmse,
                cell.mae,
                cell.mase,
                cell.empirical_m2_crps,
                cell.wis_50_80_95,
                cell.coverage_50,
                cell.width_50,
                cell.coverage_80,
                cell.width_80,
                cell.coverage_95,
                cell.width_95,
            ),
            '\t',
        ),
    )
end
println()
println("JOINT_FULL\tmodel\thorizon\tn\tenergy_score\tvariogram_score")
for cell in result.joint_scores
    cell.regime == "FULL" || continue
    println(
        join(
            (
                "JOINT_FULL",
                cell.model_id,
                cell.horizon,
                cell.n,
                cell.energy_score,
                cell.variogram_score,
            ),
            '\t',
        ),
    )
end
println()
println(
    "PAIRED_FULL\tcomparator\ttarget\thorizon\tloss\tn\t" *
        "mean_challenger_minus_comparator\thln_status\thln_reason\t" *
        "hln_statistic\thln_p_value\tconfidence_lower\tconfidence_upper",
)
for cell in result.paired_loss_cells
    cell.regime == "FULL" || continue
    println(
        join(
            (
                "PAIRED_FULL",
                cell.comparator_model_id,
                cell.target_name,
                cell.horizon,
                cell.loss,
                cell.n,
                cell.mean_challenger_minus_comparator,
                cell.hln_dm_status,
                something(cell.hln_dm_reason, ""),
                something(cell.hln_dm_statistic, ""),
                something(cell.hln_dm_p_value, ""),
                something(cell.confidence_lower, ""),
                something(cell.confidence_upper, ""),
            ),
            '\t',
        ),
    )
end
println()
for regime in M.REGIME_IDS
    println(
        "REGIME_COUNTS\t",
        regime,
        '\t',
        join(result.exact_regime_counts[regime], ','),
    )
end
for blocker in result.blockers
    println("BLOCKER\t", blocker)
end
