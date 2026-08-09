if !isdefined(@__MODULE__, :USOriginDataReceipt)
    include(joinpath(@__DIR__, "USOriginDataReceipt.jl"))
end

module USBenchmarkOriginAdapter

    using Dates
    using ..USOriginDataReceipt:
        AuthenticatedOriginData,
        OriginDataReceipt,
        OriginDataReceiptError,
        SourceArtifact,
        authenticate_origin_data,
        validate_origin_data_receipt

    export AdapterValidationError,
        AuthenticatedOriginData,
        ForecastCell,
        ModelMetadata,
        OriginDataReceipt,
        OriginReadiness,
        ProductMetadata,
        RegisteredTarget,
        SourceArtifact,
        authenticate_origin_data,
        map_benchmark_run,
        run_benchmark_origin

    const FORECAST_SCHEMA_VERSION = "beforeit-us-forecast-record.v3"
    const BENCHMARK_INTERFACE_VERSION = "0.1.0"
    const ZERO_HASH = repeat("0", 64)
    const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
    const DATE_FORMAT = dateformat"yyyy-mm-dd"
    const CANONICAL_TRACKS = ("common_information", "published_forecast")
    const MIXED_VINTAGE_TRACK = "revised_mixed_vintage_diagnostic"
    const REGISTRY_ONLY_PUBLISHED_ALIAS = "published_information"
    const HERMETIC_EXECUTION_CLASS =
        "hermetic_validation_only_no_empirical_forecasts"
    const SYNTHETIC_ORIGIN_EVIDENCE = "synthetic_fixture_only"

    # This scaffold intentionally supports only the model registry's unconditional
    # quarterly slice. Other protocol products need sealed ragged-edge or
    # conditioning-assumption artifacts before this adapter may admit them.
    const PRODUCT_POLICIES = Dict(
        "quarterly_unconditional" => (
            kind = "unconditional_forecast",
            conditioning = "none",
            realized_future_data_allowed = false,
            horizons = (1, 2, 4, 8, 12),
            tracks = CANONICAL_TRACKS,
        ),
    )

    """
    Raised before a benchmark is run or a registry payload is returned whenever an
    adapter invariant is absent, ambiguous, or inconsistent.
    """
    struct AdapterValidationError <: Exception
        message::String
    end

    Base.showerror(io::IO, error::AdapterValidationError) =
        print(io, error.message)

    fail(location, message) =
        throw(AdapterValidationError("$location: $message"))

    function expect_string(value, location)
        value isa AbstractString || fail(location, "must be a string")
        text = String(value)
        text == strip(text) || fail(location, "has surrounding whitespace")
        isempty(text) && fail(location, "must not be empty")
        return text
    end

    function expect_identifier(value, location)
        text = expect_string(value, location)
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$", text) ||
            fail(location, "contains unsupported characters")
        return text
    end

    function expect_hash(value, location)
        text = expect_string(value, location)
        occursin(r"^[0-9a-f]{64}$", text) ||
            fail(location, "must be 64 lowercase hexadecimal characters")
        text == ZERO_HASH &&
            fail(location, "must not be the all-zero placeholder hash")
        return text
    end

    function parse_timestamp(value, location)
        text = expect_string(value, location)
        occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", text) ||
            fail(location, "must be RFC3339 UTC at second precision")
        parsed = try
            DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
        catch
            fail(location, "is not a valid timestamp")
        end
        return text, parsed
    end

    function expect_date(value, location)
        text = expect_string(value, location)
        occursin(r"^\d{4}-\d{2}-\d{2}$", text) ||
            fail(location, "must be an ISO date")
        parsed = try
            Date(text, DATE_FORMAT)
        catch
            fail(location, "is not a valid date")
        end
        return text, parsed
    end

    function expect_integer(value, location; minimum = 0)
        value isa Integer && !(value isa Bool) ||
            fail(location, "must be an integer")
        result = try
            Int(value)
        catch
            fail(location, "does not fit in Int")
        end
        result >= minimum ||
            fail(location, "must be at least $minimum")
        return result
    end

    function expect_track(value, location)
        track = expect_string(value, location)
        if track == REGISTRY_ONLY_PUBLISHED_ALIAS
            fail(
                location,
                "published_information is rejected; the protocol-canonical track is published_forecast",
            )
        elseif track == MIXED_VINTAGE_TRACK
            fail(
                location,
                "the revised/current mixed-vintage diagnostic track is not runnable",
            )
        end
        track in CANONICAL_TRACKS ||
            fail(
            location,
            "must be common_information or published_forecast",
        )
        return track
    end

    """
        OriginReadiness(; ...)

    An explicit origin identity and readiness handoff. The adapter deliberately
    does not import or invoke the origin package module. This scaffold executes
    only synthetic-fixture evidence and requires an authenticated `OriginData`
    integrity receipt. A future empirical integration must also run the full
    origin-package validator and add a trusted semantic-derivation receipt.
    """
    struct OriginReadiness
        origin_id::String
        origin_kind::String
        origin_timestamp_utc::String
        origin_manifest_sha256::String
        protocol_sha256::String
        information_track::String
        evidence_class::String
        status::String

        function OriginReadiness(
                origin_id,
                origin_kind,
                origin_timestamp_utc,
                origin_manifest_sha256,
                protocol_sha256,
                information_track,
                evidence_class,
                status,
            )
            id = expect_identifier(origin_id, "origin.origin_id")
            kind = expect_identifier(origin_kind, "origin.origin_kind")
            timestamp, _ =
                parse_timestamp(origin_timestamp_utc, "origin.origin_timestamp_utc")
            manifest_hash =
                expect_hash(origin_manifest_sha256, "origin.origin_manifest_sha256")
            protocol_hash =
                expect_hash(protocol_sha256, "origin.protocol_sha256")
            track = expect_track(information_track, "origin.information_track")
            evidence = expect_identifier(evidence_class, "origin.evidence_class")
            readiness = expect_identifier(status, "origin.status")

            readiness == "ready" ||
                fail("origin.status", "must be the explicit validated value ready")
            kind == "current_diagnostic" &&
                fail(
                "origin.origin_kind",
                "tracked current diagnostics are not runnable forecast origins",
            )
            kind in ("retrospective", "prospective") ||
                fail(
                "origin.origin_kind",
                "must be retrospective or prospective",
            )
            evidence == "diagnostic_only_no_promotion" &&
                fail(
                "origin.evidence_class",
                "diagnostic-only origin evidence cannot enter the runner",
            )

            return new(
                id,
                kind,
                timestamp,
                manifest_hash,
                protocol_hash,
                track,
                evidence,
                readiness,
            )
        end
    end

    OriginReadiness(;
        origin_id,
        origin_kind,
        origin_timestamp_utc,
        origin_manifest_sha256,
        protocol_sha256,
        information_track,
        evidence_class,
        status,
    ) = OriginReadiness(
        origin_id,
        origin_kind,
        origin_timestamp_utc,
        origin_manifest_sha256,
        protocol_sha256,
        information_track,
        evidence_class,
        status,
    )

    """
    Product metadata copied from the frozen protocol for one attempted run. The
    requested horizons may be a strict subset of the product's protocol horizons,
    but must be ordered and unique.
    """
    struct ProductMetadata
        product_id::String
        kind::String
        conditioning::String
        realized_future_data_allowed::Bool
        information_track::String
        horizons::Tuple{Vararg{Int}}

        function ProductMetadata(
                product_id,
                kind,
                conditioning,
                realized_future_data_allowed,
                information_track,
                horizons,
            )
            id = expect_identifier(product_id, "product.product_id")
            haskey(PRODUCT_POLICIES, id) ||
                fail("product.product_id", "is not in the frozen protocol")
            policy = PRODUCT_POLICIES[id]
            product_kind = expect_identifier(kind, "product.kind")
            product_kind == policy.kind ||
                fail(
                "product.kind",
                "does not match protocol product $id",
            )
            conditioning_rule =
                expect_identifier(conditioning, "product.conditioning")
            conditioning_rule == policy.conditioning ||
                fail(
                "product.conditioning",
                "does not match protocol product $id",
            )
            realized_future_data_allowed isa Bool ||
                fail(
                "product.realized_future_data_allowed",
                "must be Bool",
            )
            realized_future_data_allowed ==
                policy.realized_future_data_allowed ||
                fail(
                "product.realized_future_data_allowed",
                "does not match protocol product $id",
            )
            track = expect_track(information_track, "product.information_track")
            track in policy.tracks ||
                fail(
                "product.information_track",
                "is not allowed for protocol product $id",
            )
            horizons isa AbstractVector ||
                fail("product.horizons", "must be a vector")
            selected = Int[
                expect_integer(value, "product.horizons[$index]")
                    for (index, value) in enumerate(horizons)
            ]
            isempty(selected) &&
                fail("product.horizons", "must not be empty")
            issorted(selected) ||
                fail("product.horizons", "must be strictly increasing")
            allunique(selected) ||
                fail("product.horizons", "must not contain duplicates")
            all(horizon -> horizon in policy.horizons, selected) ||
                fail(
                "product.horizons",
                "contains a horizon outside the frozen protocol product",
            )
            return new(
                id,
                product_kind,
                conditioning_rule,
                realized_future_data_allowed,
                track,
                tuple(selected...),
            )
        end
    end

    ProductMetadata(;
        product_id,
        kind,
        conditioning,
        realized_future_data_allowed,
        information_track,
        horizons,
    ) = ProductMetadata(
        product_id,
        kind,
        conditioning,
        realized_future_data_allowed,
        information_track,
        horizons,
    )

    """One registry-derived target-panel row used to bind runtime cells."""
    struct RegisteredTarget
        target_id::String
        target_operator_version::String
        transformation_version::String

        function RegisteredTarget(
                target_id,
                target_operator_version,
                transformation_version,
            )
            return new(
                expect_identifier(target_id, "registered_target.target_id"),
                expect_identifier(
                    target_operator_version,
                    "registered_target.target_operator_version",
                ),
                expect_identifier(
                    transformation_version,
                    "registered_target.transformation_version",
                ),
            )
        end
    end

    RegisteredTarget(;
        target_id,
        target_operator_version,
        transformation_version,
    ) = RegisteredTarget(
        target_id,
        target_operator_version,
        transformation_version,
    )

    """
    Hash- and policy-addressed model-registry handoff. A caller must construct this
    from one validated model entry, its resolved target panel and model-card
    artifact, and the registry's validated execution scope. No concrete registry
    module is imported, avoiding an integration cycle.
    """
    struct ModelMetadata
        model_id::String
        model_manifest_sha256::String
        model_card_sha256::String
        registry_content_sha256::String
        target_contract_sha256::String
        registry_status::String
        support_status::String
        information_track::String
        product_ids::Tuple{Vararg{String}}
        target_panel_id::String
        targets::Tuple{Vararg{RegisteredTarget}}
        execution_class::String
        empirical_forecast_execution_allowed::Bool
        production_scoring_allowed::Bool

        function ModelMetadata(
                model_id,
                model_manifest_sha256,
                model_card_sha256,
                registry_content_sha256,
                target_contract_sha256,
                registry_status,
                support_status,
                information_track,
                product_ids,
                target_panel_id,
                targets,
                execution_class,
                empirical_forecast_execution_allowed,
                production_scoring_allowed,
            )
            id = expect_identifier(model_id, "model.model_id")
            manifest_hash = expect_hash(
                model_manifest_sha256,
                "model.model_manifest_sha256",
            )
            card_hash =
                expect_hash(model_card_sha256, "model.model_card_sha256")
            registry_hash = expect_hash(
                registry_content_sha256,
                "model.registry_content_sha256",
            )
            target_contract_hash = expect_hash(
                target_contract_sha256,
                "model.target_contract_sha256",
            )
            registry_state =
                expect_identifier(registry_status, "model.registry_status")
            registry_state == "frozen_implementation_only" ||
                fail(
                "model.registry_status",
                "must be frozen_implementation_only for this scaffold",
            )
            support =
                expect_identifier(support_status, "model.support_status")
            support == "supported" ||
                fail("model.support_status", "must be supported")
            track = expect_track(information_track, "model.information_track")

            product_ids isa Union{AbstractVector, Tuple} ||
                fail("model.product_ids", "must be a vector or tuple")
            products = String[
                expect_identifier(product, "model.product_ids[$index]")
                    for (index, product) in enumerate(product_ids)
            ]
            isempty(products) &&
                fail("model.product_ids", "must not be empty")
            allunique(products) ||
                fail("model.product_ids", "must be unique")
            for (index, product) in enumerate(products)
                haskey(PRODUCT_POLICIES, product) ||
                    fail(
                    "model.product_ids[$index]",
                    "is unsupported by this scaffold",
                )
                track in PRODUCT_POLICIES[product].tracks ||
                    fail(
                    "model.information_track",
                    "is not allowed for registered product $product",
                )
            end

            panel =
                expect_identifier(target_panel_id, "model.target_panel_id")
            targets isa Union{AbstractVector, Tuple} ||
                fail("model.targets", "must be a vector or tuple")
            target_rows = RegisteredTarget[]
            for (index, target) in enumerate(targets)
                target isa RegisteredTarget ||
                    fail(
                    "model.targets[$index]",
                    "must be a RegisteredTarget",
                )
                push!(target_rows, target)
            end
            isempty(target_rows) &&
                fail("model.targets", "must not be empty")
            allunique(target.target_id for target in target_rows) ||
                fail("model.targets", "must have unique target IDs")

            scope =
                expect_identifier(execution_class, "model.execution_class")
            scope == HERMETIC_EXECUTION_CLASS ||
                fail(
                "model.execution_class",
                "must retain the hermetic-only registry scope",
            )
            empirical_forecast_execution_allowed isa Bool ||
                fail(
                "model.empirical_forecast_execution_allowed",
                "must be Bool",
            )
            empirical_forecast_execution_allowed &&
                fail(
                "model.empirical_forecast_execution_allowed",
                "must remain false",
            )
            production_scoring_allowed isa Bool ||
                fail("model.production_scoring_allowed", "must be Bool")
            production_scoring_allowed &&
                fail(
                "model.production_scoring_allowed",
                "must remain false",
            )

            return new(
                id,
                manifest_hash,
                card_hash,
                registry_hash,
                target_contract_hash,
                registry_state,
                support,
                track,
                tuple(products...),
                panel,
                tuple(target_rows...),
                scope,
                empirical_forecast_execution_allowed,
                production_scoring_allowed,
            )
        end
    end

    ModelMetadata(;
        model_id,
        model_manifest_sha256,
        model_card_sha256,
        registry_content_sha256,
        target_contract_sha256,
        registry_status,
        support_status,
        information_track,
        product_ids,
        target_panel_id,
        targets,
        execution_class,
        empirical_forecast_execution_allowed,
        production_scoring_allowed,
    ) = ModelMetadata(
        model_id,
        model_manifest_sha256,
        model_card_sha256,
        registry_content_sha256,
        target_contract_sha256,
        registry_status,
        support_status,
        information_track,
        product_ids,
        target_panel_id,
        targets,
        execution_class,
        empirical_forecast_execution_allowed,
        production_scoring_allowed,
    )

    """
    One target/horizon registry cell. `output_index` is the one-based row in the
    benchmark forecast matrix, and `forecast_key` must equal the corresponding key
    in `OriginData`. This quarterly-only scaffold requires
    `output_index == horizon`.
    """
    struct ForecastCell{T}
        forecast_id::String
        target_name::String
        target_id::String
        target_operator_version::String
        transformation_version::String
        horizon::Int
        output_index::Int
        forecast_key::T
        target_period_start::String
        target_period_end::String
        truth_key::String

        function ForecastCell(
                forecast_id,
                target_name,
                target_id,
                target_operator_version,
                transformation_version,
                horizon,
                output_index,
                forecast_key::T,
                target_period_start,
                target_period_end,
                truth_key,
            ) where {T}
            forecast_identifier =
                expect_identifier(forecast_id, "cell.forecast_id")
            benchmark_target = expect_string(target_name, "cell.target_name")
            target_identifier = expect_identifier(target_id, "cell.target_id")
            operator_version = expect_identifier(
                target_operator_version,
                "cell.target_operator_version",
            )
            transformation = expect_identifier(
                transformation_version,
                "cell.transformation_version",
            )
            horizon_value =
                expect_integer(horizon, "cell.horizon"; minimum = 1)
            output_row =
                expect_integer(output_index, "cell.output_index"; minimum = 1)
            output_row == horizon_value ||
                fail(
                "cell.output_index",
                "must equal horizon in this quarterly scaffold",
            )
            period_start, start_date =
                expect_date(target_period_start, "cell.target_period_start")
            period_end, end_date =
                expect_date(target_period_end, "cell.target_period_end")
            start_date <= end_date ||
                fail("cell.target_period_end", "precedes target_period_start")
            truth_identifier = expect_identifier(truth_key, "cell.truth_key")
            return new{T}(
                forecast_identifier,
                benchmark_target,
                target_identifier,
                operator_version,
                transformation,
                horizon_value,
                output_row,
                forecast_key,
                period_start,
                period_end,
                truth_identifier,
            )
        end
    end

    ForecastCell(;
        forecast_id,
        target_name,
        target_id,
        target_operator_version,
        transformation_version,
        horizon,
        output_index,
        forecast_key,
        target_period_start,
        target_period_end,
        truth_key,
    ) = ForecastCell(
        forecast_id,
        target_name,
        target_id,
        target_operator_version,
        transformation_version,
        horizon,
        output_index,
        forecast_key,
        target_period_start,
        target_period_end,
        truth_key,
    )

    function required_property(value, property, location)
        hasproperty(value, property) ||
            fail(location, "is missing property $property")
        return getproperty(value, property)
    end

    function required_mapping_value(value, key, location)
        value isa AbstractDict ||
            fail(location, "must be a dictionary")
        if haskey(value, key)
            return value[key]
        elseif key isa Symbol && haskey(value, String(key))
            return value[String(key)]
        end
        return fail(location, "is missing key $key")
    end

    function validate_authenticated_copy(sample, authenticated_origin_data)
        authenticated_origin_data isa AuthenticatedOriginData ||
            fail(
            "authenticated_origin_data",
            "must be an AuthenticatedOriginData from USOriginDataReceipt",
        )
        owned_sample = deepcopy(sample)
        validation = try
            validate_origin_data_receipt(
                authenticated_origin_data;
                sample = owned_sample,
            )
        catch error
            error isa OriginDataReceiptError || rethrow()
            fail(
                "authenticated_origin_data",
                sprint(showerror, error),
            )
        end
        return owned_sample, validation
    end

    function revalidate_authenticated_sample(
            sample,
            authenticated_origin_data,
            location,
        )
        try
            return validate_origin_data_receipt(
                authenticated_origin_data;
                sample,
            )
        catch error
            error isa OriginDataReceiptError || rethrow()
            fail(location, sprint(showerror, error))
        end
    end

    function validate_receipt_binding(
            authenticated_origin_data,
            origin,
            model,
        )
        receipt = authenticated_origin_data.receipt
        receipt.origin_manifest_sha256 == origin.origin_manifest_sha256 ||
            fail(
            "authenticated_origin_data.receipt.origin_manifest_sha256",
            "does not match OriginReadiness",
        )
        receipt.protocol_sha256 == origin.protocol_sha256 ||
            fail(
            "authenticated_origin_data.receipt.protocol_sha256",
            "does not match OriginReadiness",
        )
        receipt.model_registry_content_sha256 ==
            model.registry_content_sha256 ||
            fail(
            "authenticated_origin_data.receipt.model_registry_content_sha256",
            "does not match ModelMetadata",
        )
        receipt.target_contract_sha256 == model.target_contract_sha256 ||
            fail(
            "authenticated_origin_data.receipt.target_contract_sha256",
            "does not match ModelMetadata",
        )
        receipt.target_panel_id == model.target_panel_id ||
            fail(
            "authenticated_origin_data.receipt.target_panel_id",
            "does not match ModelMetadata",
        )
        receipt.evidence_class == origin.evidence_class ||
            fail(
            "authenticated_origin_data.receipt.evidence_class",
            "does not match OriginReadiness",
        )
        receipt.empirical_execution_authorized ==
            model.empirical_forecast_execution_allowed ||
            fail(
            "authenticated_origin_data.receipt.empirical_execution_authorized",
            "does not match ModelMetadata",
        )
        receipt.empirical_execution_authorized &&
            fail(
            "authenticated_origin_data.receipt.empirical_execution_authorized",
            "must remain false",
        )
        return nothing
    end

    function validate_sample(sample)
        origin_id = required_property(sample, :origin_id, "sample")
        origin_key = required_property(sample, :origin_key, "sample")
        forecast_keys = required_property(sample, :forecast_keys, "sample")
        target_names = required_property(sample, :target_names, "sample")
        required_property(sample, :x_future, "sample")
        origin_id isa AbstractString ||
            fail("sample.origin_id", "must be a string")
        forecast_keys isa AbstractVector ||
            fail("sample.forecast_keys", "must be a vector")
        isempty(forecast_keys) &&
            fail("sample.forecast_keys", "must not be empty")
        target_names isa AbstractVector ||
            fail("sample.target_names", "must be a vector")
        isempty(target_names) &&
            fail("sample.target_names", "must not be empty")
        names = String[
            expect_string(name, "sample.target_names[$index]")
                for (index, name) in enumerate(target_names)
        ]
        allunique(names) ||
            fail("sample.target_names", "must be unique")
        return (;
            origin_id = String(origin_id),
            origin_key,
            forecast_keys,
            target_names = names,
        )
    end

    function validate_cells(cells, sample_metadata, product)
        cells isa AbstractVector ||
            fail("cells", "must be a vector")
        isempty(cells) && fail("cells", "must not be empty")
        all(cell -> cell isa ForecastCell, cells) ||
            fail("cells", "must contain only ForecastCell values")

        forecast_ids = [cell.forecast_id for cell in cells]
        allunique(forecast_ids) ||
            fail("cells.forecast_id", "must be unique")
        truth_keys = [cell.truth_key for cell in cells]
        allunique(truth_keys) ||
            fail("cells.truth_key", "must be unique within one model run")

        expected_targets = Set(sample_metadata.target_names)
        actual_targets = Set(cell.target_name for cell in cells)
        actual_targets == expected_targets ||
            fail(
            "cells.target_name",
            "must cover every sample target and no others",
        )

        target_identity = Dict{String, Tuple{String, String, String}}()
        horizon_rows = Dict{Int, Tuple{Int, Any, String, String}}()
        semantic_cells = Set{Tuple{String, Int}}()
        for (index, cell) in enumerate(cells)
            cell.horizon in product.horizons ||
                fail(
                "cells[$index].horizon",
                "is not requested by the product metadata",
            )
            cell.output_index <= length(sample_metadata.forecast_keys) ||
                fail(
                "cells[$index].output_index",
                "exceeds the benchmark forecast horizon",
            )
            sample_metadata.forecast_keys[cell.output_index] ==
                cell.forecast_key ||
                fail(
                "cells[$index].forecast_key",
                "does not match sample.forecast_keys at output_index",
            )

            identity = (
                cell.target_id,
                cell.target_operator_version,
                cell.transformation_version,
            )
            if haskey(target_identity, cell.target_name)
                target_identity[cell.target_name] == identity ||
                    fail(
                    "cells[$index]",
                    "changes target/operator/transformation metadata across horizons",
                )
            else
                target_identity[cell.target_name] = identity
            end

            semantic = (cell.target_name, cell.horizon)
            semantic in semantic_cells &&
                fail(
                "cells[$index]",
                "duplicates target/horizon metadata",
            )
            push!(semantic_cells, semantic)

            row_binding = (
                cell.output_index,
                cell.forecast_key,
                cell.target_period_start,
                cell.target_period_end,
            )
            if haskey(horizon_rows, cell.horizon)
                horizon_rows[cell.horizon] == row_binding ||
                    fail(
                    "cells[$index]",
                    "changes output row, forecast key, or target period within a horizon",
                )
            else
                horizon_rows[cell.horizon] = row_binding
            end
        end
        target_ids = [identity[1] for identity in values(target_identity)]
        allunique(target_ids) ||
            fail(
            "cells.target_id",
            "must map one-to-one to benchmark target names",
        )

        expected_horizons = Set(product.horizons)
        for target_name in sample_metadata.target_names
            target_horizons = Set(
                cell.horizon
                    for cell in cells if cell.target_name == target_name
            )
            target_horizons == expected_horizons ||
                fail(
                "cells.$target_name",
                "must cover every requested horizon exactly once",
            )
        end
        return nothing
    end

    function validate_model_binding(model, product, cells, sample_metadata)
        model.information_track == product.information_track ||
            fail(
            "model.information_track",
            "does not match the selected product track",
        )
        product.product_id in model.product_ids ||
            fail(
            "model.product_ids",
            "does not admit selected product $(product.product_id)",
        )
        registered_target_ids =
            [target.target_id for target in model.targets]
        sample_metadata.target_names == registered_target_ids ||
            fail(
            "sample.target_names",
            "does not exactly match the registered target panel order",
        )
        registered_targets =
            Dict(target.target_id => target for target in model.targets)
        for (index, cell) in enumerate(cells)
            registered = registered_targets[cell.target_name]
            cell.target_id == registered.target_id ||
                fail(
                "cells[$index].target_id",
                "does not match the registered target panel",
            )
            cell.target_operator_version ==
                registered.target_operator_version ||
                fail(
                "cells[$index].target_operator_version",
                "does not match the registered target panel",
            )
            cell.transformation_version ==
                registered.transformation_version ||
                fail(
                "cells[$index].transformation_version",
                "does not match the registered target panel",
            )
        end
        return nothing
    end

    function validate_context(
            sample;
            authenticated_origin_data,
            receipt_validation,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
        )
        origin isa OriginReadiness ||
            fail("origin", "must be an OriginReadiness")
        product isa ProductMetadata ||
            fail("product", "must be a ProductMetadata")
        model isa ModelMetadata ||
            fail("model", "must be a ModelMetadata")
        validate_receipt_binding(
            authenticated_origin_data,
            origin,
            model,
        )
        experiment =
            expect_identifier(experiment_id, "run.experiment_id")
        protocol_hash =
            expect_hash(protocol_sha256, "run.protocol_sha256")
        protocol_hash == origin.protocol_sha256 ||
            fail(
            "run.protocol_sha256",
            "does not match the validated origin",
        )
        registered_text, registered =
            parse_timestamp(
            execution_registered_at_utc,
            "run.execution_registered_at_utc",
        )
        _, origin_timestamp =
            parse_timestamp(origin.origin_timestamp_utc, "origin.origin_timestamp_utc")
        registered >= origin_timestamp ||
            fail(
            "run.execution_registered_at_utc",
            "must not predate the forecast origin",
        )
        origin.information_track == product.information_track ||
            fail(
            "product.information_track",
            "does not match the validated origin track",
        )
        origin.evidence_class == SYNTHETIC_ORIGIN_EVIDENCE ||
            fail(
            "origin.evidence_class",
            "this hermetic scaffold admits only synthetic fixtures",
        )

        sample_metadata = validate_sample(sample)
        sample_metadata.origin_id == origin.origin_id ||
            fail(
            "sample.origin_id",
            "does not match the validated origin",
        )
        if product.kind == "unconditional_forecast" &&
                required_property(sample, :x_future, "sample") !== nothing
            fail(
                "sample.x_future",
                "must be nothing for the unconditional product",
            )
        end
        validate_cells(cells, sample_metadata, product)
        validate_model_binding(model, product, cells, sample_metadata)

        return (
            experiment_id = experiment,
            protocol_sha256 = protocol_hash,
            execution_registered_at_utc = registered_text,
            master_seed =
                expect_integer(master_seed, "run.master_seed"),
            path_id = expect_integer(path_id, "run.path_id"),
            n_draws = expect_integer(n_draws, "run.n_draws"),
            origin_data_sample_sha256 =
                receipt_validation.sample_sha256,
            origin_data_receipt_sha256 =
                receipt_validation.receipt_sha256,
            sample = sample_metadata,
        )
    end

    function derive_seed(seed_deriver, context, origin, model)
        record = seed_deriver(
            context.master_seed;
            experiment_id = context.experiment_id,
            origin_manifest_sha256 = origin.origin_manifest_sha256,
            model_id = model.model_id,
            path_id = context.path_id,
            purpose = "forecast",
        )
        seed = expect_integer(
            required_property(record, :seed, "seed_record"),
            "seed_record.seed",
        )
        key_hash = expect_hash(
            required_property(
                record,
                :seed_key_sha256,
                "seed_record",
            ),
            "seed_record.seed_key_sha256",
        )
        namespace =
            required_property(record, :namespace, "seed_record")
        expected_namespace = Dict{String, Any}(
            "schema_version" => "beforeit-us-rng-substream.v1",
            "master_seed" => context.master_seed,
            "experiment_id" => context.experiment_id,
            "origin_manifest_sha256" => origin.origin_manifest_sha256,
            "model_id" => model.model_id,
            "path_id" => context.path_id,
            "purpose" => "forecast",
        )
        for (key, expected) in expected_namespace
            required_mapping_value(namespace, key, "seed_record.namespace") ==
                expected ||
                fail(
                "seed_record.namespace.$key",
                "does not match the requested registry namespace",
            )
        end
        length(namespace) == length(expected_namespace) ||
            fail(
            "seed_record.namespace",
            "contains unexpected namespace fields",
        )
        return (; seed, seed_key_sha256 = key_hash, namespace)
    end

    function validate_success_run(
            run,
            context,
            origin,
            model,
            derived_seed,
        )
        required_property(run, :failure, "benchmark_run") === nothing ||
            fail("benchmark_run.failure", "must be nothing on success")
        forecast =
            required_property(run, :forecast, "benchmark_run")
        forecast === nothing &&
            fail("benchmark_run.forecast", "must be present on success")
        required_property(
            forecast,
            :interface_version,
            "benchmark_run.forecast",
        ) == BENCHMARK_INTERFACE_VERSION ||
            fail(
            "benchmark_run.forecast.interface_version",
            "is unsupported by this adapter",
        )
        required_property(forecast, :model_id, "benchmark_run.forecast") ==
            model.model_id ||
            fail(
            "benchmark_run.forecast.model_id",
            "does not match the registered model",
        )
        required_property(forecast, :origin_id, "benchmark_run.forecast") ==
            origin.origin_id ||
            fail(
            "benchmark_run.forecast.origin_id",
            "does not match the validated origin",
        )
        required_property(forecast, :origin_key, "benchmark_run.forecast") ==
            context.sample.origin_key ||
            fail(
            "benchmark_run.forecast.origin_key",
            "does not match the supplied origin data",
        )
        required_property(
            forecast,
            :forecast_keys,
            "benchmark_run.forecast",
        ) == context.sample.forecast_keys ||
            fail(
            "benchmark_run.forecast.forecast_keys",
            "does not match the supplied origin data",
        )
        String.(
            required_property(
                forecast,
                :target_names,
                "benchmark_run.forecast",
            ),
        ) == context.sample.target_names ||
            fail(
            "benchmark_run.forecast.target_names",
            "does not match the supplied origin data",
        )

        point = required_property(forecast, :point, "benchmark_run.forecast")
        draws = required_property(forecast, :draws, "benchmark_run.forecast")
        expected_shape = (
            length(context.sample.forecast_keys),
            length(context.sample.target_names),
        )
        size(point) == expected_shape ||
            fail(
            "benchmark_run.forecast.point",
            "has shape $(size(point)); expected $expected_shape",
        )
        expected_draw_shape = (expected_shape..., context.n_draws)
        size(draws) == expected_draw_shape ||
            fail(
            "benchmark_run.forecast.draws",
            "has shape $(size(draws)); expected $expected_draw_shape",
        )
        diagnostics =
            required_property(forecast, :diagnostics, "benchmark_run.forecast")
        diagnostics isa AbstractDict ||
            fail("benchmark_run.forecast.diagnostics", "must be a dictionary")
        required_mapping_value(
            diagnostics,
            "seed",
            "benchmark_run.forecast.diagnostics",
        ) == derived_seed ||
            fail(
            "benchmark_run.forecast.diagnostics.seed",
            "does not match the registry-derived seed",
        )
        required_mapping_value(
            diagnostics,
            "n_draws",
            "benchmark_run.forecast.diagnostics",
        ) == context.n_draws ||
            fail(
            "benchmark_run.forecast.diagnostics.n_draws",
            "does not match the attempted draw count",
        )
        return forecast
    end

    function validate_run(run, context, origin, model, derived_seed)
        status = required_property(run, :status, "benchmark_run")
        status in (:ok, :failed) ||
            fail("benchmark_run.status", "must be :ok or :failed")
        required_property(run, :model_id, "benchmark_run") == model.model_id ||
            fail(
            "benchmark_run.model_id",
            "does not match the registered model",
        )
        required_property(run, :origin_id, "benchmark_run") == origin.origin_id ||
            fail(
            "benchmark_run.origin_id",
            "does not match the validated origin",
        )
        if status == :ok
            return validate_success_run(
                run,
                context,
                origin,
                model,
                derived_seed,
            )
        end
        required_property(run, :forecast, "benchmark_run") === nothing ||
            fail("benchmark_run.forecast", "must be nothing on failure")
        required_property(run, :failure, "benchmark_run") === nothing &&
            fail("benchmark_run.failure", "must be present on failure")
        return nothing
    end

    function distribution_hash(
            forecast,
            n_draws,
            distribution_hash_provider,
        )
        n_draws == 0 && return nothing
        distribution_hash_provider === nothing &&
            fail(
            "distribution_hash_provider",
            "is required for a successful density forecast",
        )
        return expect_hash(
            distribution_hash_provider(forecast),
            "distribution_artifact_sha256",
        )
    end

    function forecast_payload(
            cell,
            point,
            distribution_artifact_sha256,
            registry_draws,
            failure_code,
            context,
            origin,
            product,
            model,
            seed_record,
        )
        return Dict{String, Any}(
            "schema_version" => FORECAST_SCHEMA_VERSION,
            "experiment_id" => context.experiment_id,
            "forecast_id" => cell.forecast_id,
            "execution_registered_at_utc" =>
                context.execution_registered_at_utc,
            "origin_id" => origin.origin_id,
            "origin_timestamp_utc" => origin.origin_timestamp_utc,
            "origin_manifest_sha256" => origin.origin_manifest_sha256,
            "origin_data_sample_sha256" =>
                context.origin_data_sample_sha256,
            "origin_data_receipt_sha256" =>
                context.origin_data_receipt_sha256,
            "protocol_sha256" => context.protocol_sha256,
            "model_id" => model.model_id,
            "model_manifest_sha256" => model.model_manifest_sha256,
            "model_card_sha256" => model.model_card_sha256,
            "product_id" => product.product_id,
            "information_track" => product.information_track,
            "target_id" => cell.target_id,
            "target_operator_version" => cell.target_operator_version,
            "transformation_version" => cell.transformation_version,
            "horizon" => cell.horizon,
            "target_period_start" => cell.target_period_start,
            "target_period_end" => cell.target_period_end,
            "truth_key" => cell.truth_key,
            "status" => failure_code === nothing ? "success" : "failed",
            "point_forecast" => point,
            "distribution_artifact_sha256" =>
                distribution_artifact_sha256,
            "n_draws" => registry_draws,
            "seed" => seed_record.seed,
            "seed_key_sha256" => seed_record.seed_key_sha256,
            "failure_code" => failure_code,
        )
    end

    function registry_records(
            run,
            context,
            origin,
            product,
            model,
            cells,
            seed_record,
            distribution_hash_provider,
        )
        forecast = validate_run(
            run,
            context,
            origin,
            model,
            seed_record.seed,
        )
        target_columns = Dict(
            target_name => index
                for (index, target_name) in
                enumerate(context.sample.target_names)
        )

        if run.status == :ok
            artifact_hash = distribution_hash(
                forecast,
                context.n_draws,
                distribution_hash_provider,
            )
            records = Dict{String, Any}[]
            for cell in cells
                point = forecast.point[
                    cell.output_index,
                    target_columns[cell.target_name],
                ]
                point isa Real && isfinite(point) ||
                    fail(
                    "benchmark_run.forecast.point",
                    "contains a nonfinite registry cell",
                )
                push!(
                    records,
                    forecast_payload(
                        cell,
                        Float64(point),
                        artifact_hash,
                        context.n_draws,
                        nothing,
                        context,
                        origin,
                        product,
                        model,
                        seed_record,
                    ),
                )
            end
            return records
        end

        failure = required_property(run, :failure, "benchmark_run")
        code = expect_identifier(
            String(required_property(failure, :code, "benchmark_run.failure")),
            "benchmark_run.failure.code",
        )
        return Dict{String, Any}[
            forecast_payload(
                    cell,
                    nothing,
                    nothing,
                    0,
                    code,
                    context,
                    origin,
                    product,
                    model,
                    seed_record,
                ) for cell in cells
        ]
    end

    function prepare(
            sample;
            authenticated_origin_data,
            receipt_validation,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
            seed_deriver,
        )
        context = validate_context(
            sample;
            authenticated_origin_data,
            receipt_validation,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
        )
        seed_record = derive_seed(seed_deriver, context, origin, model)
        return context, seed_record
    end

    """
        map_benchmark_run(run, sample; ...)

    Validate and expand an already-computed `BenchmarkRun` into exact v3 forecast
    payloads. The caller injects `USForecastRegistry.derive_seed_record`; a
    successful density run additionally injects a function that returns the hash
    of the externally materialized draw artifact. This module never writes that
    artifact and never accepts truth values. Because this path does not invoke the
    benchmark runner, it cannot prove how the precomputed run was produced; its
    guarantee is hermetic mapping integrity only.
    """
    function map_benchmark_run(
            run,
            sample;
            authenticated_origin_data,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
            seed_deriver,
            distribution_hash_provider = nothing,
        )
        validated_sample, receipt_validation =
            validate_authenticated_copy(
            sample,
            authenticated_origin_data,
        )
        context, seed_record = prepare(
            validated_sample;
            authenticated_origin_data,
            receipt_validation,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
            seed_deriver,
        )
        records = registry_records(
            run,
            context,
            origin,
            product,
            model,
            cells,
            seed_record,
            distribution_hash_provider,
        )
        return (
            context,
            seed_record,
            benchmark_run = run,
            forecast_records = records,
        )
    end

    """
        run_benchmark_origin(spec, sample; ...)

    Fail-closed orchestration seam for `USForecastBenchmarks.run_benchmark`. Both
    the benchmark runner and model-id resolver are injected to avoid importing the
    benchmark or in-progress model registry. All metadata and the registry seed are
    validated before the runner is called. The concrete authenticated receipt is
    checked against an owned sample copy before execution and again after return.
    """
    function run_benchmark_origin(
            spec,
            sample;
            authenticated_origin_data,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
            seed_deriver,
            benchmark_model_id,
            benchmark_runner,
            distribution_hash_provider = nothing,
        )
        validated_sample, receipt_validation =
            validate_authenticated_copy(
            sample,
            authenticated_origin_data,
        )
        context, seed_record = prepare(
            validated_sample;
            authenticated_origin_data,
            receipt_validation,
            origin,
            product,
            model,
            cells,
            experiment_id,
            protocol_sha256,
            execution_registered_at_utc,
            master_seed,
            path_id,
            n_draws,
            seed_deriver,
        )
        resolved_model_id =
            expect_identifier(benchmark_model_id(spec), "benchmark_spec.model_id")
        resolved_model_id == model.model_id ||
            fail(
            "benchmark_spec.model_id",
            "does not match the hash-addressed model registration",
        )
        run = benchmark_runner(
            spec,
            validated_sample;
            n_draws = context.n_draws,
            seed = seed_record.seed,
        )
        revalidate_authenticated_sample(
            validated_sample,
            authenticated_origin_data,
            "benchmark_runner.sample",
        )
        records = registry_records(
            run,
            context,
            origin,
            product,
            model,
            cells,
            seed_record,
            distribution_hash_provider,
        )
        return (
            context,
            seed_record,
            benchmark_run = run,
            forecast_records = records,
        )
    end

end
