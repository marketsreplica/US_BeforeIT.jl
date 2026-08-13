module USForecastRegistry

using Dates
using JSON
using SHA
using TOML

export RegistryValidationError,
    append_forecast!,
    append_score!,
    append_truth!,
    create_registry!,
    derive_seed,
    derive_seed_record,
    reveal_retrospective_truth!,
    seal_forecasts!,
    truth_quarantine_commitment,
    verify_registry

const SCHEMA_VERSION = "beforeit-us-forecast-registry.v3"
const FORECAST_SCHEMA_VERSION = "beforeit-us-forecast-record.v3"
const TRUTH_SCHEMA_VERSION = "beforeit-us-truth-record.v2"
const SCORE_SCHEMA_VERSION = "beforeit-us-score-record.v2"
const QUARANTINE_SCHEMA_VERSION =
    "beforeit-us-retrospective-truth-quarantine.v1"
const REVEAL_SCHEMA_VERSION =
    "beforeit-us-retrospective-truth-reveal.v1"
const ZERO_HASH = repeat("0", 64)
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const PROSPECTIVE_MODE = "prospective"
const RETROSPECTIVE_MODE = "retrospective_replay"
const PROSPECTIVE_TRUTH_POLICY = "future_release_only"
const RETROSPECTIVE_TRUTH_POLICY =
    "salted_exact_truth_manifest_post_seal_reveal"
const QUARANTINE_COMMITMENT_DOMAIN =
    "beforeit-us-retrospective-truth-quarantine-commitment.v1"

const HEADER_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "protocol_sha256",
        "environment_sha256",
        "run_mode",
        "knowledge_cutoff_utc",
        "truth_access_policy",
        "truth_quarantine_commitment_sha256",
        "execution_created_at_utc",
        "registry_header_sha256",
    ]
)
const FORECAST_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "forecast_id",
        "execution_registered_at_utc",
        "origin_id",
        "origin_timestamp_utc",
        "origin_manifest_sha256",
        "origin_data_sample_sha256",
        "origin_data_receipt_sha256",
        "protocol_sha256",
        "model_id",
        "model_manifest_sha256",
        "model_card_sha256",
        "product_id",
        "information_track",
        "target_id",
        "target_operator_version",
        "transformation_version",
        "horizon",
        "target_period_start",
        "target_period_end",
        "truth_key",
        "status",
        "point_forecast",
        "distribution_artifact_sha256",
        "n_draws",
        "seed",
        "seed_key_sha256",
        "failure_code",
    ]
)
const TRUTH_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "truth_id",
        "truth_key",
        "execution_appended_at_utc",
        "release_timestamp_utc",
        "target_id",
        "target_operator_version",
        "transformation_version",
        "target_period_start",
        "target_period_end",
        "truth_vintage",
        "value",
        "source_artifact_sha256",
    ]
)
const SCORE_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "score_id",
        "forecast_id",
        "truth_id",
        "forecast_record_sha256",
        "truth_record_sha256",
        "evaluation_version",
        "metric",
        "value",
        "execution_evaluated_at_utc",
    ]
)
const ENVELOPE_KEYS =
    Set(["kind", "payload", "previous_sha256", "record_sha256"])
const SEAL_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "execution_sealed_at_utc",
        "forecast_count",
        "forecast_chain_sha256",
        "forecasts_file_sha256",
        "registry_header_sha256",
        "seal_sha256",
    ]
)
const QUARANTINE_KEYS = Set(["artifact", "truth_records"])
const QUARANTINE_ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "protocol_sha256",
        "knowledge_cutoff_utc",
        "truth_record_count",
    ]
)
const QUARANTINE_TRUTH_KEYS = Set(
    [
        "truth_id",
        "truth_key",
        "release_timestamp_utc",
        "target_id",
        "target_operator_version",
        "transformation_version",
        "target_period_start",
        "target_period_end",
        "truth_vintage",
        "value",
        "source_artifact_sha256",
    ]
)
const REVEAL_KEYS = Set(
    [
        "schema_version",
        "experiment_id",
        "execution_revealed_at_utc",
        "quarantine_manifest_sha256",
        "commitment_nonce",
        "truth_quarantine_commitment_sha256",
        "truth_record_count",
        "forecast_seal_sha256",
        "forecast_chain_sha256",
        "forecasts_file_sha256",
        "registry_header_sha256",
        "reveal_sha256",
    ]
)
const FORBIDDEN_FORECAST_KEY_FRAGMENTS =
    ("truth_value", "actual", "realization", "score", "loss", "error")

struct RegistryValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::RegistryValidationError) =
    print(io, error.message)

fail(message) = throw(RegistryValidationError(String(message)))

function normalize(value, location = "value")
    if value === nothing || value isa Bool || value isa AbstractString
        return value
    elseif value isa Integer
        return Int(value)
    elseif value isa AbstractFloat
        isfinite(value) || fail("$location must be finite")
        return Float64(value)
    elseif value isa AbstractVector
        return [
            normalize(item, "$location[$index]")
                for (index, item) in enumerate(value)
        ]
    elseif value isa AbstractDict
        result = Dict{String, Any}()
        for (key, item) in pairs(value)
            key isa AbstractString ||
                fail("$location has a non-string key")
            text = String(key)
            haskey(result, text) &&
                fail("$location has duplicate key $text")
            result[text] = normalize(item, "$location.$text")
        end
        return result
    end
    return fail("$location has unsupported type $(typeof(value))")
end

function canonical(value)
    if value === nothing
        return "nothing:"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "integer:" * string(value)
    elseif value isa AbstractFloat
        isfinite(value) || fail("cannot canonicalize a nonfinite number")
        return "float64:" * bitstring(Float64(value))
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa AbstractVector
        encoded = canonical.(value)
        return "array:$(length(encoded)):" *
            join(
            ("$(ncodeunits(item)):$item" for item in encoded),
            "",
        )
    elseif value isa AbstractDict
        keys_sorted = sort!(collect(String.(keys(value))))
        fields = String[]
        for key in keys_sorted
            encoded = canonical(value[key])
            push!(
                fields,
                "$(ncodeunits(key)):$key$(ncodeunits(encoded)):$encoded",
            )
        end
        return "dict:$(length(fields)):" * join(fields, "")
    end
    return fail("cannot canonicalize type $(typeof(value))")
end

