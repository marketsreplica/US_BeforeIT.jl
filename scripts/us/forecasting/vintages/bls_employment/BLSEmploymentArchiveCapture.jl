module BLSEmploymentArchiveCapture

using Dates
using SHA
using TOML

export ArchiveExpectation,
    BLSEmploymentCaptureError,
    BLSEmploymentCaptureReceipt,
    JANUARY_2020_EXPECTATION,
    import_browser_download,
    receipt_file_sha256,
    receipt_sha256,
    validate_browser_download,
    validate_receipt,
    validate_receipt_file

const SCHEMA_VERSION =
    "beforeit-us-bls-employment-archive-browser-capture.v1"
const CANONICALIZATION =
    "ordered-field-name-type-length-prefixed-utf8.v1"
const DIGEST_ALGORITHM = "sha256"
const RECEIPT_DOMAIN =
    "beforeit-us-bls-employment-archive-receipt-self-hash.v1"
const SOURCE_AGENCY = "U.S. Bureau of Labor Statistics"
const PUBLICATION_NAME = "Employment Situation"
const COPYRIGHT_LOCATOR =
    "https://www.bls.gov/opub/copyright-information.htm"
const API_TERMS_LOCATOR =
    "https://www.bls.gov/developers/termsOfService.htm"
const PUBLIC_DOMAIN_STATUS =
    "PUBLIC_DOMAIN_EXCEPT_PREVIOUSLY_COPYRIGHTED_PHOTOGRAPHS_AND_ILLUSTRATIONS"
const SOURCE_ATTRIBUTION = "Source: U.S. Bureau of Labor Statistics"
const FILE_SPECIFIC_IMAGE_REVIEW_STATUS =
    "NOT_COMPLETED_CAPTURE_ONLY_REVIEW_REQUIRED_BEFORE_REDISTRIBUTION"
const API_TERMS_APPLICABILITY =
    "NOT_APPLICABLE_DIRECT_ARCHIVE_PDF_BROWSER_DOWNLOAD_NO_API"
const CAPTURE_METHOD = "LOCAL_BROWSER_DOWNLOAD_IMPORT"
const BROWSER_OBSERVATION_BASIS =
    "OPERATOR_ASSERTED_LOCAL_FILE_PRESENT_AFTER_BROWSER_DOWNLOAD"
const UNKNOWN_RELEASE_TIME = "NOT_EXTRACTED_NOT_VERIFIED"
const UNKNOWN_RELEASE_TIMESTAMP = "UNKNOWN_NOT_INFERRED"
const LIVE_ARCHIVE_DOCUMENT_STATE =
    "REISSUED_CORRECTED_NOT_HISTORICAL_FIRST_STATE"
const LIVE_PDF_DECLARED_EVIDENCE_BASIS =
    "MANUAL_PDF_INSPECTION_PINNED_BY_EXACT_RAW_SHA256"
const LIVE_PDF_METADATA_CREATION_DATE =
    "D:20200106100753-05'00'"
const LIVE_PDF_METADATA_MODIFICATION_DATE =
    "D:20200220142443-05'00'"
const LIVE_PDF_DECLARED_REISSUE_DATE = "2020-02-21"
const LIVE_PDF_DECLARED_CORRECTION_SCOPE =
    "REISSUED_TO_CORRECT_TABLE_A-5"
const LIVE_DIAGNOSTIC_PAYROLL_CHANGE_THOUSANDS = 145
const LIVE_DIAGNOSTIC_UNEMPLOYMENT_RATE_PERCENT = "3.5"
const LIVE_DIAGNOSTIC_HEADLINE_VALUES_STATUS =
    "PDF_DECLARED_DIAGNOSTIC_ONLY_NOT_SEMANTIC_IMPORT"
const SYNTHETIC_DOCUMENT_LITERAL =
    "NOT_APPLICABLE_SYNTHETIC_FIXTURE"
const STORAGE_MODE = "CONTENT_ADDRESSED_IMMUTABLE_OBJECTS"
const STORAGE_ENCODING = "identity"
const PDF_SIGNATURE = "%PDF-"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[a-z0-9][a-z0-9._-]*$"
const SOURCE_URL_PATTERN =
    r"^https://www\.bls\.gov/news\.release/archives/empsit_[0-9]{8}\.pdf$"
const RFC3339_SECONDS_PATTERN =
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const DATE_PATTERN = r"^\d{4}-\d{2}-\d{2}$"
const MAX_PDF_BYTES = 5_000_000

struct BLSEmploymentCaptureError <: Exception
    message::String
end

Base.showerror(io::IO, error::BLSEmploymentCaptureError) =
    print(io, error.message)

fail(location, message) =
    throw(BLSEmploymentCaptureError("$location: $message"))

"""
Pinned identity for one official BLS Employment Situation archive PDF.

The expectation is caller-independent evidence: import succeeds only when the
local bytes exactly match its official URL, release ID, byte count, SHA-256,
and PDF signature.
"""
struct ArchiveExpectation
    release_id::String
    reference_period::String
    source_url::String
    expected_raw_sha256::String
    expected_byte_count::Int
end

const JANUARY_2020_EXPECTATION = ArchiveExpectation(
    "bls_empsit_01102020",
    "2019-12",
    "https://www.bls.gov/news.release/archives/empsit_01102020.pdf",
    "e9005e394f25ad62315817fcada7bfff102442290a995a13417f82f027ceb066",
    356_586,
)

