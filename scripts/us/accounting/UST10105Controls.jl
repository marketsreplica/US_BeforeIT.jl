module UST10105Controls

using CSV
using DataFrames
using Dates
using JSON
using SHA
using TOML

export APPROVED_SOURCE_SHA256,
    CONTROL_COLUMNS,
    CONTROL_SPECS,
    FIXTURE_SCHEMA,
    load_t10105_fixture,
    materialize_control_series,
    opening_control,
    parse_t10105_source,
    validate_t10105_frame,
    write_t10105_fixture

const FIXTURE_SCHEMA = "beforeit-us-t10105-quarterly-controls.v1"
const APPROVED_SOURCE_SHA256 =
    "a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574"
const APPROVED_SOURCE_BYTE_COUNT = 1_896_972
const APPROVED_SOURCE_METADATA_SHA256 =
    "3e8a0d6e91237e22ee2805ba2abbce6ee746085e395d443e991921a97bee06ba"
const FIRST_PERIOD = "1996Q4"
const LAST_PERIOD = "2026Q2"
const UNIT = "millions_current_usd_per_quarter"
const TRANSFORMATION =
    "BEA current-dollar seasonally adjusted annual-rate level divided by four exactly once"
const IDENTITY_TOLERANCE = 1.0

const CONTROL_SPECS = (
    (
        field = :nominal_gdp_quarterly,
        line_number = "1",
        series_code = "A191RC",
        description = "Gross domestic product",
    ),
    (
        field = :nominal_household_consumption_quarterly,
        line_number = "2",
        series_code = "DPCERC",
        description = "Personal consumption expenditures",
    ),
    (
        field = :nominal_gross_private_domestic_investment_quarterly,
        line_number = "7",
        series_code = "A006RC",
        description = "Gross private domestic investment",
    ),
    (
        field = :nominal_fixed_investment_quarterly,
        line_number = "8",
        series_code = "A007RC",
        description = "Fixed investment",
    ),
    (
        field = :nominal_inventory_investment_quarterly,
        line_number = "14",
        series_code = "A014RC",
        description = "Change in private inventories",
    ),
    (
        field = :nominal_exports_quarterly,
        line_number = "16",
        series_code = "B020RC",
        description = "Exports",
    ),
    (
        field = :nominal_imports_quarterly,
        line_number = "19",
        series_code = "B021RC",
        description = "Imports",
    ),
    (
        field =
            :nominal_government_consumption_and_investment_quarterly,
        line_number = "22",
        series_code = "A822RC",
        description =
            "Government consumption expenditures and gross investment",
    ),
)