sha256_hex(value::AbstractString) = bytes2hex(SHA.sha256(value))
file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function _quarantine_commitment(manifest_sha256, commitment_nonce)
    manifest_hash = expect_hash(
        manifest_sha256,
        "quarantine_manifest_sha256",
    )
    nonce = expect_hash(commitment_nonce, "commitment_nonce")
    nonce != ZERO_HASH || fail("commitment_nonce must not be the zero hash")
    return sha256_hex(
        "$QUARANTINE_COMMITMENT_DOMAIN\n" *
            "manifest_sha256:$manifest_hash\n" *
            "commitment_nonce:$nonce",
    )
end

"""
    truth_quarantine_commitment(manifest_path, commitment_nonce)

Return the salted commitment for the exact bytes of a retrospective truth
manifest. The 256-bit lowercase-hex nonce and manifest must remain unavailable
to the forecasting process until the post-seal reveal stage.
"""
function truth_quarantine_commitment(manifest_path, commitment_nonce)
    isfile(manifest_path) ||
        fail("truth-quarantine manifest is missing: $manifest_path")
    return _quarantine_commitment(
        file_sha256(manifest_path),
        commitment_nonce,
    )
end

function expect_exact_keys(value, expected, location)
    value isa AbstractDict || fail("$location must be a table")
    actual = Set(String.(keys(value)))
    missing = sort!(collect(setdiff(expected, actual)))
    unknown = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        fail("$location is missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail("$location has unknown keys: $(join(unknown, ", "))")
    return value
end

function expect_nonempty_string(value, location)
    value isa AbstractString || fail("$location must be a string")
    text = String(value)
    isempty(strip(text)) && fail("$location must not be empty")
    strip(text) == text ||
        fail("$location must not have surrounding whitespace")
    return text
end

function expect_id(value, location)
    text = expect_nonempty_string(value, location)
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$", text) ||
        fail("$location contains unsupported characters")
    return text
end

function expect_hash(value, location)
    text = expect_nonempty_string(value, location)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail("$location must be 64 lowercase hexadecimal characters")
    return text
end

function expect_nonzero_hash(value, location)
    hash = expect_hash(value, location)
    hash != ZERO_HASH ||
        fail("$location must not be the zero hash")
    return hash
end

function expect_timestamp(value, location)
    text = expect_nonempty_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", text) ||
        fail("$location must be an RFC3339 UTC timestamp at second precision")
    try
        return DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch
        return fail("$location is not a valid timestamp")
    end
end

function expect_date(value, location)
    text = expect_nonempty_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}$", text) ||
        fail("$location must use YYYY-MM-DD")
    try
        return Date(text)
    catch
        return fail("$location is not a valid date")
    end
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail("$location must be an integer")
    value >= minimum || fail("$location must be at least $minimum")
    return Int(value)
end

function expect_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail("$location must be numeric")
    isfinite(value) || fail("$location must be finite")
    return Float64(value)
end

function header_path(directory)
    return joinpath(directory, "registry.toml")
end

function ledger_path(directory, kind)
    kind in ("forecast", "truth", "score") ||
        fail("unknown ledger kind $kind")
    return joinpath(directory, kind * "s.jsonl")
end

seal_path(directory) = joinpath(directory, "forecast_seal.toml")
quarantine_path(directory) =
    joinpath(directory, "truth_quarantine_manifest.toml")
reveal_path(directory) = joinpath(directory, "truth_reveal_receipt.toml")
lock_path(directory) = joinpath(directory, ".registry-write.lock")

function _with_lock(f::Function, directory)
    lock = lock_path(directory)
    try
        mkdir(lock)
    catch
        fail("registry is locked by another writer: $lock")
    end
    try
        return f()
    finally
        isdir(lock) && rm(lock)
    end
end

function _write_toml(path, payload)
    open(path, "w") do io
        TOML.print(io, payload; sorted = true)
    end
    return path
end

function _header_hash(payload)
    unhashed = Dict(
        key => payload[key]
            for key in setdiff(HEADER_KEYS, Set(["registry_header_sha256"]))
    )
    return sha256_hex(canonical(unhashed))
end

function validate_header(payload)
    expect_exact_keys(payload, HEADER_KEYS, "registry header")
    payload["schema_version"] == SCHEMA_VERSION ||
        fail("registry header has an unsupported schema version")
    expect_id(payload["experiment_id"], "registry header.experiment_id")
    expect_hash(payload["protocol_sha256"], "registry header.protocol_sha256")
    expect_hash(
        payload["environment_sha256"],
        "registry header.environment_sha256",
    )
    mode = payload["run_mode"]
    mode in (PROSPECTIVE_MODE, RETROSPECTIVE_MODE) ||
        fail("registry header.run_mode is not recognized")
    cutoff = expect_timestamp(
        payload["knowledge_cutoff_utc"],
        "registry header.knowledge_cutoff_utc",
    )
    created = expect_timestamp(
        payload["execution_created_at_utc"],
        "registry header.execution_created_at_utc",
    )
    created >= cutoff ||
        fail("registry execution cannot predate its knowledge cutoff")
    commitment = expect_hash(
        payload["truth_quarantine_commitment_sha256"],
        "registry header.truth_quarantine_commitment_sha256",
    )
    if mode == PROSPECTIVE_MODE
        payload["truth_access_policy"] == PROSPECTIVE_TRUTH_POLICY ||
            fail("prospective registry has the wrong truth-access policy")
        commitment == ZERO_HASH ||
            fail("prospective registry cannot have a truth-quarantine commitment")
    else
        payload["truth_access_policy"] == RETROSPECTIVE_TRUTH_POLICY ||
            fail("retrospective registry has the wrong truth-access policy")
        commitment != ZERO_HASH ||
            fail("retrospective registry requires a truth-quarantine commitment")
    end
    expected = _header_hash(payload)
    expect_hash(
        payload["registry_header_sha256"],
        "registry header.registry_header_sha256",
    ) == expected ||
        fail("registry header hash mismatch")
    return payload
end

