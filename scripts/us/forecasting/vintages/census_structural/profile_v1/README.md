# Census AIES/SUSB logical-schema mechanics v1

Status: **permanently nonadmitting `CANNOT_RUN`; logical-schema mechanics only**.

This isolated, standard-library-only artifact closes the documented logical
schema gaps for five 2023 Annual Integrated Economic Survey inventory products
and the 2022 Statistics of U.S. Businesses structural product. It does not
download, capture, parse, or attribute any Census body. Its tab-separated test
format is named
`BEFOREIT_SYNTHETIC_LOGICAL_TSV_V1_NOT_PROVIDER_BYTES` and is an internal
synthetic interchange format, not a claim about a ZIP member, direct TXT body,
delimiter, header, encoding, or row order used by Census.

The module contains no HTTP client and no filesystem writer. The test suite
creates only temporary tampered copies, symbolic links, and hard links to prove
that physical aliases fail closed; it does not write raw data, receipts,
inventory, shared configuration, worklog, CI, or forecast artifacts.

## Exact six-profile logical surface

Every AIES profile begins with the exact common structural set:

`GEO_ID,GEO_ID_F,INDLEVEL,NAICS,NAICS_F,NAICS_LABEL,NAME,SECTOR,YEAR`

The profile then preserves all additional dimensions and every value,
value-flag, coefficient-of-variation, and CV-flag field:

| Product | Candidate key | Additional dimensions/labels | Logical fields |
| --- | --- | --- | ---: |
| `AIES00INV` | `GEO_ID,YEAR,NAICS,TYPOP,TAXSTAT` | `TAXSTAT,TAXSTAT_LABEL,TYPOP,TYPOP_LABEL` | 21 |
| `AIES31INV` | `GEO_ID,YEAR,NAICS` | common labels and flags | 21 |
| `AIES42INV` | `GEO_ID,YEAR,NAICS,TYPOP` | `TYPOP,TYPOP_LABEL` | 23 |
| `AIES44INV` | `GEO_ID,YEAR,NAICS` | `INDGROUP,SUBSECTOR` | 23 |
| `AIES51INV` | `GEO_ID,YEAR,NAICS,TAXSTAT` | `TAXSTAT,TAXSTAT_LABEL` | 27 |

`AIES00INV` carries the receipts and total-inventory families.
`AIES31INV`, `AIES42INV`, and `AIES44INV` carry total inventory, LIFO
inventory, and LIFO-reserve families. `AIES51INV` carries total,
finished-goods, work-in-process, and materials inventory families. The TOML
enumerates every literal field; no parser-side aliases or inferred columns are
accepted.

The AIES publication symbols are typed states. `D` is withheld and included in
higher totals, `N` is unavailable/not comparable, `S` fails publication
standards, and `Z` rounds to zero. CV flags `v` and `w` preserve the documented
high-CV states. A flagged cell retains its exact value and flag lexemes and is
never silently converted to an unflagged numeric zero.

## SUSB all-size universe and projection

The canonical direct object name is
`us_state_6digitnaics_2022.txt`. The logical schema is exactly:

`STATE,NAICS,ENTRSIZE,FIRM,ESTB,EMPL,EMPLFL_R,EMPLFL_N,PAYR,PAYRFL_N,RCPT,RCPTFL_N,STATEDSCR,NAICSDSCR,ENTRSIZEDSCR`

The synthetic mechanics retain size codes `01` through `09`. They never sum all
nine overlapping rows. Within each synthetic `(STATE,NAICS)` group, the
mechanics check these documented identities when all participating values are
unflagged:

- `05 = 02 + 03 + 04`
- `08 = 05 + 06 + 07`
- `01 = 08 + 09`

`G`, `H`, and `J` remain typed noise ranges. `S` means the published numeric
zero is a withheld unknown included in broader totals; an identity touching
that value is recorded as unverified instead of treating the zero as observed.
Historical `D` is rejected in a 2022 synthetic fixture because it was replaced
by `S` starting in 2017. `EMPLFL_R` is required in the logical schema and empty
in the synthetic 2022 representation, while its literal presence in the future
provider body remains unresolved because Census discontinued it starting in
2018. The TOML deliberately records that the complete provider flag vocabulary
is not yet evidenced.

The result derives and independently hashes a separate
`STATE=00,ENTRSIZE=01` total-only projection. That projection cannot replace
the retained all-size rows. `FIRM` is never summed across NAICS: because an
enterprise can own establishments in several industries, it is labelled only
as an `industry_firm_presences` proxy pending a validated allocation or
deduplication ontology.

## Parser and replay boundary