const CONTROL_COLUMNS = (
    :period,
    (specification.field for specification in CONTROL_SPECS)...,
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function quarter_end(label::AbstractString)
    match_result = match(r"^([0-9]{4})Q([1-4])$", String(label))
    match_result === nothing &&
        throw(ArgumentError("invalid BEA quarter label $(repr(label))"))
    year = parse(Int, match_result.captures[1])
    quarter = parse(Int, match_result.captures[2])
    return lastdayofmonth(Date(year, 3 * quarter, 1))
end

function expected_periods()
    first_period = quarter_end(FIRST_PERIOD)
    last_period = quarter_end(LAST_PERIOD)
    periods = Date[]
    period = first_period
    while period <= last_period
        push!(periods, period)
        period = lastdayofmonth(firstdayofmonth(period + Month(3)))
    end
    return periods
end

function parse_bea_level(value)
    text = strip(String(value))
    isempty(text) &&
        throw(ArgumentError("BEA T10105 contains a blank required value"))
    negative = startswith(text, "(") && endswith(text, ")")
    negative && (text = text[2:(end - 1)])
    number = parse(Float64, replace(text, "," => ""))
    return negative ? -number : number
end

function validate_t10105_frame(
        frame::DataFrame;
        identity_tolerance::Real = IDENTITY_TOLERANCE,
    )
    Symbol.(names(frame)) == collect(CONTROL_COLUMNS) ||
        throw(
        ArgumentError(
            "T10105 fixture columns do not match the frozen control contract",
        ),
    )
    periods = expected_periods()
    frame.period == periods ||
        throw(
        ArgumentError(
            "T10105 fixture must contain the complete ordered " *
                "$(FIRST_PERIOD)–$(LAST_PERIOD) quarter axis",
        ),
    )
    nrow(frame) == length(periods) ||
        throw(ArgumentError("T10105 fixture row count is inconsistent"))

    tolerance = Float64(identity_tolerance)
    isfinite(tolerance) && tolerance >= 0 ||
        throw(ArgumentError("identity tolerance must be finite and nonnegative"))
    for specification in CONTROL_SPECS
        values = frame[!, specification.field]
        eltype(values) <: Real ||
            throw(
            ArgumentError(
                "T10105 control $(specification.field) is not numeric",
            ),
        )
        all(isfinite, values) ||
            throw(
            ArgumentError(
                "T10105 control $(specification.field) contains nonfinite values",
            ),
        )
        all(value -> isinteger(4 * value), values) ||
            throw(
            ArgumentError(
                "T10105 control $(specification.field) is not a whole-million SAAR value divided by four",
            ),
        )
        if specification.field !=
                :nominal_inventory_investment_quarterly
            all(>(0), values) ||
                throw(
                ArgumentError(
                    "T10105 control $(specification.field) must be positive",
                ),
            )
        end
    end
    inventory = frame.nominal_inventory_investment_quarterly
    any(<(0), inventory) && any(>(0), inventory) ||
        throw(
        ArgumentError(
            "T10105 signed inventory flow lost either its negative or positive observations",
        ),
    )

    investment_residual =
        frame.nominal_gross_private_domestic_investment_quarterly -
        frame.nominal_fixed_investment_quarterly -
        frame.nominal_inventory_investment_quarterly
    maximum(abs, investment_residual) <= tolerance ||
        throw(
        ArgumentError(
            "T10105 GPDI identity exceeds the source-rounding tolerance",
        ),
    )
    expenditure_residual =
        frame.nominal_gdp_quarterly -
        frame.nominal_household_consumption_quarterly -
        frame.nominal_gross_private_domestic_investment_quarterly -
        frame.nominal_exports_quarterly +
        frame.nominal_imports_quarterly -
        frame.nominal_government_consumption_and_investment_quarterly
    maximum(abs, expenditure_residual) <= tolerance ||
        throw(
        ArgumentError(
            "T10105 GDP expenditure identity exceeds the source-rounding tolerance",
        ),
    )
    return (;
        maximum_expenditure_residual = maximum(abs, expenditure_residual),
        maximum_investment_residual = maximum(abs, investment_residual),
    )
end

function parse_t10105_source(
        source_path::AbstractString;
        expected_sha256::AbstractString = APPROVED_SOURCE_SHA256,
    )
    source_bytes = read(source_path)
    actual_sha256 = sha256_hex(source_bytes)
    actual_sha256 == lowercase(String(expected_sha256)) ||
        throw(ArgumentError("archived T10105 source SHA-256 mismatch"))
    length(source_bytes) == APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("archived T10105 source byte count mismatch"))

    payload = JSON.parse(String(source_bytes))
    rows = try
        payload["BEAAPI"]["Results"]["Data"]
    catch
        throw(ArgumentError("archived T10105 source has an unsupported envelope"))
    end
    rows isa AbstractVector ||
        throw(ArgumentError("archived T10105 Data payload is not an array"))

    required_periods = expected_periods()
    required_labels = Set(
        string(year(period), "Q", quarterofyear(period))
            for period in required_periods
    )
    by_key = Dict{Tuple{String, String}, Float64}()
    for row in rows
        line_number = String(get(row, "LineNumber", ""))
        specification_index =
            findfirst(
            specification ->
            specification.line_number == line_number,
            CONTROL_SPECS,
        )
        specification_index === nothing && continue
        specification = CONTROL_SPECS[specification_index]
        period = String(get(row, "TimePeriod", ""))
        period in required_labels || continue
        String(get(row, "TableName", "")) == "T10105" ||
            throw(ArgumentError("required row has the wrong BEA table"))
        String(get(row, "SeriesCode", "")) ==
            specification.series_code ||
            throw(ArgumentError("required row has the wrong BEA series"))
        String(get(row, "LineDescription", "")) ==
            specification.description ||
            throw(
            ArgumentError(
                "required row has an unexpected BEA line description",
            ),
        )
        String(get(row, "CL_UNIT", "")) == "Level" ||
            throw(ArgumentError("required row is not a BEA level"))
        String(get(row, "UNIT_MULT", "")) == "6" ||
            throw(
            ArgumentError(
                "required row is not reported in millions of dollars",
            ),
        )
        key = (line_number, period)
        haskey(by_key, key) &&
            throw(ArgumentError("duplicate required T10105 observation"))
        by_key[key] = parse_bea_level(row["DataValue"]) / 4
    end

    frame = DataFrame(period = required_periods)
    for specification in CONTROL_SPECS
        frame[!, specification.field] = Float64[
            get(
                    by_key,
                    (
                        specification.line_number,
                        string(year(period), "Q", quarterofyear(period)),
                    ),
                ) do
                    throw(
                        ArgumentError(
                            "missing $(specification.field) for $period",
                        ),
                    )
            end
                for period in required_periods
        ]
    end
    validate_t10105_frame(frame)
    return frame
