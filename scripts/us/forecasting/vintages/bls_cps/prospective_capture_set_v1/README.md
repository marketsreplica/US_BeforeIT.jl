# BLS CPS prospective capture-set candidate v1 — audit-repaired freeze

This directory contains an isolated offline candidate for the six
`bls_cps_structural` profiles. The first freeze is rejected and historical; the
hashes below identify the audit-repaired freeze. Its permanent status is
`CANNOT_RUN`. There is no downloader, HTTP client, capture command, raw-data or
receipt writer, inventory mutation, admission, promotion, model execution,
truth access, or scoring path.

Passing the tests establishes mechanics against generated synthetic bytes only.
It does not establish that BLS produced or authenticated any bytes, that the
injected bytes came from a planned URL, that September 2026 was available, that
the object set is a complete provider snapshot, that responses were atomic or
first-public, or that a qualified common-origin leaf exists. Qualified coverage
remains zero of six.

## Frozen plan and claim ceiling

The ordered profile set is:

| Ordinal | Profile | Series | Treatment | Unit | Frozen begin |
| ---: | --- | --- | --- | --- | --- |
| 1 | `cps_employed` | `LNU02000000` | NSA | thousands | 1948/M01 |
| 2 | `cps_inactive` | `LNU05000000` | NSA | thousands | 1975/M01 |
| 3 | `cps_labor_force` | `LNU01000000` | NSA | thousands | 1948/M01 |
| 4 | `cps_population` | `LNU00000000` | NSA | thousands | 1948/M01 |
| 5 | `cps_unemployed` | `LNU03000000` | NSA | thousands | 1948/M01 |
| 6 | `cps_unemployment_rate` | `LNS14000000` | SA | percent | 1948/M01 |

The SA unemployment-rate series is never treated as one of the five NSA count
series. Population/labor-force/employment identities are diagnostic only and
cannot admit or reject evidence. M13 annual averages are not needed by these six
monthly projections and are rejected rather than accepted through an
underconstrained side channel.

The planned API operation is eight unregistered v2 POST bodies in this exact
order: 1948–1957, 1958–1967, 1968–1977, 1978–1987, 1988–1997, 1998–2007,
2008–2017, and 2018–2026. The planned catalog/lookup set is `ln.series`,
`ln.footnote`, `ln.seasonal`, `ln.periodicity`, `ln.lfst`, `ln.ages`, `ln.tdat`,
and `ln.txt`. Validation requires concrete `String` keys, concrete byte vectors,
exact 16-object cardinality and membership, and the frozen manifest ordinals
1–16.

The capture ID remains `final_structural_pre_origin`; its window is
2026-10-29T13:30:00Z through 2026-10-30T13:45:00Z, strictly before the
2026-10-30T14:00:00Z origin. The scheduled September Employment Situation event
on 2026-10-02 at 08:30 ET (12:30Z) is separate. The documented one-day public
API lag means a release-time request cannot alone establish September
availability. These are plan semantics, not evidence that any request ran.

## Full raw objects and the projection receipt

Injected catalog bytes are treated as unauthenticated full-object candidates.
The object manifest records their full byte counts and SHA-256 hashes, but uses a
separate `planned_url` field and always records
`planned_url_bytes_claimed=false`. It never labels a selected seven-row table as
the bytes returned by a provider URL. A seven-row `ln.series` stand-in is
rejected.

The TSV adapter permits extra physical columns and irrelevant rows. It locates
the required columns by unique decoded header name, retains the hashes of all
eight complete injected objects, selects exactly one row for each frozen series,
and creates a separate self-hashed catalog-projection receipt. That receipt binds:

- all eight full raw object hashes, sizes, IDs, and ordinals;
- the complete physical `ln.series` header and its hash;
- the full data-row and irrelevant-row counts;
- each selected physical row ordinal and decoded tab-row hash (with the full raw
  hash retaining the physical bytes and line endings);
- every selected field and referenced lookup code/physical row ordinal;
- every full lookup header.

The receipt and enclosing result are accepted only by replaying the frozen
profile and all 16 injected byte vectors. Coordinated self-rehashing is not
sufficient.

The exact physical provider header/layout is **not locally evidenced**. The
column names used by synthetic adversarial fixtures are not asserted to be the
official BLS schema. Consequently the profile, receipt, and result all keep
provider-layout evidence, projection operationality, full-provider-object
completeness, and origin gates false. A future prospective preservation of the
complete physical catalog set must establish the real header/layout before a
new reviewed adapter version can be considered. The current profile must not be
restamped to fit future bytes.