"""
Immutable present-day capture receipt.

All fields are scalar and therefore deeply immutable. `receipt_sha256` is a
domain-separated self-hash over every field except itself. The false gates are
part of that preimage and cannot be promoted by this capture contract.
"""
struct BLSEmploymentCaptureReceipt
    schema_version::String
    receipt_id::String
    canonicalization::String
    digest_algorithm::String
    immutable_receipt::Bool
    receipt_sha256::String
    source_agency::String
    publication_name::String
    release_id::String
    reference_period::String
    source_url::String
    expected_raw_sha256::String
    expected_byte_count::Int
    observed_raw_sha256::String
    observed_byte_count::Int
    pdf_signature::String
    archive_document_state::String
    pdf_declared_evidence_basis::String
    pdf_metadata_creation_date::String
    pdf_metadata_modification_date::String
    pdf_declared_reissue_date::String
    pdf_declared_correction_scope::String
    diagnostic_payroll_change_thousands::Int
    diagnostic_unemployment_rate_percent::String
    diagnostic_headline_values_status::String
    raw_object_relative_path::String
    storage_mode::String
    storage_encoding::String
    capture_method::String
    browser_download_observed_at_utc::String
    browser_observation_basis::String
    import_started_at_utc::String
    import_completed_at_utc::String
    import_local_date::String
    release_stated_embargo_time::String
    release_stated_public_time::String
    release_event_timestamp_utc::String
    release_time_inferred_from_browser_capture::Bool
    browser_retrieval_is_release_event_evidence::Bool
    copyright_terms_locator::String
    api_terms_locator::String
    terms_reviewed_local_date::String
    public_domain_status::String
    source_attribution::String
    file_specific_image_review_required::Bool
    file_specific_image_review_status::String
    api_terms_applicability::String
    bls_emblem_reuse_authorized::Bool
    redistribution_authorized::Bool
    historical_first_state_verified::Bool
    historical_availability_verified::Bool
    origin_admissible::Bool
    empirical_execution_allowed::Bool
    inventory_mutation_authorized::Bool
    ready::Bool
end

const RECEIPT_SECTIONS = Set(
    [
        "artifact",
        "source",
        "document_evidence",
        "storage",
        "capture",
        "release_time_boundary",
        "terms",
        "gates",
    ],
)
const DOCUMENT_EVIDENCE_KEYS = Set(
    [
        "archive_document_state",
        "pdf_declared_evidence_basis",
        "pdf_metadata_creation_date",
        "pdf_metadata_modification_date",
        "pdf_declared_reissue_date",
        "pdf_declared_correction_scope",
        "diagnostic_payroll_change_thousands",
        "diagnostic_unemployment_rate_percent",
        "diagnostic_headline_values_status",
    ],
)
const ARTIFACT_KEYS = Set(
    [
        "schema_version",
        "receipt_id",
        "canonicalization",
        "digest_algorithm",
        "immutable_receipt",
        "receipt_sha256",
    ],
)
const SOURCE_KEYS = Set(
    [
        "source_agency",
        "publication_name",
        "release_id",
        "reference_period",
        "source_url",
        "expected_raw_sha256",
        "expected_byte_count",
        "observed_raw_sha256",
        "observed_byte_count",
        "pdf_signature",
    ],
)
const STORAGE_KEYS = Set(
    [
        "raw_object_relative_path",
        "storage_mode",
        "storage_encoding",
    ],
)
const CAPTURE_KEYS = Set(
    [
        "capture_method",
        "browser_download_observed_at_utc",
        "browser_observation_basis",
        "import_started_at_utc",
        "import_completed_at_utc",
        "import_local_date",
    ],
)
const RELEASE_TIME_KEYS = Set(
    [
        "release_stated_embargo_time",
        "release_stated_public_time",
        "release_event_timestamp_utc",
        "release_time_inferred_from_browser_capture",
        "browser_retrieval_is_release_event_evidence",
    ],
)
const TERMS_KEYS = Set(
    [
        "copyright_terms_locator",
        "api_terms_locator",
        "terms_reviewed_local_date",
        "public_domain_status",
        "source_attribution",
        "file_specific_image_review_required",
        "file_specific_image_review_status",
        "api_terms_applicability",
        "bls_emblem_reuse_authorized",
        "redistribution_authorized",
    ],
)
const GATE_KEYS = Set(
    [
        "historical_first_state_verified",
        "historical_availability_verified",
        "origin_admissible",
        "empirical_execution_allowed",
        "inventory_mutation_authorized",
        "ready",
    ],
)

sha256_hex(bytes::AbstractVector{UInt8}) = bytes2hex(SHA.sha256(bytes))

function _expect_hash(value, location)
    value isa String || fail(location, "must be a string")
    occursin(HASH_PATTERN, value) ||
        fail(location, "must be a lowercase SHA-256")
    return value
end

function _expect_nonempty_string(value, location)
    value isa String || fail(location, "must be a string")
    isempty(value) && fail(location, "must not be empty")
    occursin('\0', value) && fail(location, "must not contain NUL")
    return value
end

function _parse_timestamp(value, location)
    text = _expect_nonempty_string(value, location)
    occursin(RFC3339_SECONDS_PATTERN, text) ||
        fail(location, "must be canonical RFC3339 UTC seconds")
    return try
        DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch error
        fail(location, "is invalid ($(sprint(showerror, error)))")
    end
end

function _parse_date(value, location)
    text = _expect_nonempty_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must be a canonical ISO date")
    return try
        Date(text)
    catch error
        fail(location, "is invalid ($(sprint(showerror, error)))")
    end
end

_timestamp(value::DateTime) =
    Dates.format(value, RFC3339_SECONDS_FORMAT) * "Z"

function _validate_expectation(expectation::ArchiveExpectation)
    occursin(IDENTIFIER_PATTERN, expectation.release_id) ||
        fail(
        "expectation.release_id",
        "must be a lowercase canonical identifier",
    )
    occursin(r"^[0-9]{4}-[0-9]{2}$", expectation.reference_period) ||
        fail(
        "expectation.reference_period",
        "must be a canonical YYYY-MM period",
    )
    occursin(SOURCE_URL_PATTERN, expectation.source_url) ||
        fail(
        "expectation.source_url",
        "must be an exact official BLS Employment Situation archive PDF URL",
    )
    archive_stem = splitext(basename(expectation.source_url))[1]
    expectation.release_id == "bls_$archive_stem" ||
        fail(
        "expectation.release_id",
        "must be derived exactly from the archive filename",
    )
    _expect_hash(
        expectation.expected_raw_sha256,
        "expectation.expected_raw_sha256",
    )
    0 < expectation.expected_byte_count <= MAX_PDF_BYTES ||
        fail(
        "expectation.expected_byte_count",
        "must be within the PDF byte limit",
    )
    return expectation
end

function _is_live_expectation(expectation)
    return expectation.release_id == JANUARY_2020_EXPECTATION.release_id &&
        expectation.reference_period ==
        JANUARY_2020_EXPECTATION.reference_period &&
        expectation.source_url == JANUARY_2020_EXPECTATION.source_url &&
        expectation.expected_raw_sha256 ==
        JANUARY_2020_EXPECTATION.expected_raw_sha256 &&
        expectation.expected_byte_count ==
        JANUARY_2020_EXPECTATION.expected_byte_count
end