function create_registry!(
        directory;
        experiment_id,
        protocol_sha256,
        environment_sha256,
        knowledge_cutoff_utc,
        execution_created_at_utc,
        run_mode = PROSPECTIVE_MODE,
        truth_quarantine_commitment_sha256 = ZERO_HASH,
    )
    if ispath(directory)
        isdir(directory) || fail("registry path is not a directory: $directory")
        isempty(readdir(directory)) ||
            fail("registry directory must be empty: $directory")
    else
        mkpath(directory)
    end
    header = Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "experiment_id" => expect_id(experiment_id, "experiment_id"),
        "protocol_sha256" =>
            expect_hash(protocol_sha256, "protocol_sha256"),
        "environment_sha256" =>
            expect_hash(environment_sha256, "environment_sha256"),
        "run_mode" => expect_nonempty_string(run_mode, "run_mode"),
        "knowledge_cutoff_utc" => expect_nonempty_string(
            knowledge_cutoff_utc,
            "knowledge_cutoff_utc",
        ),
        "truth_access_policy" => run_mode == PROSPECTIVE_MODE ?
            PROSPECTIVE_TRUTH_POLICY :
            RETROSPECTIVE_TRUTH_POLICY,
        "truth_quarantine_commitment_sha256" => expect_hash(
            truth_quarantine_commitment_sha256,
            "truth_quarantine_commitment_sha256",
        ),
        "execution_created_at_utc" => expect_nonempty_string(
            execution_created_at_utc,
            "execution_created_at_utc",
        ),
    )
    run_mode in (PROSPECTIVE_MODE, RETROSPECTIVE_MODE) ||
        fail("run_mode is not recognized")
    header["registry_header_sha256"] = _header_hash(header)
    validate_header(header)
    _write_toml(header_path(directory), header)
    for kind in ("forecast", "truth", "score")
        open(ledger_path(directory, kind), "w") do _
        end
    end
    return verify_registry(directory)
end

function read_header(directory)
    path = header_path(directory)
    isfile(path) || fail("registry header is missing: $path")
    return validate_header(normalize(TOML.parsefile(path), "registry header"))
end

function record_hash(kind, previous_sha256, payload)
    return sha256_hex(
        "kind:$kind\nprevious:$previous_sha256\npayload:" *
            canonical(payload),
    )
end

function read_ledger(directory, kind)
    path = ledger_path(directory, kind)
    isfile(path) || fail("$kind ledger is missing: $path")
    records = Dict{String, Any}[]
    previous = ZERO_HASH
    for (line_number, line) in enumerate(eachline(path))
        isempty(strip(line)) && fail("$kind ledger line $line_number is empty")
        envelope = try
            normalize(JSON.parse(line), "$kind ledger line $line_number")
        catch error
            error isa RegistryValidationError && rethrow()
            fail("$kind ledger line $line_number is not valid JSON")
        end
        expect_exact_keys(
            envelope,
            ENVELOPE_KEYS,
            "$kind ledger line $line_number",
        )
        envelope["kind"] == kind ||
            fail("$kind ledger line $line_number has the wrong record kind")
        expect_hash(
            envelope["previous_sha256"],
            "$kind ledger line $line_number.previous_sha256",
        ) == previous ||
            fail("$kind ledger hash chain breaks at line $line_number")
        payload = envelope["payload"]
        payload isa AbstractDict ||
            fail("$kind ledger line $line_number.payload must be a table")
        expected = record_hash(kind, previous, payload)
        expect_hash(
            envelope["record_sha256"],
            "$kind ledger line $line_number.record_sha256",
        ) == expected ||
            fail("$kind ledger record hash mismatch at line $line_number")
        push!(records, envelope)
        previous = expected
    end
    return records
end

function validate_forecast(payload, header)
    expect_exact_keys(payload, FORECAST_KEYS, "forecast payload")
    payload["schema_version"] == FORECAST_SCHEMA_VERSION ||
        fail("forecast payload has an unsupported schema version")
    payload["experiment_id"] == header["experiment_id"] ||
        fail("forecast experiment_id does not match the registry")
    payload["protocol_sha256"] == header["protocol_sha256"] ||
        fail("forecast protocol hash does not match the registry")
    for key in (
            "forecast_id",
            "origin_id",
            "model_id",
            "product_id",
            "target_id",
            "target_operator_version",
            "transformation_version",
            "truth_key",
        )
        expect_id(payload[key], "forecast.$key")
    end
    for key in (
            "origin_manifest_sha256",
            "protocol_sha256",
            "model_manifest_sha256",
            "model_card_sha256",
            "seed_key_sha256",
        )
        expect_hash(payload[key], "forecast.$key")
    end
    for key in (
            "origin_data_sample_sha256",
            "origin_data_receipt_sha256",
        )
        expect_nonzero_hash(payload[key], "forecast.$key")
    end
    registered = expect_timestamp(
        payload["execution_registered_at_utc"],
        "forecast.execution_registered_at_utc",
    )
    origin = expect_timestamp(
        payload["origin_timestamp_utc"],
        "forecast.origin_timestamp_utc",
    )
    cutoff = expect_timestamp(
        header["knowledge_cutoff_utc"],
        "registry header.knowledge_cutoff_utc",
    )
    created = expect_timestamp(
        header["execution_created_at_utc"],
        "registry header.execution_created_at_utc",
    )
    origin == cutoff ||
        fail("forecast origin does not match the registry knowledge cutoff")
    registered >= created ||
        fail("forecast cannot be registered before the registry is created")
    registered >= origin ||
        fail("forecast cannot be registered before its origin")
    period_start =
        expect_date(payload["target_period_start"], "forecast.target_period_start")
    period_end =
        expect_date(payload["target_period_end"], "forecast.target_period_end")
    period_start <= period_end ||
        fail("forecast target period is reversed")
    expect_integer(payload["horizon"], "forecast.horizon"; minimum = 0)
    expect_integer(payload["n_draws"], "forecast.n_draws"; minimum = 0)
    expect_integer(payload["seed"], "forecast.seed"; minimum = 0)
    payload["information_track"] in
        ("common_information", "published_forecast") ||
        fail("forecast.information_track is not recognized")
    status = payload["status"]
    status in ("success", "failed") ||
        fail("forecast.status is not recognized")
    if status == "success"
        expect_number(payload["point_forecast"], "forecast.point_forecast")
        payload["failure_code"] === nothing ||
            fail("successful forecast cannot have a failure_code")
        if payload["n_draws"] > 0
            expect_hash(
                payload["distribution_artifact_sha256"],
                "forecast.distribution_artifact_sha256",
            )
        else
            payload["distribution_artifact_sha256"] === nothing ||
                fail("point-only forecast cannot name a distribution artifact")
        end
    else
        payload["point_forecast"] === nothing ||
            fail("failed forecast cannot have a point forecast")
        payload["distribution_artifact_sha256"] === nothing ||
            fail("failed forecast cannot have a distribution artifact")
        payload["n_draws"] == 0 ||
            fail("failed forecast must have zero draws")
        expect_id(payload["failure_code"], "forecast.failure_code")
    end
    for key in keys(payload)
        lowercase_key = lowercase(String(key))
        any(
            fragment -> occursin(fragment, lowercase_key),
            FORBIDDEN_FORECAST_KEY_FRAGMENTS,
        ) && key ∉ ("target_operator_version",) &&
            fail("forecast payload contains forbidden outcome field $key")
    end
    return payload