## Parser and coverage boundaries

The JSON parser checks `isvalid(String, bytes)` before parsing and again on every
decoded string. It rejects invalid UTF-8, unpaired surrogates, duplicate member
names after escape decoding at every nesting level, excessive bytes/depth/nodes
or string size, malformed numeric grammar, and trailing bytes. The API validator
requires empty BLS messages, integer—not floating or Boolean—`responseTime`,
exact six-series order per chunk, exact chunk/year membership, and exact period,
value, and footnote preservation.

The TSV/text parsers explicitly reject invalid UTF-8, NUL/CR, blank or ragged
rows, duplicate headers/codes/series IDs, and configured byte/line/column/field
ceilings. `ln.series` has a frozen 32 MiB ceiling (33,554,432 bytes), more than
twice the independent-audit reference size of 15,288,538 bytes. That size
reference is not publisher authentication or proof that locally supplied bytes
are complete.

Monthly coverage must be exact and gap/overlap-free from the frozen catalog
begin through 2026/M09. October 2025 must remain explicit `-` missing data with
footnote code 9 and its exact text; zero and interpolation reject. M13 always
rejects.

## Frozen profile and upstream bindings

Only the adjacent checked-in profile path is accepted. Its semantic identity is
pinned independently of its self-hash, so an alternate path or coordinated
self-restamp fails. The validator also freezes the exact top-level shape,
contract and requirement/source/capture IDs, selectors, begin periods, request
bodies, routes, resource ceilings and rationale, gates, prohibited actions, and
ordered unique source pins.

The 11 upstream byte pins cover prospective-v2 (module and contract),
common-origin-v3 (module and policy), the accepted snapshot envelope (module and
tests), `sources.toml`, `USPipeline.jl`, `Project.toml`, `Manifest.toml`, and the
current source inventory.

Every public operational call—`validate_profile`, `validate_capture_set`, and
`validate_compiled_result`—always performs the exact 11-file existence,
physical-hash, symbolic-link, and hard-link checks. None exposes a
`verify_sources` keyword or another source-verification bypass. The separately
named internal profile-document unit helper performs only immutable document
checks and returns `nothing`; it cannot emit a compiled validation result. Tests
inject a failing internal verifier and prove the operational source-verification
boundary is reached, then use method/keyword introspection to reject the removed
bypass.

Audit-repaired hashes:

- profile semantic SHA-256:
  `68e8d7a1a366c9409e4a29f83dfa90864fbcb0024fcbd91aa53cc16dcbd04e8b`
- profile physical SHA-256:
  `d6bad6ffc6279cacee09ae3fcdec688df1b460515e12ffc2f17d918b40ae7081`
- module SHA-256:
  `549b0001a41051d587d46ed2979345cb5a7897b9b6fe2d54d06f9e75bf0b0caa`
- test SHA-256:
  `669d0ce7bddd0d1a849e09736e69a66e93fbacd48002b729736d0c64c711d031`

## Why common-origin-v3 remains false

The accepted common-origin-v3 dispatch permits one selected JSON/CSV source
payload. It has no set-valued raw-object type, TSV/text catalog media branch, or
catalog-to-series trust/selection receipt. A successor needs an accepted ordered
capture-set envelope, exactly-once preservation semantics, two independently
checked replicas, media-specific validators, catalog/selector receipts tied to
every full raw hash, and an independent validation receipt type. These are gaps,
not capabilities claimed here.

## Strict verification

From the repository root:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bls_cps/prospective_capture_set_v1/test_bls_cps_prospective_capture_set_v1.jl
```

Run the same absolute command from an unrelated directory such as
`/private/tmp`. Require Runic 1.7.0 `--check` on both Julia files, a scoped
`git diff --check`, no conflict markers or trailing whitespace, and exact
physical/semantic hashes. The repaired suite has 118 assertions.

Fresh independent review is required before reuse. It must audit the missing
provider schema evidence, full-object/projection separation, UTF-8 boundaries,
profile freeze and alternate-path rejection, exact object identity/order, M13
rejection, resource ceilings, replay resistance, and all-false gates. The review
must make no request, preserve no raw bytes, mutate no shared file or inventory,
and never call this candidate qualified.
