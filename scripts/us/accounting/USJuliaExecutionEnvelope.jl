module USJuliaExecutionEnvelope

using Base.BinaryPlatforms
using LinearAlgebra

export BYTE_REPRODUCIBILITY_SCOPE,
    CANONICAL_EXECUTION_ENVELOPE,
    EXECUTION_ENVELOPE_KEYS,
    ExecutionEnvelopeAssessment,
    ExecutionEnvelopeMismatch,
    SemanticExecutionPreconditionMismatch,
    assess_execution_envelope,
    current_execution_envelope,
    validate_build_environment,
    validate_execution_envelope_table,
    validate_portable_semantic_environment,
    validate_runtime_execution_envelope_table

const BYTE_REPRODUCIBILITY_SCOPE =
    "same_frozen_local_execution_envelope_only"
const CANONICAL_EXECUTION_ENVELOPE = Dict{String, Any}(
    "julia_version" => "1.10.3",
    "bounds_check_mode" => "auto",
    "bounds_check_code" => 0,
    "opt_level" => 2,
    "min_opt_level" => 0,
    "fast_math_code" => 0,
    "can_inline_code" => 1,
    "polly_code" => 1,
    "cpu_target" => "native",
    "startup_file_mode" => "no",
    "startup_file_code" => 2,
    "platform_triplet" =>
        "aarch64-apple-darwin-libgfortran5-cxx11-julia_version+1.10.3",
    "kernel" => "Darwin",
    "architecture" => "aarch64",
    "cpu_name" => "apple-m1",
    "word_size" => 64,
    "julia_thread_count" => 1,
    "blas_thread_count" => 1,
    "blas_vendor" => "lbt",
)
const EXECUTION_ENVELOPE_KEYS =
    sort!(collect(keys(CANONICAL_EXECUTION_ENVELOPE)))
const BOUNDS_CHECK_MODES =
    Dict(0 => "auto", 1 => "yes", 2 => "no")
const STARTUP_FILE_MODES =
    Dict(0 => "auto", 1 => "yes", 2 => "no")

struct ExecutionEnvelopeMismatch <: Exception
    expected::Dict{String, Any}
    actual::Dict{String, Any}
    mismatches::Vector{String}
end

struct ExecutionEnvelopeAssessment
    expected::Dict{String, Any}
    actual::Dict{String, Any}
    mismatches::Vector{String}
    canonical_match::Bool
end

struct SemanticExecutionPreconditionMismatch <: Exception
    actual::Dict{String, Any}
    mismatches::Vector{String}
end

function Base.showerror(
        io::IO,
        error::ExecutionEnvelopeMismatch,
    )
    return print(
        io,
        "candidate build execution envelope mismatch: ",
        join(error.mismatches, "; "),
    )
end

function Base.showerror(
        io::IO,
        error::SemanticExecutionPreconditionMismatch,
    )
    return print(
        io,
        "portable semantic execution precondition mismatch: ",
        join(error.mismatches, "; "),
    )
end

function option_string(pointer)
    pointer == C_NULL && return ""
    return unsafe_string(pointer)
end

function current_execution_envelope()
    options = Base.JLOptions()
    bounds_check_code = Int(options.check_bounds)
    startup_file_code = Int(options.startupfile)
    return Dict{String, Any}(
        "julia_version" => string(VERSION),
        "bounds_check_mode" =>
            get(BOUNDS_CHECK_MODES, bounds_check_code, "unknown"),
        "bounds_check_code" => bounds_check_code,
        "opt_level" => Int(options.opt_level),
        "min_opt_level" => Int(options.opt_level_min),
        "fast_math_code" => Int(options.fast_math),
        "can_inline_code" => Int(options.can_inline),
        "polly_code" => Int(options.polly),
        "cpu_target" => option_string(options.cpu_target),
        "startup_file_mode" =>
            get(STARTUP_FILE_MODES, startup_file_code, "unknown"),
        "startup_file_code" => startup_file_code,
        "platform_triplet" => triplet(HostPlatform()),
        "kernel" => string(Sys.KERNEL),
        "architecture" => string(Sys.ARCH),
        "cpu_name" => String(Sys.CPU_NAME),
        "word_size" => Sys.WORD_SIZE,
        "julia_thread_count" => Threads.nthreads(),
        "blas_thread_count" => LinearAlgebra.BLAS.get_num_threads(),
        "blas_vendor" => string(LinearAlgebra.BLAS.vendor()),
    )
end