end

function validate_manifest(manifest, cells_path)
    get(manifest, "schema_version", "") == FIXTURE_SCHEMA ||
        throw(ArgumentError("unsupported T10105 fixture schema"))
    get(manifest, "economic_unit", "") == UNIT ||
        throw(ArgumentError("unsupported T10105 fixture unit"))
    get(manifest, "transformation", "") == TRANSFORMATION ||
        throw(ArgumentError("unsupported T10105 fixture transformation"))
    get(manifest, "period_start", "") == FIRST_PERIOD ||
        throw(ArgumentError("unexpected T10105 fixture start period"))
    get(manifest, "period_end", "") == LAST_PERIOD ||
        throw(ArgumentError("unexpected T10105 fixture end period"))
    Int(get(manifest, "period_count", -1)) == length(expected_periods()) ||
        throw(ArgumentError("unexpected T10105 fixture period count"))
    Float64(get(manifest, "identity_tolerance", NaN)) ==
        IDENTITY_TOLERANCE ||
        throw(ArgumentError("unexpected T10105 identity tolerance"))
    get(manifest, "fixture_sha256", "") == sha256_hex(read(cells_path)) ||
        throw(ArgumentError("T10105 fixture SHA-256 mismatch"))

    source = get(manifest, "source", Dict{String, Any}())
    get(source, "status", "") == "APPROVED_ARCHIVED" ||
        throw(ArgumentError("T10105 source is not approved and archived"))
    get(source, "table_id", "") == "T10105" ||
        throw(ArgumentError("T10105 fixture has the wrong source table"))
    get(source, "source_sha256", "") == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("T10105 fixture source SHA-256 mismatch"))
    Int(get(source, "source_byte_count", -1)) ==
        APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("T10105 fixture source byte count mismatch"))
    get(source, "source_metadata_sha256", "") ==
        APPROVED_SOURCE_METADATA_SHA256 ||
        throw(
        ArgumentError(
            "T10105 fixture source-metadata SHA-256 mismatch",
        ),
    )

    series = get(manifest, "series", Any[])
    length(series) == length(CONTROL_SPECS) ||
        throw(ArgumentError("T10105 fixture series count mismatch"))
    by_id = Dict(String(entry["id"]) => entry for entry in series)
    Set(keys(by_id)) == Set(String(spec.field) for spec in CONTROL_SPECS) ||
        throw(ArgumentError("T10105 fixture series identifiers mismatch"))
    for specification in CONTROL_SPECS
        entry = by_id[String(specification.field)]
        String(entry["line_number"]) == specification.line_number ||
            throw(ArgumentError("T10105 fixture line-number mismatch"))
        String(entry["series_code"]) == specification.series_code ||
            throw(ArgumentError("T10105 fixture series-code mismatch"))
        String(entry["description"]) == specification.description ||
            throw(ArgumentError("T10105 fixture description mismatch"))
    end
    return nothing
end

function load_t10105_fixture(directory::AbstractString)
    manifest_path = joinpath(directory, "manifest.toml")
    cells_path = joinpath(directory, "quarterly_controls.csv")
    isfile(manifest_path) ||
        throw(ArgumentError("missing T10105 fixture manifest"))
    isfile(cells_path) ||
        throw(ArgumentError("missing T10105 fixture controls"))
    manifest = TOML.parsefile(manifest_path)
    validate_manifest(manifest, cells_path)
    frame = CSV.read(cells_path, DataFrame; types = Dict(:period => Date))
    validation = validate_t10105_frame(
        frame;
        identity_tolerance = manifest["identity_tolerance"],
    )
    return (; frame, manifest, validation, manifest_path, cells_path)
end