end

function validate_truth(payload, header)
    expect_exact_keys(payload, TRUTH_KEYS, "truth payload")
    payload["schema_version"] == TRUTH_SCHEMA_VERSION ||
        fail("truth payload has an unsupported schema version")
    payload["experiment_id"] == header["experiment_id"] ||
        fail("truth experiment_id does not match the registry")
    for key in (
            "truth_id",
            "truth_key",
            "target_id",
            "target_operator_version",
            "transformation_version",
        )
        expect_id(payload[key], "truth.$key")
    end
    appended = expect_timestamp(
        payload["execution_appended_at_utc"],
        "truth.execution_appended_at_utc",
    )
    released = expect_timestamp(
        payload["release_timestamp_utc"],
        "truth.release_timestamp_utc",
    )
    appended >= released ||
        fail("truth cannot be appended before its release")
    period_start =
        expect_date(payload["target_period_start"], "truth.target_period_start")
    period_end =
        expect_date(payload["target_period_end"], "truth.target_period_end")
    period_start <= period_end ||
        fail("truth target period is reversed")
    payload["truth_vintage"] in ("first_release", "near_mature", "mature") ||
        fail("truth.truth_vintage is not recognized")
    expect_number(payload["value"], "truth.value")
    expect_hash(
        payload["source_artifact_sha256"],
        "truth.source_artifact_sha256",
    )
    return payload
end

function validate_score(payload, header)
    expect_exact_keys(payload, SCORE_KEYS, "score payload")
    payload["schema_version"] == SCORE_SCHEMA_VERSION ||
        fail("score payload has an unsupported schema version")
    payload["experiment_id"] == header["experiment_id"] ||
        fail("score experiment_id does not match the registry")
    for key in (
            "score_id",
            "forecast_id",
            "truth_id",
            "evaluation_version",
            "metric",
        )
        expect_id(payload[key], "score.$key")
    end
    expect_hash(
        payload["forecast_record_sha256"],
        "score.forecast_record_sha256",
    )
    expect_hash(payload["truth_record_sha256"], "score.truth_record_sha256")
    expect_number(payload["value"], "score.value")
    expect_timestamp(
        payload["execution_evaluated_at_utc"],
        "score.execution_evaluated_at_utc",
    )
    return payload
end

function validate_quarantine_truth(payload, header)
    expect_exact_keys(
        payload,
        QUARANTINE_TRUTH_KEYS,
        "truth-quarantine record",
    )
    for key in (
            "truth_id",
            "truth_key",
            "target_id",
            "target_operator_version",
            "transformation_version",
        )
        expect_id(payload[key], "truth-quarantine record.$key")
    end
    released = expect_timestamp(
        payload["release_timestamp_utc"],
        "truth-quarantine record.release_timestamp_utc",
    )
    created = expect_timestamp(
        header["execution_created_at_utc"],
        "registry header.execution_created_at_utc",
    )
    released <= created ||
        fail(
        "retrospective truth must have been released by registry execution",
    )
    period_start = expect_date(
        payload["target_period_start"],
        "truth-quarantine record.target_period_start",
    )
    period_end = expect_date(
        payload["target_period_end"],
        "truth-quarantine record.target_period_end",
    )
    period_start <= period_end ||
        fail("truth-quarantine target period is reversed")
    payload["truth_vintage"] in ("first_release", "near_mature", "mature") ||
        fail("truth-quarantine record.truth_vintage is not recognized")
    expect_number(payload["value"], "truth-quarantine record.value")
    expect_hash(
        payload["source_artifact_sha256"],
        "truth-quarantine record.source_artifact_sha256",
    )
    return payload
end

forecast_semantic_key(payload) = (
    payload["origin_id"],
    payload["model_id"],
    payload["product_id"],
    payload["information_track"],
    payload["target_id"],
    payload["target_operator_version"],
    payload["transformation_version"],
    payload["horizon"],
    payload["target_period_start"],
    payload["target_period_end"],
)

truth_semantic_key(payload) =
    (payload["truth_key"], payload["truth_vintage"])

truth_target_key(payload) = (
    payload["truth_key"],
    payload["target_id"],
    payload["target_operator_version"],
    payload["transformation_version"],
    payload["target_period_start"],
    payload["target_period_end"],
)

score_semantic_key(payload) = (
    payload["forecast_id"],
    payload["truth_id"],
    payload["evaluation_version"],
    payload["metric"],
)