function _document_evidence(expectation)
    if _is_live_expectation(expectation)
        return (
            archive_document_state = LIVE_ARCHIVE_DOCUMENT_STATE,
            pdf_declared_evidence_basis =
                LIVE_PDF_DECLARED_EVIDENCE_BASIS,
            pdf_metadata_creation_date =
                LIVE_PDF_METADATA_CREATION_DATE,
            pdf_metadata_modification_date =
                LIVE_PDF_METADATA_MODIFICATION_DATE,
            pdf_declared_reissue_date =
                LIVE_PDF_DECLARED_REISSUE_DATE,
            pdf_declared_correction_scope =
                LIVE_PDF_DECLARED_CORRECTION_SCOPE,
            diagnostic_payroll_change_thousands =
                LIVE_DIAGNOSTIC_PAYROLL_CHANGE_THOUSANDS,
            diagnostic_unemployment_rate_percent =
                LIVE_DIAGNOSTIC_UNEMPLOYMENT_RATE_PERCENT,
            diagnostic_headline_values_status =
                LIVE_DIAGNOSTIC_HEADLINE_VALUES_STATUS,
        )
    end
    return (
        archive_document_state =
            "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE",
        pdf_declared_evidence_basis = SYNTHETIC_DOCUMENT_LITERAL,
        pdf_metadata_creation_date = SYNTHETIC_DOCUMENT_LITERAL,
        pdf_metadata_modification_date = SYNTHETIC_DOCUMENT_LITERAL,
        pdf_declared_reissue_date = SYNTHETIC_DOCUMENT_LITERAL,
        pdf_declared_correction_scope = SYNTHETIC_DOCUMENT_LITERAL,
        diagnostic_payroll_change_thousands = 0,
        diagnostic_unemployment_rate_percent =
            SYNTHETIC_DOCUMENT_LITERAL,
        diagnostic_headline_values_status =
            "SYNTHETIC_FIXTURE_NO_SOURCE_SEMANTICS",
    )
end

function _has_pdf_signature(bytes)
    length(bytes) >= 8 || return false
    bytes[1:5] == Vector{UInt8}(codeunits(PDF_SIGNATURE)) ||
        return false
    bytes[6] == UInt8('1') || return false
    bytes[7] == UInt8('.') || return false
    UInt8('0') <= bytes[8] <= UInt8('9') || return false
    return true
end

function _has_pdf_eof(bytes)
    isempty(bytes) && return false
    last_nonwhitespace = findlast(
        byte -> !(byte in UInt8[0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20]),
        bytes,
    )
    last_nonwhitespace === nothing && return false
    marker = Vector{UInt8}(codeunits("%%EOF"))
    last_nonwhitespace >= length(marker) || return false
    start = last_nonwhitespace - length(marker) + 1
    return bytes[start:last_nonwhitespace] == marker
end

"""
    validate_browser_download(bytes, expectation)

Validate exact byte count, SHA-256, PDF header, and terminal PDF marker without
parsing or inferring publication semantics.
"""
function validate_browser_download(
        bytes::AbstractVector{UInt8},
        expectation::ArchiveExpectation,
    )
    _validate_expectation(expectation)
    raw = Vector{UInt8}(bytes)
    length(raw) == expectation.expected_byte_count ||
        fail(
        "browser_download.byte_count",
        "expected $(expectation.expected_byte_count), found $(length(raw))",
    )
    _has_pdf_signature(raw) ||
        fail(
        "browser_download.pdf_signature",
        "must begin with a canonical PDF-1.x signature",
    )
    _has_pdf_eof(raw) ||
        fail(
        "browser_download.pdf_eof",
        "must end with the PDF %%EOF marker",
    )
    digest = sha256_hex(raw)
    digest == expectation.expected_raw_sha256 ||
        fail(
        "browser_download.sha256",
        "expected $(expectation.expected_raw_sha256), found $digest",
    )
    return (
        raw_bytes = raw,
        raw_sha256 = digest,
        raw_byte_count = length(raw),
        pdf_signature = PDF_SIGNATURE,
    )
end

function _write_u64(io, value::Integer)
    value >= 0 || fail("canonicalization", "length must be nonnegative")
    number = UInt64(value)
    for shift in 56:-8:0
        write(io, UInt8((number >> shift) & 0xff))
    end
    return nothing
end

function _write_blob(io, bytes::AbstractVector{UInt8})
    _write_u64(io, length(bytes))
    write(io, bytes)
    return nothing
end

_string_bytes(value) = Vector{UInt8}(codeunits(String(value)))

function _write_scalar(io, value)
    if value isa String
        write(io, UInt8('s'))
        _write_blob(io, _string_bytes(value))
    elseif value isa Bool
        write(io, UInt8('b'))
        _write_blob(io, UInt8[value ? 0x01 : 0x00])
    elseif value isa Int
        write(io, UInt8('i'))
        _write_blob(io, _string_bytes(string(value)))
    else
        fail(
            "canonicalization",
            "unsupported receipt field type $(typeof(value))",
        )
    end
    return nothing
end

function _receipt_preimage(receipt::BLSEmploymentCaptureReceipt)
    io = IOBuffer()
    _write_blob(io, _string_bytes(RECEIPT_DOMAIN))
    for name in fieldnames(BLSEmploymentCaptureReceipt)
        name == :receipt_sha256 && continue
        _write_blob(io, _string_bytes(String(name)))
        _write_scalar(io, getfield(receipt, name))
    end
    return take!(io)
end

receipt_sha256(receipt::BLSEmploymentCaptureReceipt) =
    sha256_hex(_receipt_preimage(receipt))

function _receipt_with_hash(
        receipt::BLSEmploymentCaptureReceipt,
        digest::String,
    )
    values = Any[
        name == :receipt_sha256 ? digest : getfield(receipt, name) for
            name in fieldnames(BLSEmploymentCaptureReceipt)
    ]
    return BLSEmploymentCaptureReceipt(values...)
end

function _raw_relative_path(raw_sha256)
    return joinpath(
        "bls",
        "employment_situation",
        "archive",
        "objects",
        "sha256-$raw_sha256",
        "raw-sha256-$raw_sha256.pdf",
    )
end

