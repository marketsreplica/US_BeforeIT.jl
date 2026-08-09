# Upstream regime-adjudication ledger

This directory contains a bounded protocol utility for adjudicating regime
assertions before they enter forecast-comparison geometry. It preserves
admitted raw tokens and their evidence references, validates declared
dispositions, and emits contrast-local inclusion masks. It does not read
scores, compute a statistic, select a model, admit an origin, or authorize
promotion.

## Boundary and vocabulary

Every observation must have exactly one record for each frozen contrast:

- `PANDEMIC_REGIME_CONTRAST`: `PRE_PANDEMIC`, `PANDEMIC_ACUTE`, or
  `POST_ACUTE`;
- `NBER_REGIME_CONTRAST`: `NBER_RECESSION` or `NBER_EXPANSION`; and
- `POLICY_REGIME_CONTRAST`: `ELB_POLICY` or `STANDARD_POLICY`.

The only dispositions are:

- `REGIME_ACCEPTED`;
- `REGIME_UNKNOWN_PENDING_ADJUDICATION`;
- `REGIME_CONTRADICTION_QUARANTINED`; and
- `REGIME_CONFLICT_QUARANTINED`.

An accepted record requires one or more literally matching registered tokens.
Every other disposition retains `accepted_regime_label="NOT_ACCEPTED"` and is
excluded from only its affected regime contrast.

Every raw token admitted at this boundary is preserved exactly in order,
case, and multiplicity. Leading or trailing whitespace is rejected rather
than silently trimmed or normalized. Each token has a parallel,
non-placeholder `evidence_ref`; repeated tokens may retain the same reference
when they came from the same source, and the validated raw-token inventory
repeats every exact token/reference pair. References must use one of the
closed v1 namespaces `evidence:`, `manifest:`, `source:`, `sha256:`, `doi:`,
`urn:`, or `https:`. Reserved placeholder components such as `unknown`,
`placeholder`, or `todo` are rejected case-insensitively.

`SOURCE_ASSERTIONS_DISAGREE` accepts only labels registered for the affected
contrast and requires distinct assertions and distinct references.
`SOURCE_PROVENANCE_CONFLICT` permits identical retained assertions when
distinct sources disagree on vintage, timestamp, or concept provenance, but
still permits only affected-contrast labels and requires distinct references.
Contradictions may contain only registered regime labels;
mutually-exclusive-source contradictions also require distinct references.
Counts, masks, records, and the inventory are exhaustively cross-checked.

A raw token literally equal to `Used` is retained, never thrown away. It must
be pending with `BARE_USED_INVALID_FOR_REGIME` or, when its source context is
the BEA accounts, with
`NATIVE_BEA_ACCOUNTING_LABEL_OUTSIDE_REGIME_VOCABULARY`. `Other` is likewise
retained under an explicit pending reason. Neither token can be accepted,
converted to a baseline regime, or converted to numeric zero.

Typed source-usage provenance—such as `SOURCE_USAGE_INPUT_ONLY`—is metadata,
not a regime. If it reaches this raw regime-token boundary, the explicit
pending reason is
`SOURCE_USAGE_PROVENANCE_OUTSIDE_REGIME_VOCABULARY`. Native BEA `Used` and
`Other` accounting labels belong to their source tables and remain outside
the forecasting regime vocabulary.

## Masks and the primary analysis

`full_sample_primary_mask` is always true for every registered observation.
Its scope is strictly **regime adjudication**: it says that an unresolved
regime label does not delete an observation from the full-sample primary
analysis. It is not a score-cell eligibility decision. A downstream caller
must conjoin it with the separately validated forecast/truth pairing,
maturity, model-execution, target, horizon, and other score-cell eligibility
masks.

Each contrast receives its own observation-aligned mask. A pending,
contradicted, or conflicted pandemic record therefore excludes the
observation from the pandemic contrast only; it does not alter the NBER or
policy masks. This is the exact project protocol, not a claim that selective
exclusion is universally appropriate.

## API

```julia
include("USRegimeAdjudicationLedger.jl")
using .USRegimeAdjudicationLedger

document = build_regime_adjudication_ledger(
    "accepted-regime-review.v1",
    observation_ids,
    input_records,
)
validated = validate_regime_adjudication_ledger(document)

pandemic_mask = affected_contrast_inclusion_mask(
    validated,
    "PANDEMIC_REGIME_CONTRAST",
)
regime_only_full_mask = full_sample_primary_inclusion_mask(validated)
```

Input records contain exactly:

- `record_id`, `observation_id`, and `contrast_id`;
- parallel `raw_tokens` and `evidence_refs`;
- `disposition`, `accepted_regime_label`, and `issue_code`.

The builder derives token counts, both inclusion flags, the full token
inventory, exhaustive status counts, contrast masks, and a semantic SHA-256.
It immediately validates its own output. Records may arrive in any order, but
the observation-by-contrast grid must be complete and duplicate IDs or pairs
are fatal.

The validator rejects unknown schemas, fields, contrasts, dispositions,
reasons, labels, or evidence-reference namespaces; placeholder evidence
components; nonparallel token and evidence arrays; invalid conflict or
contradiction routing; attempts to route `Used`, `Other`, or source-usage
provenance outside pending adjudication; duplicate record or observation IDs;
incomplete grids; inconsistent counts or masks; any missing, reordered, or
altered inventory token/reference; an attempted full-sample regime exclusion;
and any artifact claiming to be a score, empirical result, or promotion
artifact. The registered protocol vocabularies are immutable tuples rather
than caller-mutable dictionaries or sets.

## Design provenance

The implementation choices are informed by, but are not dictated by:

- the W3C [PROV Data Model](https://www.w3.org/TR/2013/REC-prov-dm-20130430/),
  which motivates keeping source entities/provenance distinct from the
  adjudication activity and its derived disposition;
- Wilkinson et al.,
  [The FAIR Guiding Principles for scientific data management and stewardship](https://doi.org/10.1038/sdata.2016.18),
  which motivates explicit identifiers, metadata, and reusable token/evidence
  inventories;
- the
  [STROBE Statement](https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.0040296)
  and its
  [Explanation and Elaboration](https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.0040297),
  which motivate transparent reporting of exclusions, missingness handling,
  and sensitivity analyses; and
- BEA's official
  [Input-Output Accounts guide](https://www.bea.gov/resources/guide-interactive-industry-input-output-accounts-tables)
  and [I-O glossary](https://www.bea.gov/help/glossary/input-output-i-o-accounts),
  which establish that “use” has a native accounting meaning that must not be
  silently repurposed as a forecasting regime.

The exact status names, issue codes, exhaustive grid, self-hash, and
contrast-local exclusion rule are BeforeIT project protocol decisions. W3C
PROV, FAIR, STROBE, and BEA do not prescribe them.

## Limitations

- The semantic self-hash detects accidental mutation but is not an external
  acceptance pin or signature.
- Evidence references are validated as non-placeholder identifiers but are
  not dereferenced or authenticated here.
- The ledger can prove that every admitted token is retained. It cannot
  detect a token omitted before intake; upstream source completeness requires
  an independently bound source artifact or manifest. Whitespace-bearing
  tokens are rejected at admission, not rewritten.
- The utility validates declared adjudications. It does not infer NBER,
  pandemic, or policy regimes from dates and does not decide substantive
  contradictions.
- Contrast-local exclusion does not cure selection or missing-data bias.
  Effective sample counts and interpretation still require the frozen
  inference protocol and separately approved sensitivity analysis.

## Verification

From the repository worktree:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/inference/regime_adjudication/test_regime_adjudication_ledger.jl
```