function read_quarantine_manifest(path, header, forecasts)
    isfile(path) || fail("truth-quarantine manifest is missing: $path")
    manifest_bytes = read(path)
    raw = try
        normalize(
            TOML.parse(String(copy(manifest_bytes))),
            "truth-quarantine manifest",
        )
    catch error
        error isa RegistryValidationError && rethrow()
        fail("truth-quarantine manifest is not valid TOML")
    end
    expect_exact_keys(raw, QUARANTINE_KEYS, "truth-quarantine manifest")
    artifact = raw["artifact"]
    expect_exact_keys(
        artifact,
        QUARANTINE_ARTIFACT_KEYS,
        "truth-quarantine artifact",
    )
    artifact["schema_version"] == QUARANTINE_SCHEMA_VERSION ||
        fail("truth-quarantine manifest has an unsupported schema version")
    artifact["experiment_id"] == header["experiment_id"] ||
        fail("truth-quarantine experiment_id does not match the registry")
    artifact["protocol_sha256"] == header["protocol_sha256"] ||
        fail("truth-quarantine protocol hash does not match the registry")
    artifact["knowledge_cutoff_utc"] == header["knowledge_cutoff_utc"] ||
        fail("truth-quarantine knowledge cutoff does not match the registry")
    expect_timestamp(
        artifact["knowledge_cutoff_utc"],
        "truth-quarantine artifact.knowledge_cutoff_utc",
    )
    records = raw["truth_records"]
    records isa AbstractVector ||
        fail("truth-quarantine truth_records must be an array of tables")
    expected_count = expect_integer(
        artifact["truth_record_count"],
        "truth-quarantine artifact.truth_record_count";
        minimum = 1,
    )
    expected_count == length(records) ||
        fail("truth-quarantine record count mismatch")

    truth_ids = Set{String}()
    truth_keys = Set{Tuple}()
    committed_targets = Set{Tuple}()
    for (index, record) in enumerate(records)
        record isa AbstractDict ||
            fail("truth-quarantine record $index must be a table")
        validate_quarantine_truth(record, header)
        truth_id = record["truth_id"]
        truth_id in truth_ids &&
            fail("duplicate truth_id $truth_id in truth-quarantine manifest")
        push!(truth_ids, truth_id)
        semantic_key = truth_semantic_key(record)
        semantic_key in truth_keys &&
            fail(
            "duplicate truth key/vintage in truth-quarantine manifest for $truth_id",
        )
        push!(truth_keys, semantic_key)
        push!(committed_targets, truth_target_key(record))
    end

    forecast_targets =
        Set(truth_target_key(record["payload"]) for record in forecasts)
    isempty(setdiff(committed_targets, forecast_targets)) ||
        fail("truth-quarantine manifest contains an unregistered target")
    isempty(setdiff(forecast_targets, committed_targets)) ||
        fail("truth-quarantine manifest does not cover every forecast target")
    return (
        artifact = artifact,
        records = records,
        manifest_sha256 = bytes2hex(SHA.sha256(manifest_bytes)),
        manifest_bytes = manifest_bytes,
    )
end

function committed_truth_matches(payload, committed)
    return all(QUARANTINE_TRUTH_KEYS) do key
        canonical(payload[key]) == canonical(committed[key])
    end
end

function validate_score_link(payload, forecast_record, truth_record)
    id = payload["score_id"]
    payload["forecast_record_sha256"] ==
        forecast_record["record_sha256"] ||
        fail("score $id has the wrong forecast record hash")
    payload["truth_record_sha256"] == truth_record["record_sha256"] ||
        fail("score $id has the wrong truth record hash")
    forecast_payload = forecast_record["payload"]
    truth_payload = truth_record["payload"]
    evaluated = expect_timestamp(
        payload["execution_evaluated_at_utc"],
        "score.execution_evaluated_at_utc",
    )
    appended = expect_timestamp(
        truth_payload["execution_appended_at_utc"],
        "truth.execution_appended_at_utc",
    )
    evaluated >= appended ||
        fail("score $id cannot be evaluated before truth is appended")
    forecast_payload["status"] == "success" ||
        fail("score $id cannot be attached to a failed forecast")
    forecast_payload["truth_key"] == truth_payload["truth_key"] ||
        fail("score $id joins a forecast to unrelated truth")
    for key in (
            "target_id",
            "target_operator_version",
            "transformation_version",
            "target_period_start",
            "target_period_end",
        )
        forecast_payload[key] == truth_payload[key] ||
            fail("score $id has a forecast/truth $key mismatch")
    end
    return payload
end

function validate_truth_link(payload, forecasts, seal, header, reveal)
    id = payload["truth_id"]
    seal === nothing &&
        fail("truth $id exists before the forecast ledger was sealed")
    released = expect_timestamp(
        payload["release_timestamp_utc"],
        "truth.release_timestamp_utc",
    )
    if header["run_mode"] == PROSPECTIVE_MODE
        sealed = expect_timestamp(
            seal["execution_sealed_at_utc"],
            "forecast seal.execution_sealed_at_utc",
        )
        released > sealed ||
            fail("truth $id was released before the forecast ledger was sealed")
    else
        reveal === nothing &&
            fail("truth $id exists before retrospective truth was revealed")
        appended = expect_timestamp(
            payload["execution_appended_at_utc"],
            "truth.execution_appended_at_utc",
        )
        revealed = expect_timestamp(
            reveal.receipt["execution_revealed_at_utc"],
            "truth reveal.execution_revealed_at_utc",
        )
        appended >= revealed ||
            fail("truth $id was appended before retrospective truth reveal")
        committed_index = findfirst(
            record -> record["truth_id"] == id,
            reveal.manifest.records,
        )
        committed_index === nothing &&
            fail("truth $id is absent from the truth-quarantine manifest")
        committed_truth_matches(
            payload,
            reveal.manifest.records[committed_index],
        ) || fail("truth $id differs from its quarantined commitment")
    end
    matching_forecast = any(forecasts) do record
        forecast = record["payload"]
        forecast["truth_key"] == payload["truth_key"] &&
            all(
            key -> forecast[key] == payload[key],
            (
                "target_id",
                "target_operator_version",
                "transformation_version",
                "target_period_start",
                "target_period_end",
            ),
        )
    end
    matching_forecast ||
        fail("truth $id does not match any registered forecast target")
    return payload
end

function _seal_hash(payload)
    unhashed = Dict(
        key => payload[key]
            for key in setdiff(SEAL_KEYS, Set(["seal_sha256"]))
    )
    return sha256_hex(canonical(unhashed))
end