function _build_receipt(
        expectation,
        validation;
        terms_reviewed_local_date,
        browser_download_observed_at_utc,
        import_started_at_utc,
        import_completed_at_utc,
        import_local_date,
    )
    identifier_time = replace(
        _timestamp(browser_download_observed_at_utc),
        ":" => "",
        "-" => "",
    )
    receipt_id =
        "$(expectation.release_id)-browser-$identifier_time.v1"
    document_evidence = _document_evidence(expectation)
    unsealed = BLSEmploymentCaptureReceipt(
        SCHEMA_VERSION,
        lowercase(receipt_id),
        CANONICALIZATION,
        DIGEST_ALGORITHM,
        true,
        repeat("0", 64),
        SOURCE_AGENCY,
        PUBLICATION_NAME,
        expectation.release_id,
        expectation.reference_period,
        expectation.source_url,
        expectation.expected_raw_sha256,
        expectation.expected_byte_count,
        validation.raw_sha256,
        validation.raw_byte_count,
        validation.pdf_signature,
        document_evidence.archive_document_state,
        document_evidence.pdf_declared_evidence_basis,
        document_evidence.pdf_metadata_creation_date,
        document_evidence.pdf_metadata_modification_date,
        document_evidence.pdf_declared_reissue_date,
        document_evidence.pdf_declared_correction_scope,
        document_evidence.diagnostic_payroll_change_thousands,
        document_evidence.diagnostic_unemployment_rate_percent,
        document_evidence.diagnostic_headline_values_status,
        _raw_relative_path(validation.raw_sha256),
        STORAGE_MODE,
        STORAGE_ENCODING,
        CAPTURE_METHOD,
        _timestamp(browser_download_observed_at_utc),
        BROWSER_OBSERVATION_BASIS,
        _timestamp(import_started_at_utc),
        _timestamp(import_completed_at_utc),
        string(import_local_date),
        UNKNOWN_RELEASE_TIME,
        UNKNOWN_RELEASE_TIME,
        UNKNOWN_RELEASE_TIMESTAMP,
        false,
        false,
        COPYRIGHT_LOCATOR,
        API_TERMS_LOCATOR,
        string(terms_reviewed_local_date),
        PUBLIC_DOMAIN_STATUS,
        SOURCE_ATTRIBUTION,
        true,
        FILE_SPECIFIC_IMAGE_REVIEW_STATUS,
        API_TERMS_APPLICABILITY,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
    )
    return _receipt_with_hash(unsealed, receipt_sha256(unsealed))
end

function _require_fixed(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), found $(repr(value))")
    return value
end

function validate_receipt(receipt::BLSEmploymentCaptureReceipt)
    _require_fixed(
        receipt.schema_version,
        SCHEMA_VERSION,
        "receipt.schema_version",
    )
    occursin(IDENTIFIER_PATTERN, receipt.receipt_id) ||
        fail("receipt.receipt_id", "must be a canonical identifier")
    _require_fixed(
        receipt.canonicalization,
        CANONICALIZATION,
        "receipt.canonicalization",
    )
    _require_fixed(
        receipt.digest_algorithm,
        DIGEST_ALGORITHM,
        "receipt.digest_algorithm",
    )
    _require_fixed(
        receipt.immutable_receipt,
        true,
        "receipt.immutable_receipt",
    )
    _expect_hash(receipt.receipt_sha256, "receipt.receipt_sha256")
    _require_fixed(
        receipt.source_agency,
        SOURCE_AGENCY,
        "receipt.source_agency",
    )
    _require_fixed(
        receipt.publication_name,
        PUBLICATION_NAME,
        "receipt.publication_name",
    )

    expectation = ArchiveExpectation(
        receipt.release_id,
        receipt.reference_period,
        receipt.source_url,
        receipt.expected_raw_sha256,
        receipt.expected_byte_count,
    )
    _validate_expectation(expectation)
    _expect_hash(
        receipt.observed_raw_sha256,
        "receipt.observed_raw_sha256",
    )
    _require_fixed(
        receipt.observed_raw_sha256,
        receipt.expected_raw_sha256,
        "receipt.observed_raw_sha256",
    )
    _require_fixed(
        receipt.observed_byte_count,
        receipt.expected_byte_count,
        "receipt.observed_byte_count",
    )
    _require_fixed(
        receipt.pdf_signature,
        PDF_SIGNATURE,
        "receipt.pdf_signature",
    )
    document_evidence = _document_evidence(expectation)
    for field in (
            :archive_document_state,
            :pdf_declared_evidence_basis,
            :pdf_metadata_creation_date,
            :pdf_metadata_modification_date,
            :pdf_declared_reissue_date,
            :pdf_declared_correction_scope,
            :diagnostic_payroll_change_thousands,
            :diagnostic_unemployment_rate_percent,
            :diagnostic_headline_values_status,
        )
        _require_fixed(
            getfield(receipt, field),
            getfield(document_evidence, field),
            "receipt.$field",
        )
    end
    _require_fixed(
        receipt.raw_object_relative_path,
        _raw_relative_path(receipt.observed_raw_sha256),
        "receipt.raw_object_relative_path",
    )
    isabspath(receipt.raw_object_relative_path) &&
        fail(
        "receipt.raw_object_relative_path",
        "must be relative to the supplied raw root",
    )
    ".." in splitpath(receipt.raw_object_relative_path) &&
        fail(
        "receipt.raw_object_relative_path",
        "must not contain parent traversal",
    )
    _require_fixed(
        receipt.storage_mode,
        STORAGE_MODE,
        "receipt.storage_mode",
    )
    _require_fixed(
        receipt.storage_encoding,
        STORAGE_ENCODING,
        "receipt.storage_encoding",
    )
    _require_fixed(
        receipt.capture_method,
        CAPTURE_METHOD,
        "receipt.capture_method",
    )
    _require_fixed(
        receipt.browser_observation_basis,
        BROWSER_OBSERVATION_BASIS,
        "receipt.browser_observation_basis",
    )
    browser_time = _parse_timestamp(
        receipt.browser_download_observed_at_utc,
        "receipt.browser_download_observed_at_utc",
    )
    import_start = _parse_timestamp(
        receipt.import_started_at_utc,
        "receipt.import_started_at_utc",
    )
    import_complete = _parse_timestamp(
        receipt.import_completed_at_utc,
        "receipt.import_completed_at_utc",
    )
    browser_time <= import_start <= import_complete ||
        fail(
        "receipt.capture_timestamps",
        "browser observation and import timestamps must be ordered",
    )
    import_date =
        _parse_date(receipt.import_local_date, "receipt.import_local_date")
    review_date = _parse_date(
        receipt.terms_reviewed_local_date,
        "receipt.terms_reviewed_local_date",
    )
    review_date == import_date ||
        fail(
        "receipt.terms_reviewed_local_date",
        "must equal the import host-local date",
    )

    for (field, expected) in (
            (
                :release_stated_embargo_time,
                UNKNOWN_RELEASE_TIME,
            ),
            (
                :release_stated_public_time,
                UNKNOWN_RELEASE_TIME,
            ),
            (
                :release_event_timestamp_utc,
                UNKNOWN_RELEASE_TIMESTAMP,
            ),
            (
                :release_time_inferred_from_browser_capture,
                false,
            ),
            (
                :browser_retrieval_is_release_event_evidence,
                false,
            ),
            (:copyright_terms_locator, COPYRIGHT_LOCATOR),
            (:api_terms_locator, API_TERMS_LOCATOR),
            (:public_domain_status, PUBLIC_DOMAIN_STATUS),
            (:source_attribution, SOURCE_ATTRIBUTION),
            (:file_specific_image_review_required, true),
            (
                :file_specific_image_review_status,
                FILE_SPECIFIC_IMAGE_REVIEW_STATUS,
            ),
            (:api_terms_applicability, API_TERMS_APPLICABILITY),
            (:bls_emblem_reuse_authorized, false),
            (:redistribution_authorized, false),
            (:historical_first_state_verified, false),
            (:historical_availability_verified, false),
            (:origin_admissible, false),
            (:empirical_execution_allowed, false),
            (:inventory_mutation_authorized, false),
            (:ready, false),
        )
        _require_fixed(
            getfield(receipt, field),
            expected,
            "receipt.$field",
        )
    end

    computed = receipt_sha256(receipt)
    receipt.receipt_sha256 == computed ||
        fail(
        "receipt.receipt_sha256",
        "self-hash mismatch: computed $computed",
    )
    return (
        receipt_sha256 = computed,
        raw_sha256 = receipt.observed_raw_sha256,
        raw_byte_count = receipt.observed_byte_count,
        terms_reviewed_local_date = review_date,
        historical_first_state_verified = false,
        historical_availability_verified = false,
        origin_admissible = false,
        empirical_execution_allowed = false,
        inventory_mutation_authorized = false,
        ready = false,
    )