function opening_control(frame::DataFrame, period::Date)
    rows = findall(==(period), frame.period)
    length(rows) == 1 ||
        throw(ArgumentError("opening period $period is absent or duplicated"))
    row = only(rows)
    return (;
        nominal_gdp = frame.nominal_gdp_quarterly[row],
        nominal_household_consumption =
            frame.nominal_household_consumption_quarterly[row],
        nominal_gross_private_domestic_investment =
            frame.nominal_gross_private_domestic_investment_quarterly[
            row,
        ],
        nominal_fixed_investment =
            frame.nominal_fixed_investment_quarterly[row],
        nominal_inventory_investment =
            frame.nominal_inventory_investment_quarterly[row],
        nominal_exports = frame.nominal_exports_quarterly[row],
        nominal_imports = frame.nominal_imports_quarterly[row],
        nominal_government_consumption_and_investment =
            frame.nominal_government_consumption_and_investment_quarterly[
            row,
        ],
    )
end

function materialize_control_series(
        frame::DataFrame,
        periods::AbstractVector{Date},
    )
    frame.period == collect(periods) ||
        throw(
        ArgumentError(
            "calibration and T10105 control quarter axes must match exactly",
        ),
    )
    return Dict{String, Vector{Float64}}(
        String(specification.field) =>
            Float64.(frame[!, specification.field])
            for specification in CONTROL_SPECS
    )
end

function write_t10105_fixture(
        source_path::AbstractString,
        metadata_path::AbstractString,
        output_directory::AbstractString,
    )
    frame = parse_t10105_source(source_path)
    sha256_hex(read(metadata_path)) ==
        APPROVED_SOURCE_METADATA_SHA256 ||
        throw(ArgumentError("T10105 sidecar file SHA-256 mismatch"))
    metadata = JSON.parsefile(metadata_path)
    get(metadata, "sha256", "") == APPROVED_SOURCE_SHA256 ||
        throw(ArgumentError("T10105 sidecar SHA-256 mismatch"))
    Int(get(metadata, "byte_count", -1)) ==
        APPROVED_SOURCE_BYTE_COUNT ||
        throw(ArgumentError("T10105 sidecar byte count mismatch"))
    get(metadata, "dataset", "") == "NIPA" ||
        throw(ArgumentError("T10105 sidecar dataset mismatch"))
    request = get(metadata, "request", Dict{String, Any}())
    get(request, "TableName", "") == "T10105" ||
        throw(ArgumentError("T10105 sidecar request table mismatch"))
    get(request, "Frequency", "") == "Q" ||
        throw(ArgumentError("T10105 sidecar request frequency mismatch"))

    mkpath(output_directory)
    cells_path = joinpath(output_directory, "quarterly_controls.csv")
    CSV.write(cells_path, frame)
    fixture_sha256 = sha256_hex(read(cells_path))
    diagnostics = validate_t10105_frame(frame)
    manifest = Dict{String, Any}(
        "schema_version" => FIXTURE_SCHEMA,
        "fixture_sha256" => fixture_sha256,
        "economic_unit" => UNIT,
        "transformation" => TRANSFORMATION,
        "period_start" => FIRST_PERIOD,
        "period_end" => LAST_PERIOD,
        "period_count" => nrow(frame),
        "identity_tolerance" => IDENTITY_TOLERANCE,
        "maximum_expenditure_residual" =>
            diagnostics.maximum_expenditure_residual,
        "maximum_investment_residual" =>
            diagnostics.maximum_investment_residual,
        "source" => Dict{String, Any}(
            "status" => "APPROVED_ARCHIVED",
            "source_agency" => "U.S. Bureau of Economic Analysis",
            "dataset" => "NIPA",
            "table_id" => "T10105",
            "request_id" => get(metadata, "request_id", ""),
            "retrieved_at" => get(metadata, "retrieved_at", ""),
            "source_sha256" => APPROVED_SOURCE_SHA256,
            "source_byte_count" => APPROVED_SOURCE_BYTE_COUNT,
            "source_metadata_sha256" =>
                APPROVED_SOURCE_METADATA_SHA256,
        ),
        "series" => [
            Dict{String, Any}(
                    "id" => String(specification.field),
                    "line_number" => specification.line_number,
                    "series_code" => specification.series_code,
                    "description" => specification.description,
                )
                for specification in CONTROL_SPECS
        ],
    )
    manifest_path = joinpath(output_directory, "manifest.toml")
    open(manifest_path, "w") do io
        TOML.print(io, manifest; sorted = true)
    end
    load_t10105_fixture(output_directory)
    return (; frame, manifest, cells_path, manifest_path)
end

end # module