function read_seal(directory, header, forecasts)
    path = seal_path(directory)
    isfile(path) || return nothing
    seal = normalize(TOML.parsefile(path), "forecast seal")
    expect_exact_keys(seal, SEAL_KEYS, "forecast seal")
    seal["schema_version"] == SCHEMA_VERSION * ".forecast-seal" ||
        fail("forecast seal has an unsupported schema version")
    seal["experiment_id"] == header["experiment_id"] ||
        fail("forecast seal experiment_id does not match the registry")
    sealed = expect_timestamp(
        seal["execution_sealed_at_utc"],
        "forecast seal.execution_sealed_at_utc",
    )
    created = expect_timestamp(
        header["execution_created_at_utc"],
        "registry header.execution_created_at_utc",
    )
    sealed >= created ||
        fail("forecast seal predates the registry")
    all(forecasts) do record
        registered = expect_timestamp(
            record["payload"]["execution_registered_at_utc"],
            "forecast.execution_registered_at_utc",
        )
        registered <= sealed
    end || fail("forecast seal predates a registered forecast")
    expect_integer(
        seal["forecast_count"],
        "forecast seal.forecast_count";
        minimum = 1,
    ) == length(forecasts) ||
        fail("forecast seal count mismatch")
    chain_hash =
        isempty(forecasts) ? ZERO_HASH : forecasts[end]["record_sha256"]
    expect_hash(
        seal["forecast_chain_sha256"],
        "forecast seal.forecast_chain_sha256",
    ) == chain_hash ||
        fail("forecast seal chain hash mismatch")
    expect_hash(
        seal["forecasts_file_sha256"],
        "forecast seal.forecasts_file_sha256",
    ) == file_sha256(ledger_path(directory, "forecast")) ||
        fail("sealed forecast ledger bytes have changed")
    seal["registry_header_sha256"] == header["registry_header_sha256"] ||
        fail("forecast seal registry-header hash mismatch")
    expect_hash(seal["seal_sha256"], "forecast seal.seal_sha256") ==
        _seal_hash(seal) ||
        fail("forecast seal hash mismatch")
    return seal
end

function _reveal_hash(payload)
    unhashed = Dict(
        key => payload[key]
            for key in setdiff(REVEAL_KEYS, Set(["reveal_sha256"]))
    )
    return sha256_hex(canonical(unhashed))
end

function read_reveal(directory, header, forecasts, seal)
    manifest_exists = isfile(quarantine_path(directory))
    receipt_exists = isfile(reveal_path(directory))
    if header["run_mode"] == PROSPECTIVE_MODE
        (manifest_exists || receipt_exists) &&
            fail("prospective registry cannot contain retrospective truth artifacts")
        return nothing
    end
    manifest_exists == receipt_exists ||
        fail("retrospective truth reveal is incomplete")
    manifest_exists || return nothing
    seal === nothing &&
        fail("retrospective truth was revealed before forecasts were sealed")

    manifest =
        read_quarantine_manifest(quarantine_path(directory), header, forecasts)
    receipt = try
        normalize(
            TOML.parsefile(reveal_path(directory)),
            "truth-reveal receipt",
        )
    catch error
        error isa RegistryValidationError && rethrow()
        fail("truth-reveal receipt is not valid TOML")
    end
    expect_exact_keys(receipt, REVEAL_KEYS, "truth-reveal receipt")
    receipt["schema_version"] == REVEAL_SCHEMA_VERSION ||
        fail("truth-reveal receipt has an unsupported schema version")
    receipt["experiment_id"] == header["experiment_id"] ||
        fail("truth-reveal experiment_id does not match the registry")
    revealed = expect_timestamp(
        receipt["execution_revealed_at_utc"],
        "truth reveal.execution_revealed_at_utc",
    )
    sealed = expect_timestamp(
        seal["execution_sealed_at_utc"],
        "forecast seal.execution_sealed_at_utc",
    )
    revealed > sealed ||
        fail("retrospective truth reveal must occur after forecast sealing")
    manifest_hash = expect_hash(
        receipt["quarantine_manifest_sha256"],
        "truth reveal.quarantine_manifest_sha256",
    )
    manifest_hash == manifest.manifest_sha256 ||
        fail("revealed truth-quarantine manifest bytes have changed")
    nonce = expect_hash(
        receipt["commitment_nonce"],
        "truth reveal.commitment_nonce",
    )
    nonce != ZERO_HASH ||
        fail("truth reveal.commitment_nonce must not be the zero hash")
    commitment = expect_hash(
        receipt["truth_quarantine_commitment_sha256"],
        "truth reveal.truth_quarantine_commitment_sha256",
    )
    commitment == header["truth_quarantine_commitment_sha256"] ||
        fail("truth reveal commitment does not match the registry header")
    _quarantine_commitment(manifest_hash, nonce) == commitment ||
        fail("truth reveal does not open the registry commitment")
    expect_integer(
        receipt["truth_record_count"],
        "truth reveal.truth_record_count";
        minimum = 1,
    ) == length(manifest.records) ||
        fail("truth reveal record count mismatch")
    expect_hash(
        receipt["forecast_seal_sha256"],
        "truth reveal.forecast_seal_sha256",
    ) == seal["seal_sha256"] ||
        fail("truth reveal forecast-seal hash mismatch")
    expect_hash(
        receipt["forecast_chain_sha256"],
        "truth reveal.forecast_chain_sha256",
    ) == seal["forecast_chain_sha256"] ||
        fail("truth reveal forecast-chain hash mismatch")
    expect_hash(
        receipt["forecasts_file_sha256"],
        "truth reveal.forecasts_file_sha256",
    ) == seal["forecasts_file_sha256"] ||
        fail("truth reveal forecast-file hash mismatch")
    expect_hash(
        receipt["registry_header_sha256"],
        "truth reveal.registry_header_sha256",
    ) == header["registry_header_sha256"] ||
        fail("truth reveal registry-header hash mismatch")
    expect_hash(receipt["reveal_sha256"], "truth reveal.reveal_sha256") ==
        _reveal_hash(receipt) ||
        fail("truth reveal hash mismatch")
    return (receipt = receipt, manifest = manifest)
end