end

function _receipt_document(receipt)
    validate_receipt(receipt)
    return Dict(
        "artifact" => Dict(
            "schema_version" => receipt.schema_version,
            "receipt_id" => receipt.receipt_id,
            "canonicalization" => receipt.canonicalization,
            "digest_algorithm" => receipt.digest_algorithm,
            "immutable_receipt" => receipt.immutable_receipt,
            "receipt_sha256" => receipt.receipt_sha256,
        ),
        "source" => Dict(
            "source_agency" => receipt.source_agency,
            "publication_name" => receipt.publication_name,
            "release_id" => receipt.release_id,
            "reference_period" => receipt.reference_period,
            "source_url" => receipt.source_url,
            "expected_raw_sha256" => receipt.expected_raw_sha256,
            "expected_byte_count" => receipt.expected_byte_count,
            "observed_raw_sha256" => receipt.observed_raw_sha256,
            "observed_byte_count" => receipt.observed_byte_count,
            "pdf_signature" => receipt.pdf_signature,
        ),
        "document_evidence" => Dict(
            "archive_document_state" =>
                receipt.archive_document_state,
            "pdf_declared_evidence_basis" =>
                receipt.pdf_declared_evidence_basis,
            "pdf_metadata_creation_date" =>
                receipt.pdf_metadata_creation_date,
            "pdf_metadata_modification_date" =>
                receipt.pdf_metadata_modification_date,
            "pdf_declared_reissue_date" =>
                receipt.pdf_declared_reissue_date,
            "pdf_declared_correction_scope" =>
                receipt.pdf_declared_correction_scope,
            "diagnostic_payroll_change_thousands" =>
                receipt.diagnostic_payroll_change_thousands,
            "diagnostic_unemployment_rate_percent" =>
                receipt.diagnostic_unemployment_rate_percent,
            "diagnostic_headline_values_status" =>
                receipt.diagnostic_headline_values_status,
        ),
        "storage" => Dict(
            "raw_object_relative_path" =>
                receipt.raw_object_relative_path,
            "storage_mode" => receipt.storage_mode,
            "storage_encoding" => receipt.storage_encoding,
        ),
        "capture" => Dict(
            "capture_method" => receipt.capture_method,
            "browser_download_observed_at_utc" =>
                receipt.browser_download_observed_at_utc,
            "browser_observation_basis" =>
                receipt.browser_observation_basis,
            "import_started_at_utc" => receipt.import_started_at_utc,
            "import_completed_at_utc" =>
                receipt.import_completed_at_utc,
            "import_local_date" => receipt.import_local_date,
        ),
        "release_time_boundary" => Dict(
            "release_stated_embargo_time" =>
                receipt.release_stated_embargo_time,
            "release_stated_public_time" =>
                receipt.release_stated_public_time,
            "release_event_timestamp_utc" =>
                receipt.release_event_timestamp_utc,
            "release_time_inferred_from_browser_capture" =>
                receipt.release_time_inferred_from_browser_capture,
            "browser_retrieval_is_release_event_evidence" =>
                receipt.browser_retrieval_is_release_event_evidence,
        ),
        "terms" => Dict(
            "copyright_terms_locator" =>
                receipt.copyright_terms_locator,
            "api_terms_locator" => receipt.api_terms_locator,
            "terms_reviewed_local_date" =>
                receipt.terms_reviewed_local_date,
            "public_domain_status" => receipt.public_domain_status,
            "source_attribution" => receipt.source_attribution,
            "file_specific_image_review_required" =>
                receipt.file_specific_image_review_required,
            "file_specific_image_review_status" =>
                receipt.file_specific_image_review_status,
            "api_terms_applicability" =>
                receipt.api_terms_applicability,
            "bls_emblem_reuse_authorized" =>
                receipt.bls_emblem_reuse_authorized,
            "redistribution_authorized" =>
                receipt.redistribution_authorized,
        ),
        "gates" => Dict(
            "historical_first_state_verified" =>
                receipt.historical_first_state_verified,
            "historical_availability_verified" =>
                receipt.historical_availability_verified,
            "origin_admissible" => receipt.origin_admissible,
            "empirical_execution_allowed" =>
                receipt.empirical_execution_allowed,
            "inventory_mutation_authorized" =>
                receipt.inventory_mutation_authorized,
            "ready" => receipt.ready,
        ),
    )