function validate_execution_envelope_table(value, location)
    value isa AbstractDict ||
        throw(ArgumentError("$location must be a table"))
    actual_keys = sort!(String.(collect(keys(value))))
    actual_keys == EXECUTION_ENVELOPE_KEYS ||
        throw(
        ArgumentError(
            "$location keys differ; expected " *
                join(EXECUTION_ENVELOPE_KEYS, ", "),
        ),
    )
    declared = Dict{String, Any}(
        key => value[key] for key in EXECUTION_ENVELOPE_KEYS
    )
    declared == CANONICAL_EXECUTION_ENVELOPE ||
        throw(
        ArgumentError(
            "$location differs from the frozen local execution envelope",
        ),
    )
    return declared
end

function validate_runtime_execution_envelope_table(value, location)
    value isa AbstractDict ||
        throw(ArgumentError("$location must be a table"))
    actual_keys = sort!(String.(collect(keys(value))))
    actual_keys == EXECUTION_ENVELOPE_KEYS ||
        throw(
        ArgumentError(
            "$location keys differ; expected " *
                join(EXECUTION_ENVELOPE_KEYS, ", "),
        ),
    )
    result = Dict{String, Any}()
    for key in EXECUTION_ENVELOPE_KEYS
        entry = value[key]
        canonical = CANONICAL_EXECUTION_ENVELOPE[key]
        if canonical isa Integer
            entry isa Integer && !(entry isa Bool) ||
                throw(ArgumentError("$location.$key must be an integer"))
            result[key] = Int(entry)
        else
            entry isa AbstractString ||
                throw(ArgumentError("$location.$key must be a string"))
            isempty(strip(String(entry))) &&
                throw(ArgumentError("$location.$key must be nonempty"))
            result[key] = String(entry)
        end
    end
    result["word_size"] in (32, 64) ||
        throw(ArgumentError("$location.word_size must be 32 or 64"))
    result["julia_thread_count"] > 0 ||
        throw(ArgumentError("$location.julia_thread_count must be positive"))
    result["blas_thread_count"] > 0 ||
        throw(ArgumentError("$location.blas_thread_count must be positive"))
    return result
end

function assess_execution_envelope(config)
    expected = validate_execution_envelope_table(
        get(config, "execution_envelope", nothing),
        "candidate execution_envelope",
    )
    actual = validate_runtime_execution_envelope_table(
        current_execution_envelope(),
        "actual execution_envelope",
    )
    mismatches = String[
        "$key expected $(repr(expected[key])) got $(repr(actual[key]))"
            for key in EXECUTION_ENVELOPE_KEYS
            if !isequal(expected[key], actual[key])
    ]
    return ExecutionEnvelopeAssessment(
        expected,
        actual,
        mismatches,
        isempty(mismatches),
    )
end

function validate_build_environment(config)
    assessment = assess_execution_envelope(config)
    isempty(assessment.mismatches) ||
        throw(
        ExecutionEnvelopeMismatch(
            assessment.expected,
            assessment.actual,
            assessment.mismatches,
        ),
    )
    return assessment.actual
end

function validate_portable_semantic_environment(config)
    assessment = assess_execution_envelope(config)
    precondition_mismatches = String[]
    assessment.actual["julia_thread_count"] == 1 ||
        push!(
        precondition_mismatches,
        "julia_thread_count expected 1 got " *
            repr(assessment.actual["julia_thread_count"]),
    )
    assessment.actual["blas_thread_count"] == 1 ||
        push!(
        precondition_mismatches,
        "blas_thread_count expected 1 got " *
            repr(assessment.actual["blas_thread_count"]),
    )
    isempty(precondition_mismatches) ||
        throw(
        SemanticExecutionPreconditionMismatch(
            assessment.actual,
            precondition_mismatches,
        ),
    )
    return assessment
end

function validate_build_environment(config, actual::AbstractDict)
    expected = validate_execution_envelope_table(
        get(config, "execution_envelope", nothing),
        "candidate execution_envelope",
    )
    recorded = validate_runtime_execution_envelope_table(
        actual,
        "actual execution_envelope",
    )
    mismatches = String[
        "$key expected $(repr(expected[key])) got $(repr(recorded[key]))"
            for key in EXECUTION_ENVELOPE_KEYS
            if !isequal(expected[key], recorded[key])
    ]
    isempty(mismatches) ||
        throw(ExecutionEnvelopeMismatch(expected, recorded, mismatches))
    return recorded
end

end # module