The internal synthetic TSV parser requires an exact byte vector, valid UTF-8,
LF termination, no BOM, CR, blank lines, controls, leading/trailing field
whitespace, duplicate headers, unknown/reordered headers, wrong row widths,
oversized numeric lexemes, or duplicate candidate keys. It applies closed
synthetic type grammars and bounded body, row, and field sizes. These rules
exercise logical mechanics; they are not a proposed Census physical parser.

Numeric, code, and hash lexemes are checked with manual bytewise ASCII
predicates. The module retains no `Regex`, array, dictionary, or set as
persistent policy state. The regression suite swaps every field of a strict
caller-owned `Regex` with a permissive one using ordinary Julia `setfield!`,
proves that the swapped object now matches `NaN`, and proves that the parser
still rejects `NaN`. It also recursively audits the immutable tuple-based
policy surface and verifies that mutating one returned result cannot poison a
fresh result.

The exported in-memory profile validator accepts only the concrete Julia types
emitted by the pinned TOML parser at every nesting level and compares their
full type topology with the frozen profile before semantic hashing. Exact-value
aliases such as `SubString{String}`, `SubArray`, `IdDict`, changed vector element
types, non-native integer widths, Boolean/integer swaps, and floats therefore
cannot exploit the canonicalizer's intentionally broad abstract-type encoding.

`build_structural_result` reparses all six fixtures in frozen profile order,
checks SUSB coverage and overlap identities, types every publication state,
derives the national-total projection, and emits only `CANNOT_RUN` with every
gate false. `validate_structural_result` rebuilds that result from the exact
fixture bytes and performs type-exact recursive comparison. A self-rehashed
status, gate, raw field, typed state, projection, overlap result, count, or
extra member cannot pass replay.

The profile self-hash excludes only `artifact.content_sha256`. The module pins
both its physical and semantic identities, so a coordinated TOML restamp does
not authorize a changed schema, gate, claim, source binding, or evidence state.
The operational load, parse, build, and replay paths always verify all nine
physical source pins. No exported operation has a `verify_sources` or injected
source-verifier keyword. Paths resolve from `@__DIR__`, reject traversal and
internal symbolic links, and require regular single-link files, so an unrelated
working directory cannot redirect the closure.

The pinned prospective-v2 artifacts document the legacy requirement surface;
they are change-detection dependencies, not endorsement of their earlier AIES
member, delimiter, or underspecified selector claims. The profile also pins the
common-origin-v4 module/policy, current inventory, `sources.toml`,
`USPipeline.jl`, and the `scripts/us` Julia environment.

## Permanent claim ceiling

This artifact resolves **6/6 logical schemas and 0/6 physical layouts**. It
does not establish any of the following:

- exact AIES member names, CRCs, delimiter, quoting, header bytes/order/case,
  encoding/BOM, newlines, null lexemes, row order, or membership;
- the SUSB body header, encoding, newlines, blank/null behavior, row order,
  complete flag vocabulary, or literal 2022 `EMPLFL_R` presence;
- source response bytes, source hashes, full-object completeness, publication
  or intraday availability, first-public history, or atomicity;
- authenticated Census, transport, timestamp, trust, or durable custody;
- a qualified leaf, admitted origin, model input, forecast execution, truth
  access, score, accuracy claim, promotion, or production readiness.

Local hashes prove only local fixity. A successor must prospectively preserve
the five ZIP bodies and the one direct TXT body with their documentation and
transport evidence, independently rederive the physical facts, and pass the
project's authenticated common-origin boundary before any status may rise.

## Verification

From the worktree root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/census_structural/profile_v1/test_census_structural_profile_v1.jl
```

From an unrelated directory, use absolute paths for both `--project` and the
test script. Both executions currently pass **273/273** assertions.

Runic 1.7.0 must accept both Julia files:

```sh
JULIA_LOAD_PATH=/Users/sina/.julia/packages/Runic/XIBDc:/Users/sina/.julia/packages/JuliaSyntax/J00sR:/Users/sina/.julia/packages/Preferences/kUJxq:@stdlib \
  julia --startup-file=no -e 'using Runic; exit(Runic.main(ARGS))' -- --check \
  scripts/us/forecasting/vintages/census_structural/profile_v1/USCensusStructuralProfileV1.jl \
  scripts/us/forecasting/vintages/census_structural/profile_v1/test_census_structural_profile_v1.jl
```

Frozen candidate identities before independent review:

| Artifact | SHA-256 |
| --- | --- |
| module | `e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68` |
| profile physical | `512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157` |
| profile semantic | `c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491` |
| tests | `ef2089d3fb47400947111f8b8a743999c42c0092b547d70e8be7c9708447cd55` |

These identities designate only a replacement candidate submitted for
independent audit. They are not an acceptance or qualification claim.