end

function _toml_bytes(receipt)
    io = IOBuffer()
    TOML.print(io, _receipt_document(receipt); sorted = true)
    bytes = take!(io)
    isempty(bytes) && fail("receipt.serialization", "must not be empty")
    bytes[end] == UInt8('\n') || push!(bytes, UInt8('\n'))
    return bytes
end

receipt_file_sha256(receipt::BLSEmploymentCaptureReceipt) =
    sha256_hex(_toml_bytes(receipt))

function _reject_symlink_components(path, location)
    current = abspath(normpath(String(path)))
    components = String[]
    while true
        push!(components, current)
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    for component in Iterators.reverse(components)
        islink(component) &&
            fail(
            location,
            "path traverses symbolic-link component $component",
        )
    end
    return nothing
end

function _exact_keys(document, expected, location)
    document isa AbstractDict ||
        fail(location, "must be a TOML table")
    actual = Set(String(key) for key in keys(document))
    actual == expected ||
        fail(
        location,
        "keys differ; expected $(sort!(collect(expected))), found $(sort!(collect(actual)))",
    )
    return document
end

function _field(table, key, expected_type, location)
    value = table[key]
    value isa expected_type ||
        fail(
        "$location.$key",
        "must have type $expected_type, found $(typeof(value))",
    )
    return value
end

function _receipt_from_document(document)
    root = _exact_keys(document, RECEIPT_SECTIONS, "receipt")
    artifact =
        _exact_keys(root["artifact"], ARTIFACT_KEYS, "receipt.artifact")
    source = _exact_keys(root["source"], SOURCE_KEYS, "receipt.source")
    document_evidence = _exact_keys(
        root["document_evidence"],
        DOCUMENT_EVIDENCE_KEYS,
        "receipt.document_evidence",
    )
    storage =
        _exact_keys(root["storage"], STORAGE_KEYS, "receipt.storage")
    capture =
        _exact_keys(root["capture"], CAPTURE_KEYS, "receipt.capture")
    release = _exact_keys(
        root["release_time_boundary"],
        RELEASE_TIME_KEYS,
        "receipt.release_time_boundary",
    )
    terms = _exact_keys(root["terms"], TERMS_KEYS, "receipt.terms")
    gates = _exact_keys(root["gates"], GATE_KEYS, "receipt.gates")
    s(table, key, location) = _field(table, key, String, location)
    b(table, key, location) = _field(table, key, Bool, location)
    i(table, key, location) = _field(table, key, Int64, location)
    return BLSEmploymentCaptureReceipt(
        s(artifact, "schema_version", "receipt.artifact"),
        s(artifact, "receipt_id", "receipt.artifact"),
        s(artifact, "canonicalization", "receipt.artifact"),
        s(artifact, "digest_algorithm", "receipt.artifact"),
        b(artifact, "immutable_receipt", "receipt.artifact"),
        s(artifact, "receipt_sha256", "receipt.artifact"),
        s(source, "source_agency", "receipt.source"),
        s(source, "publication_name", "receipt.source"),
        s(source, "release_id", "receipt.source"),
        s(source, "reference_period", "receipt.source"),
        s(source, "source_url", "receipt.source"),
        s(source, "expected_raw_sha256", "receipt.source"),
        i(source, "expected_byte_count", "receipt.source"),
        s(source, "observed_raw_sha256", "receipt.source"),
        i(source, "observed_byte_count", "receipt.source"),
        s(source, "pdf_signature", "receipt.source"),
        s(
            document_evidence,
            "archive_document_state",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "pdf_declared_evidence_basis",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "pdf_metadata_creation_date",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "pdf_metadata_modification_date",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "pdf_declared_reissue_date",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "pdf_declared_correction_scope",
            "receipt.document_evidence",
        ),
        i(
            document_evidence,
            "diagnostic_payroll_change_thousands",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "diagnostic_unemployment_rate_percent",
            "receipt.document_evidence",
        ),
        s(
            document_evidence,
            "diagnostic_headline_values_status",
            "receipt.document_evidence",
        ),
        s(storage, "raw_object_relative_path", "receipt.storage"),
        s(storage, "storage_mode", "receipt.storage"),
        s(storage, "storage_encoding", "receipt.storage"),
        s(capture, "capture_method", "receipt.capture"),
        s(
            capture,
            "browser_download_observed_at_utc",
            "receipt.capture",
        ),
        s(capture, "browser_observation_basis", "receipt.capture"),
        s(capture, "import_started_at_utc", "receipt.capture"),
        s(capture, "import_completed_at_utc", "receipt.capture"),
        s(capture, "import_local_date", "receipt.capture"),
        s(
            release,
            "release_stated_embargo_time",
            "receipt.release_time_boundary",
        ),
        s(
            release,
            "release_stated_public_time",
            "receipt.release_time_boundary",
        ),
        s(
            release,
            "release_event_timestamp_utc",
            "receipt.release_time_boundary",
        ),
        b(
            release,
            "release_time_inferred_from_browser_capture",
            "receipt.release_time_boundary",
        ),
        b(
            release,
            "browser_retrieval_is_release_event_evidence",
            "receipt.release_time_boundary",
        ),
        s(terms, "copyright_terms_locator", "receipt.terms"),
        s(terms, "api_terms_locator", "receipt.terms"),
        s(terms, "terms_reviewed_local_date", "receipt.terms"),
        s(terms, "public_domain_status", "receipt.terms"),
        s(terms, "source_attribution", "receipt.terms"),
        b(
            terms,
            "file_specific_image_review_required",
            "receipt.terms",
        ),
        s(
            terms,
            "file_specific_image_review_status",
            "receipt.terms",
        ),
        s(terms, "api_terms_applicability", "receipt.terms"),
        b(terms, "bls_emblem_reuse_authorized", "receipt.terms"),
        b(terms, "redistribution_authorized", "receipt.terms"),
        b(
            gates,
            "historical_first_state_verified",
            "receipt.gates",
        ),
        b(
            gates,
            "historical_availability_verified",
            "receipt.gates",
        ),
        b(gates, "origin_admissible", "receipt.gates"),
        b(gates, "empirical_execution_allowed", "receipt.gates"),
        b(
            gates,
            "inventory_mutation_authorized",
            "receipt.gates",
        ),
        b(gates, "ready", "receipt.gates"),
    )
end

