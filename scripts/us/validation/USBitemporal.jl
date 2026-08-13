module USBitemporal

using DataFrames
using Dates
using SHA

export REQUIRED_COLUMNS,
    BitemporalValidationError,
    asof_snapshot,
    origin_manifest,
    validate_observations

const REQUIRED_COLUMNS = (
    :series_id,
    :reference_period_start,
    :reference_period_end,
    :value,
    :release_timestamp_utc,
    :realtime_start,
    :realtime_end,
    :source_release_id,
    :source_url_or_file,
    :raw_sha256,
    :retrieved_at_utc,
    :unit,
    :frequency,
    :seasonal_adjustment,
    :annual_rate_flag,
    :stock_flow_index_rate,
    :price_basis,
    :classification,
    :classification_vintage,
    :transformation_version,
    :quality_status,
)
const ALLOWED_QUALITY_STATUSES =
    Set(["APPROVED", "DUBIOUS", "REJECTED", "MISSING"])
const SNAPSHOT_KEY = (
    :series_id,
    :reference_period_start,
    :reference_period_end,
    :transformation_version,
)
const UNIQUE_OBSERVATION_KEY = (
    SNAPSHOT_KEY...,
    :release_timestamp_utc,
    :source_release_id,
)
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

struct BitemporalValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::BitemporalValidationError) =
    print(io, error.message)

fail(message) = throw(BitemporalValidationError(String(message)))

function nonempty_string(value, location)
    value isa AbstractString ||
        fail("$location must be a string")
    text = String(value)
    isempty(strip(text)) &&
        fail("$location must not be empty")
    strip(text) == text ||
        fail("$location must not have surrounding whitespace")
    return text
end

function validate_value(value, quality_status, location)
    if ismissing(value)
        quality_status == "MISSING" ||
            fail("$location may be missing only when quality_status is MISSING")
        return value
    end
    value isa Real && !(value isa Bool) ||
        fail("$location must be a real number or missing")
    isfinite(value) || fail("$location must be finite")
    quality_status != "MISSING" ||
        fail("$location must be missing when quality_status is MISSING")
    return value
end

function validate_observations(observations::AbstractDataFrame)
    actual_columns = Set(Symbol.(names(observations)))
    expected_columns = Set(REQUIRED_COLUMNS)
    missing_columns = sort!(collect(setdiff(expected_columns, actual_columns)))
    unknown_columns = sort!(collect(setdiff(actual_columns, expected_columns)))
    isempty(missing_columns) ||
        fail("observations are missing columns: $(join(missing_columns, ", "))")
    isempty(unknown_columns) ||
        fail("observations have unknown columns: $(join(unknown_columns, ", "))")

    seen_keys = Set{Tuple}()
    for (row_number, row) in enumerate(eachrow(observations))
        location = "observations[$row_number]"
        for column in (
                :series_id,
                :source_release_id,
                :source_url_or_file,
                :unit,
                :frequency,
                :seasonal_adjustment,
                :stock_flow_index_rate,
                :price_basis,
                :classification,
                :classification_vintage,
                :transformation_version,
            )
            nonempty_string(row[column], "$location.$column")
        end
        row.reference_period_start isa Date ||
            fail("$location.reference_period_start must be a Date")
        row.reference_period_end isa Date ||
            fail("$location.reference_period_end must be a Date")
        row.reference_period_start <= row.reference_period_end ||
            fail("$location has a reversed reference-period interval")
        row.release_timestamp_utc isa DateTime ||
            fail("$location.release_timestamp_utc must be a UTC DateTime")
        row.retrieved_at_utc isa DateTime ||
            fail("$location.retrieved_at_utc must be a UTC DateTime")
        row.release_timestamp_utc <= row.retrieved_at_utc ||
            fail("$location was retrieved before its release timestamp")
        row.realtime_start isa Date ||
            fail("$location.realtime_start must be a Date")
        row.realtime_end isa Date ||
            fail("$location.realtime_end must be a Date")
        row.realtime_start <= row.realtime_end ||
            fail("$location has a reversed realtime interval")
        row.realtime_start <= Date(row.release_timestamp_utc) <=
            row.realtime_end ||
            fail(
            "$location release date must fall inside its realtime interval",
        )
        row.annual_rate_flag isa Bool ||
            fail("$location.annual_rate_flag must be Boolean")
        raw_sha256 = nonempty_string(
            row.raw_sha256,
            "$location.raw_sha256",
        )
        occursin(r"^[0-9a-f]{64}$", raw_sha256) ||
            fail("$location.raw_sha256 must be 64 lowercase hexadecimal characters")
        quality_status =
            nonempty_string(row.quality_status, "$location.quality_status")
        quality_status in ALLOWED_QUALITY_STATUSES ||
            fail("$location.quality_status is not recognized")
        validate_value(row.value, quality_status, "$location.value")

        unique_key = Tuple(row[column] for column in UNIQUE_OBSERVATION_KEY)
        unique_key in seen_keys &&
            fail("$location duplicates a bitemporal observation key")
        push!(seen_keys, unique_key)
    end
    return observations