function verify_registry(directory)
    isdir(directory) || fail("registry directory does not exist: $directory")
    header = read_header(directory)
    forecasts = read_ledger(directory, "forecast")
    truths = read_ledger(directory, "truth")
    scores = read_ledger(directory, "score")
    foreach(record -> validate_forecast(record["payload"], header), forecasts)
    foreach(record -> validate_truth(record["payload"], header), truths)
    foreach(record -> validate_score(record["payload"], header), scores)

    forecast_by_id = Dict{String, Dict{String, Any}}()
    forecast_keys = Set{Tuple}()
    for record in forecasts
        payload = record["payload"]
        id = payload["forecast_id"]
        haskey(forecast_by_id, id) &&
            fail("duplicate forecast_id $id")
        forecast_key = forecast_semantic_key(payload)
        forecast_key in forecast_keys &&
            fail("duplicate semantic forecast key for forecast_id $id")
        push!(forecast_keys, forecast_key)
        forecast_by_id[id] = record
    end

    seal = read_seal(directory, header, forecasts)
    (!isempty(truths) || !isempty(scores)) && seal === nothing &&
        fail("truth or scores exist before the forecast ledger was sealed")
    reveal = read_reveal(directory, header, forecasts, seal)
    if header["run_mode"] == RETROSPECTIVE_MODE
        (!isempty(truths) || !isempty(scores)) && reveal === nothing &&
            fail("truth or scores exist before retrospective truth reveal")
    end

    truth_by_id = Dict{String, Dict{String, Any}}()
    truth_keys = Set{Tuple}()
    for record in truths
        payload = record["payload"]
        id = payload["truth_id"]
        haskey(truth_by_id, id) && fail("duplicate truth_id $id")
        truth_key = truth_semantic_key(payload)
        truth_key in truth_keys &&
            fail("duplicate truth key/vintage for truth_id $id")
        push!(truth_keys, truth_key)
        truth_by_id[id] = record
        validate_truth_link(payload, forecasts, seal, header, reveal)
    end
    truth_reveal_complete =
        header["run_mode"] == RETROSPECTIVE_MODE && reveal !== nothing ?
        length(truths) == length(reveal.manifest.records) : nothing
    !isempty(scores) &&
        header["run_mode"] == RETROSPECTIVE_MODE &&
        truth_reveal_complete !== true &&
        fail("scores require every quarantined truth record to be appended")

    score_ids = Set{String}()
    score_keys = Set{Tuple}()
    for record in scores
        payload = record["payload"]
        id = payload["score_id"]
        id in score_ids && fail("duplicate score_id $id")
        push!(score_ids, id)
        haskey(forecast_by_id, payload["forecast_id"]) ||
            fail("score $id references an unknown forecast")
        haskey(truth_by_id, payload["truth_id"]) ||
            fail("score $id references unknown truth")
        forecast_record = forecast_by_id[payload["forecast_id"]]
        truth_record = truth_by_id[payload["truth_id"]]
        validate_score_link(payload, forecast_record, truth_record)
        score_key = score_semantic_key(payload)
        score_key in score_keys &&
            fail("duplicate semantic score key for score_id $id")
        push!(score_keys, score_key)
    end

    return (
        header,
        forecasts,
        truths,
        scores,
        seal,
        reveal,
        forecast_count = length(forecasts),
        truth_count = length(truths),
        score_count = length(scores),
        committed_truth_count =
            reveal === nothing ? nothing : length(reveal.manifest.records),
        truth_reveal_complete,
        verified = true,
    )
end

function append_envelope!(directory, kind, payload, records)
    previous =
        isempty(records) ? ZERO_HASH : records[end]["record_sha256"]
    envelope = Dict{String, Any}(
        "kind" => kind,
        "payload" => payload,
        "previous_sha256" => previous,
        "record_sha256" => record_hash(kind, previous, payload),
    )
    open(ledger_path(directory, kind), "a") do io
        write(io, JSON.json(envelope))
        write(io, '\n')
        flush(io)
    end
    return envelope
end

function append_forecast!(directory, raw_payload)
    return _with_lock(directory) do
        registry = verify_registry(directory)
        registry.seal === nothing ||
            fail("forecast ledger is sealed")
        payload = normalize(raw_payload, "forecast payload")
        validate_forecast(payload, registry.header)
        any(
            record -> record["payload"]["forecast_id"] ==
                payload["forecast_id"],
            registry.forecasts,
        ) && fail("duplicate forecast_id $(payload["forecast_id"])")
        key = forecast_semantic_key(payload)
        any(
            record -> forecast_semantic_key(record["payload"]) == key,
            registry.forecasts,
        ) && fail(
            "duplicate semantic forecast key for forecast_id $(payload["forecast_id"])",
        )
        envelope = append_envelope!(
            directory,
            "forecast",
            payload,
            registry.forecasts,
        )
        verify_registry(directory)
        return envelope
    end
end

function seal_forecasts!(directory; execution_sealed_at_utc)
    return _with_lock(directory) do
        registry = verify_registry(directory)
        registry.seal === nothing ||
            fail("forecast ledger is already sealed")
        isempty(registry.forecasts) &&
            fail("cannot seal an empty forecast ledger")
        sealed = expect_timestamp(
            execution_sealed_at_utc,
            "execution_sealed_at_utc",
        )
        created = expect_timestamp(
            registry.header["execution_created_at_utc"],
            "registry header.execution_created_at_utc",
        )
        sealed >= created ||
            fail("forecast seal predates the registry")
        all(registry.forecasts) do record
            registered = expect_timestamp(
                record["payload"]["execution_registered_at_utc"],
                "forecast.execution_registered_at_utc",
            )
            registered <= sealed
        end || fail("forecast seal predates a registered forecast")
        seal = Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION * ".forecast-seal",
            "experiment_id" => registry.header["experiment_id"],
            "execution_sealed_at_utc" =>
                String(execution_sealed_at_utc),
            "forecast_count" => length(registry.forecasts),
            "forecast_chain_sha256" =>
                registry.forecasts[end]["record_sha256"],
            "forecasts_file_sha256" =>
                file_sha256(ledger_path(directory, "forecast")),
            "registry_header_sha256" =>
                registry.header["registry_header_sha256"],
        )
        seal["seal_sha256"] = _seal_hash(seal)
        _write_toml(seal_path(directory), seal)
        return verify_registry(directory).seal
    end
end