function _canonical_input_path(path)
    text = _expect_nonempty_string(String(path), "input")
    candidate = abspath(normpath(text))
    _reject_symlink_components(candidate, "input")
    islink(candidate) && fail("input", "must not be a symbolic link")
    isfile(candidate) || fail("input", "must be a regular file")
    return realpath(candidate)
end

function _canonical_raw_root(path; create = false)
    text = _expect_nonempty_string(String(path), "raw_root")
    candidate = abspath(normpath(text))
    dirname(candidate) == candidate &&
        fail("raw_root", "must not be a filesystem root")
    _reject_symlink_components(candidate, "raw_root")
    islink(candidate) &&
        fail("raw_root", "must not be a symbolic link")
    ispath(candidate) && !isdir(candidate) &&
        fail("raw_root", "existing path must be a directory")
    if !ispath(candidate)
        create ||
            fail("raw_root", "must be an existing directory")
        mkpath(candidate)
    end
    islink(candidate) &&
        fail("raw_root", "must not be a symbolic link")
    return realpath(candidate)
end

function _ensure_internal_tree(root, components)
    current = root
    for component in components
        current = joinpath(current, component)
        islink(current) &&
            fail("raw_root", "internal component is a symbolic link")
        if ispath(current)
            isdir(current) ||
                fail("raw_root", "internal component is not a directory")
        else
            mkdir(current)
        end
    end
    return current
end

function _validate_existing_internal_tree(root, components)
    current = root
    for component in components
        current = joinpath(current, component)
        islink(current) &&
            fail("raw_root", "internal component is a symbolic link")
        isdir(current) ||
            fail("raw_root", "internal component is not a directory")
    end
    return current
end

function _read_object_bundle(
        bundle_path,
        expected_name,
        location,
    )
    islink(bundle_path) &&
        fail(location, "object directory must not be a symbolic link")
    isdir(bundle_path) ||
        fail(location, "object path must be a directory")
    stat(bundle_path).mode & 0o222 == 0 ||
        fail(location, "object directory must be write-protected")
    readdir(bundle_path; sort = true) == [expected_name] ||
        fail(location, "object directory has an unexpected file set")
    object_path = joinpath(bundle_path, expected_name)
    islink(object_path) &&
        fail(location, "object file must not be a symbolic link")
    isfile(object_path) ||
        fail(location, "object file must be regular")
    stat(object_path).mode & 0o222 == 0 ||
        fail(location, "object file must be write-protected")
    return (path = object_path, bytes = read(object_path))
end

function _validate_object_bundle(
        bundle_path,
        expected_name,
        expected_bytes,
        location,
    )
    object = _read_object_bundle(
        bundle_path,
        expected_name,
        location,
    )
    object.bytes == expected_bytes ||
        fail(location, "content-addressed object bytes do not match")
    return object.path
end

function _install_object(
        parent,
        object_name,
        filename,
        bytes,
        location,
    )
    object_path = joinpath(parent, object_name)
    islink(object_path) &&
        fail(location, "object directory must not be a symbolic link")
    if ispath(object_path)
        return _validate_object_bundle(
            object_path,
            filename,
            bytes,
            location,
        )
    end
    staging = mktempdir(parent; prefix = ".staging-")
    installed = false
    try
        staged_file = joinpath(staging, filename)
        open(staged_file, "w") do io
            write(io, bytes)
            flush(io)
        end
        read(staged_file) == bytes ||
            fail(location, "staged bytes failed read-back")
        chmod(staged_file, 0o444)
        chmod(staging, 0o555)
        mv(staging, object_path)
        installed = true
    finally
        if !installed && ispath(staging)
            chmod(staging, 0o755)
            for name in readdir(staging)
                chmod(joinpath(staging, name), 0o644)
            end
            rm(staging; recursive = true)
        end
    end
    return _validate_object_bundle(
        object_path,
        filename,
        bytes,
        location,
    )
end

function _load_receipt_bytes(bytes)
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(
            "receipt.file",
            "is not valid TOML ($(sprint(showerror, error)))",
        )
    end
    receipt = _receipt_from_document(document)
    validate_receipt(receipt)
    return receipt
end

"""
    validate_receipt_file(path, raw_root)

Validate strict TOML shape, receipt self-hash, content-addressed receipt path,
and the bound local raw object. Neither the receipt nor the raw object may be a
symbolic link or contain additional files.
"""
function validate_receipt_file(path, raw_root)
    receipt_candidate = abspath(normpath(String(path)))
    _reject_symlink_components(receipt_candidate, "receipt.file")
    islink(receipt_candidate) &&
        fail("receipt.file", "must not be a symbolic link")
    islink(dirname(receipt_candidate)) &&
        fail(
        "receipt.file",
        "object directory must not be a symbolic link",
    )
    isfile(receipt_candidate) ||
        fail("receipt.file", "must be a regular file")
    receipt_path = realpath(receipt_candidate)
    receipt_name_match = match(
        r"^receipt-self-sha256-([0-9a-f]{64})\.toml$",
        basename(receipt_path),
    )
    receipt_name_match === nothing &&
        fail("receipt.file", "filename is not content addressed")
    path_receipt_sha256 = only(receipt_name_match.captures)
    expected_receipt_name =
        "receipt-self-sha256-$path_receipt_sha256.toml"
    receipt_bundle = dirname(receipt_path)
    basename(receipt_bundle) == "sha256-$path_receipt_sha256" ||
        fail("receipt.file", "parent directory is not content addressed")
    receipt_object = _read_object_bundle(
        receipt_bundle,
        expected_receipt_name,
        "receipt.file",
    )
    receipt_object.path == receipt_path ||
        fail("receipt.file", "resolved object path differs")
    receipt_bytes = receipt_object.bytes
    receipt = _load_receipt_bytes(receipt_bytes)
    receipt.receipt_sha256 == path_receipt_sha256 ||
        fail(
        "receipt.file",
        "path digest does not equal the receipt self-hash",
    )
    receipt_bytes == _toml_bytes(receipt) ||
        fail(
        "receipt.file",
        "bytes are not the canonical serialization of the receipt",
    )

    root = _canonical_raw_root(raw_root)
    expected_receipt_path = joinpath(
        root,
        "bls",
        "employment_situation",
        "archive",
        "receipts",
        "sha256-$(receipt.receipt_sha256)",
        expected_receipt_name,
    )
    receipt_path == expected_receipt_path ||
        fail(
        "receipt.file",
        "is not at the exact content-addressed path under raw root",
    )
    _validate_existing_internal_tree(
        root,
        [
            "bls",
            "employment_situation",
            "archive",
            "receipts",
            "sha256-$(receipt.receipt_sha256)",
        ],
    )
    raw_path = normpath(joinpath(root, receipt.raw_object_relative_path))
    relative = relpath(raw_path, root)
    (relative == ".." || startswith(relative, "../")) &&
        fail("receipt.raw_object_relative_path", "escapes raw root")
    expected_raw_name =
        "raw-sha256-$(receipt.observed_raw_sha256).pdf"
    raw_bundle = _validate_existing_internal_tree(
        root,
        [
            "bls",
            "employment_situation",
            "archive",
            "objects",
            "sha256-$(receipt.observed_raw_sha256)",
        ],
    )
    raw_object = _read_object_bundle(
        raw_bundle,
        expected_raw_name,
        "receipt.raw_object",
    )
    raw_object.path == raw_path ||
        fail(
        "receipt.raw_object",
        "resolved path differs from the receipt binding",
    )
    raw_bytes = raw_object.bytes
    validation = validate_browser_download(
        raw_bytes,
        ArchiveExpectation(
            receipt.release_id,
            receipt.reference_period,
            receipt.source_url,
            receipt.expected_raw_sha256,
            receipt.expected_byte_count,
        ),
    )
    return (
        receipt = receipt,
        receipt_path = receipt_path,
        receipt_sha256 = receipt.receipt_sha256,
        receipt_file_sha256 = sha256_hex(receipt_bytes),
        raw_object_path = raw_path,
        raw_sha256 = validation.raw_sha256,
        raw_byte_count = validation.raw_byte_count,
        historical_first_state_verified = false,
        historical_availability_verified = false,
        origin_admissible = false,
        empirical_execution_allowed = false,
        inventory_mutation_authorized = false,
        ready = false,
    )