end

function eligible_rows(
        observations::AbstractDataFrame,
        origin_timestamp_utc::DateTime,
        allowed_quality_statuses::Set{String},
    )
    all(
        status -> status in ALLOWED_QUALITY_STATUSES,
        allowed_quality_statuses,
    ) || fail("allowed_quality_statuses contains an unknown status")
    origin_date = Date(origin_timestamp_utc)
    pending_today = Set{Tuple}()
    for row in eachrow(observations)
        if Date(row.release_timestamp_utc) == origin_date &&
                row.release_timestamp_utc > origin_timestamp_utc
            push!(
                pending_today,
                Tuple(row[column] for column in SNAPSHOT_KEY),
            )
        end
    end
    interval_or_intraday_carry = [
        row.realtime_end >= origin_date ||
            (
                row.realtime_end + Day(1) == origin_date &&
                Tuple(row[column] for column in SNAPSHOT_KEY) in
                pending_today
            )
            for row in eachrow(observations)
    ]
    return observations[
        (observations.release_timestamp_utc .<= origin_timestamp_utc) .&
            (observations.realtime_start .<= origin_date) .&
            interval_or_intraday_carry .&
            in.(
            String.(observations.quality_status),
            Ref(allowed_quality_statuses),
        ),
        :,
    ]
end

function asof_snapshot(
        observations::AbstractDataFrame,
        origin_timestamp_utc::DateTime;
        allowed_quality_statuses = Set(["APPROVED"]),
        required_series = String[],
    )
    validate_observations(observations)
    statuses = Set(String.(collect(allowed_quality_statuses)))
    eligible =
        eligible_rows(observations, origin_timestamp_utc, statuses)

    selected_rows = Int[]
    if nrow(eligible) > 0
        grouped = groupby(eligible, collect(SNAPSHOT_KEY); sort = true)
        for group in grouped
            latest_release = maximum(group.release_timestamp_utc)
            candidates = findall(
                ==(latest_release),
                group.release_timestamp_utc,
            )
            length(candidates) == 1 ||
                fail(
                "ambiguous latest release for $(Tuple(group[1, column] for column in SNAPSHOT_KEY))",
            )
            push!(selected_rows, parentindices(group)[1][only(candidates)])
        end
    end
    snapshot = eligible[selected_rows, :]
    sort!(
        snapshot,
        [
            :series_id,
            :reference_period_start,
            :reference_period_end,
            :transformation_version,
        ],
    )

    required = Set(String.(required_series))
    available = Set(String.(snapshot.series_id))
    missing_series = sort!(collect(setdiff(required, available)))
    isempty(missing_series) ||
        fail(
        "origin $(origin_timestamp_utc) is missing required series: $(join(missing_series, ", "))",
    )
    all(snapshot.release_timestamp_utc .<= origin_timestamp_utc) ||
        fail("internal look-ahead check failed")
    return snapshot
end

function canonical_scalar(value)
    if ismissing(value)
        return "missing:"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa DateTime
        return "datetime:" *
            Dates.format(value, RFC3339_SECONDS_FORMAT) *
            "Z"
    elseif value isa Date
        return "date:" * string(value)
    elseif value isa AbstractFloat
        return "float:" * bitstring(Float64(value))
    elseif value isa Integer
        return "integer:" * string(value)
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    end
    return fail("cannot canonicalize value of type $(typeof(value))")
end

function canonical_row(row)
    fields = String[]
    for column in REQUIRED_COLUMNS
        encoded = canonical_scalar(row[column])
        push!(
            fields,
            "$(String(column)):$(ncodeunits(encoded)):$encoded",
        )
    end
    return join(fields, "|")
end

function origin_manifest(
        observations::AbstractDataFrame,
        origin_timestamp_utc::DateTime;
        allowed_quality_statuses = Set(["APPROVED"]),
        required_series = String[],
    )
    snapshot = asof_snapshot(
        observations,
        origin_timestamp_utc;
        allowed_quality_statuses,
        required_series,
    )
    canonical_rows = canonical_row.(eachrow(snapshot))
    row_sha256 = [bytes2hex(SHA.sha256(row)) for row in canonical_rows]
    canonical_snapshot = join(
        [
            "origin:" *
                Dates.format(
                origin_timestamp_utc,
                RFC3339_SECONDS_FORMAT,
            ) *
                "Z",
            ("row:" .* canonical_rows)...,
        ],
        "\n",
    )
    return (
        schema_version = "beforeit-us-origin-manifest.v1",
        origin_timestamp_utc =
            Dates.format(
            origin_timestamp_utc,
            RFC3339_SECONDS_FORMAT,
        ) * "Z",
        row_count = nrow(snapshot),
        series_ids = sort!(unique(String.(snapshot.series_id))),
        row_sha256,
        snapshot_sha256 = bytes2hex(
            SHA.sha256(canonical_snapshot),
        ),
        snapshot,
    )
end

end