"""
    reveal_retrospective_truth!(directory;
        quarantine_manifest_path, commitment_nonce,
        execution_revealed_at_utc)

After the forecast ledger is sealed, verify and open a retrospective registry's
salted truth commitment. The exact committed manifest bytes and a receipt bound
to the registry header and forecast seal are then installed in the registry.
"""
function reveal_retrospective_truth!(
        directory;
        quarantine_manifest_path,
        commitment_nonce,
        execution_revealed_at_utc,
    )
    return _with_lock(directory) do
        registry = verify_registry(directory)
        registry.header["run_mode"] == RETROSPECTIVE_MODE ||
            fail("truth reveal is only valid for retrospective registries")
        registry.seal === nothing &&
            fail("forecasts must be sealed before retrospective truth reveal")
        registry.reveal === nothing ||
            fail("retrospective truth was already revealed")
        isempty(registry.truths) && isempty(registry.scores) ||
            fail("truth reveal requires empty truth and score ledgers")
        manifest = read_quarantine_manifest(
            quarantine_manifest_path,
            registry.header,
            registry.forecasts,
        )
        nonce = expect_hash(commitment_nonce, "commitment_nonce")
        nonce != ZERO_HASH ||
            fail("commitment_nonce must not be the zero hash")
        commitment =
            _quarantine_commitment(manifest.manifest_sha256, nonce)
        commitment ==
            registry.header["truth_quarantine_commitment_sha256"] ||
            fail("truth-quarantine manifest or nonce does not open the commitment")
        revealed = expect_timestamp(
            execution_revealed_at_utc,
            "execution_revealed_at_utc",
        )
        sealed = expect_timestamp(
            registry.seal["execution_sealed_at_utc"],
            "forecast seal.execution_sealed_at_utc",
        )
        revealed > sealed ||
            fail("retrospective truth reveal must occur after forecast sealing")

        receipt = Dict{String, Any}(
            "schema_version" => REVEAL_SCHEMA_VERSION,
            "experiment_id" => registry.header["experiment_id"],
            "execution_revealed_at_utc" =>
                String(execution_revealed_at_utc),
            "quarantine_manifest_sha256" => manifest.manifest_sha256,
            "commitment_nonce" => nonce,
            "truth_quarantine_commitment_sha256" => commitment,
            "truth_record_count" => length(manifest.records),
            "forecast_seal_sha256" => registry.seal["seal_sha256"],
            "forecast_chain_sha256" =>
                registry.seal["forecast_chain_sha256"],
            "forecasts_file_sha256" =>
                registry.seal["forecasts_file_sha256"],
            "registry_header_sha256" =>
                registry.header["registry_header_sha256"],
        )
        receipt["reveal_sha256"] = _reveal_hash(receipt)
        open(quarantine_path(directory), "w") do io
            write(io, manifest.manifest_bytes)
            flush(io)
        end
        _write_toml(reveal_path(directory), receipt)
        return verify_registry(directory).reveal
    end
end

function append_truth!(directory, raw_payload)
    return _with_lock(directory) do
        registry = verify_registry(directory)
        registry.seal === nothing &&
            fail("forecast ledger must be sealed before truth is appended")
        payload = normalize(raw_payload, "truth payload")
        validate_truth(payload, registry.header)
        validate_truth_link(
            payload,
            registry.forecasts,
            registry.seal,
            registry.header,
            registry.reveal,
        )
        any(
            record -> record["payload"]["truth_id"] == payload["truth_id"],
            registry.truths,
        ) && fail("duplicate truth_id $(payload["truth_id"])")
        key = truth_semantic_key(payload)
        any(
            record -> truth_semantic_key(record["payload"]) == key,
            registry.truths,
        ) && fail(
            "duplicate truth key/vintage for truth_id $(payload["truth_id"])",
        )
        envelope =
            append_envelope!(directory, "truth", payload, registry.truths)
        verify_registry(directory)
        return envelope
    end
end

function append_score!(directory, raw_payload)
    return _with_lock(directory) do
        registry = verify_registry(directory)
        registry.seal === nothing &&
            fail("forecast ledger must be sealed before scores are appended")
        registry.header["run_mode"] == RETROSPECTIVE_MODE &&
            registry.truth_reveal_complete !== true &&
            fail("scores require every quarantined truth record to be appended")
        payload = normalize(raw_payload, "score payload")
        validate_score(payload, registry.header)
        any(
            record -> record["payload"]["score_id"] == payload["score_id"],
            registry.scores,
        ) && fail("duplicate score_id $(payload["score_id"])")
        forecast_record = findfirst(
            record -> record["payload"]["forecast_id"] ==
                payload["forecast_id"],
            registry.forecasts,
        )
        forecast_record === nothing &&
            fail("score $(payload["score_id"]) references an unknown forecast")
        truth_record = findfirst(
            record -> record["payload"]["truth_id"] == payload["truth_id"],
            registry.truths,
        )
        truth_record === nothing &&
            fail("score $(payload["score_id"]) references unknown truth")
        validate_score_link(
            payload,
            registry.forecasts[forecast_record],
            registry.truths[truth_record],
        )
        key = score_semantic_key(payload)
        any(
            record -> score_semantic_key(record["payload"]) == key,
            registry.scores,
        ) && fail(
            "duplicate semantic score key for score_id $(payload["score_id"])",
        )
        envelope =
            append_envelope!(directory, "score", payload, registry.scores)
        verify_registry(directory)
        return envelope
    end
end

function seed_key(
        master_seed;
        experiment_id,
        origin_manifest_sha256,
        model_id,
        path_id,
        purpose,
    )
    seed = expect_integer(master_seed, "master_seed"; minimum = 0)
    experiment = expect_id(experiment_id, "experiment_id")
    origin_hash = expect_hash(
        origin_manifest_sha256,
        "origin_manifest_sha256",
    )
    model = expect_id(model_id, "model_id")
    path = expect_integer(path_id, "path_id"; minimum = 0)
    purpose_id = expect_id(purpose, "purpose")
    return Dict(
        "schema_version" => "beforeit-us-rng-substream.v1",
        "master_seed" => seed,
        "experiment_id" => experiment,
        "origin_manifest_sha256" => origin_hash,
        "model_id" => model,
        "path_id" => path,
        "purpose" => purpose_id,
    )
end

"""
    derive_seed_record(master_seed; experiment_id, origin_manifest_sha256,
                       model_id, path_id, purpose)

Derive a deterministic, non-negative `Int` seed and the SHA-256 of its full
experiment/origin/model/path namespace. The derivation is independent of task
scheduling and does not consume the process-global RNG.
"""
function derive_seed_record(master_seed; kwargs...)
    namespace = seed_key(master_seed; kwargs...)
    digest = SHA.sha256(canonical(namespace))
    unsigned = zero(UInt64)
    for byte in digest[1:8]
        unsigned = (unsigned << 8) | UInt64(byte)
    end
    return (
        seed = Int(unsigned % UInt64(typemax(Int))),
        seed_key_sha256 = bytes2hex(digest),
        namespace,
    )
end

"""
    derive_seed(master_seed; experiment_id, origin_manifest_sha256, model_id,
                path_id, purpose)

Return only the deterministic seed from [`derive_seed_record`](@ref).
"""
function derive_seed(master_seed; kwargs...)
    return derive_seed_record(master_seed; kwargs...).seed
end

end