end

function _import_browser_download(
        input,
        raw_root;
        expectation,
        live,
        terms_reviewed_local_date,
        browser_download_observed_at_utc,
        import_local_date,
        import_started_at_utc,
        import_completed_at_utc,
    )
    live === true ||
        fail("live", "explicit live=true opt-in is required")
    review_date = terms_reviewed_local_date isa Date ?
        terms_reviewed_local_date :
        _parse_date(
            String(terms_reviewed_local_date),
            "terms_reviewed_local_date",
        )
    local_date = import_local_date isa Date ?
        import_local_date :
        _parse_date(String(import_local_date), "import_local_date")
    review_date == local_date ||
        fail(
        "terms_reviewed_local_date",
        "must equal the host-local import date $local_date",
    )
    browser_time = browser_download_observed_at_utc isa DateTime ?
        browser_download_observed_at_utc :
        _parse_timestamp(
            String(browser_download_observed_at_utc),
            "browser_download_observed_at_utc",
        )
    start_time = import_started_at_utc isa DateTime ?
        import_started_at_utc :
        _parse_timestamp(
            String(import_started_at_utc),
            "import_started_at_utc",
        )
    browser_time <= start_time ||
        fail(
        "browser_download_observed_at_utc",
        "must not be later than import start",
    )
    supplied_complete_time = if import_completed_at_utc === nothing
        nothing
    elseif import_completed_at_utc isa DateTime
        import_completed_at_utc
    else
        _parse_timestamp(
            String(import_completed_at_utc),
            "import_completed_at_utc",
        )
    end
    supplied_complete_time !== nothing &&
        start_time > supplied_complete_time &&
        fail(
        "import_completed_at_utc",
        "must not precede import start",
    )

    input_path = _canonical_input_path(input)
    raw_bytes = read(input_path)
    validation =
        validate_browser_download(raw_bytes, expectation)
    root = _canonical_raw_root(raw_root; create = true)

    object_parent = _ensure_internal_tree(
        root,
        ["bls", "employment_situation", "archive", "objects"],
    )
    raw_object_name = "sha256-$(validation.raw_sha256)"
    raw_filename = "raw-sha256-$(validation.raw_sha256).pdf"
    raw_object_path = _install_object(
        object_parent,
        raw_object_name,
        raw_filename,
        validation.raw_bytes,
        "raw_object",
    )

    complete_time = supplied_complete_time === nothing ?
        now(UTC) :
        supplied_complete_time
    start_time <= complete_time ||
        fail(
        "import_completed_at_utc",
        "must not precede import start",
    )
    receipt = _build_receipt(
        expectation,
        validation;
        terms_reviewed_local_date = review_date,
        browser_download_observed_at_utc = browser_time,
        import_started_at_utc = start_time,
        import_completed_at_utc = complete_time,
        import_local_date = local_date,
    )
    validate_receipt(receipt)
    receipt_bytes = _toml_bytes(receipt)

    receipt_parent = _ensure_internal_tree(
        root,
        ["bls", "employment_situation", "archive", "receipts"],
    )
    receipt_object_name = "sha256-$(receipt.receipt_sha256)"
    receipt_filename =
        "receipt-self-sha256-$(receipt.receipt_sha256).toml"
    receipt_path = _install_object(
        receipt_parent,
        receipt_object_name,
        receipt_filename,
        receipt_bytes,
        "receipt_object",
    )
    result = validate_receipt_file(receipt_path, root)
    result.raw_object_path == raw_object_path ||
        fail(
        "raw_object",
        "validated receipt resolved a different raw object",
    )
    return result
end

"""
    import_browser_download(input, raw_root; ...)

Opt-in local import of the one pinned January 10, 2020 BLS archive PDF. The
public boundary does not accept an alternate expectation or clock. The caller
must set `live=true`, attest an operator-observed browser-download time, and
provide a terms-review date equal to `Dates.today()` on the import host. Import
start and completion use the live UTC clock.

The function does not perform network I/O, parse economic values, infer release
times, mutate `current_inventory.toml`, admit an origin, or authorize
execution.
"""
function import_browser_download(
        input,
        raw_root;
        live = false,
        terms_reviewed_local_date,
        browser_download_observed_at_utc,
    )
    return _import_browser_download(
        input,
        raw_root;
        expectation = JANUARY_2020_EXPECTATION,
        live,
        terms_reviewed_local_date,
        browser_download_observed_at_utc,
        import_local_date = Dates.today(),
        import_started_at_utc = now(UTC),
        import_completed_at_utc = nothing,
    )
end

end
