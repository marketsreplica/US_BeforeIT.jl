# EFFR prospective endpoint profile v1

This directory is an additive, isolated, read-only contract for one candidate
EFFR model-input estimand. Its checked-in state is exactly `CANNOT_RUN`. It is
not an acquisition runner, an admission compiler, a wrapper around the legacy
prospective-v2 EFFR profiles, or a forecast/score path. It does not edit the
accepted upstream contracts, source inventory, raw evidence, work log, or CI.

The artifact is a possible qualified leaf in a future semantic supersession of
the three legacy prospective-v2 profiles. It cannot satisfy the parent-v3 EFFR
requirement until a separately reviewed three-profile legacy-to-active decision
and exact qualified-leaf dispatch exist. Editing or rehashing this v1 artifact
cannot promote it; a successor evidence-admission compiler and external
receipts are required.

## Estimand and claim ceiling

The distinct model-input-only estimand is:

```text
PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE
```

It means the latest separately preserved, observed-state-v3-validated EFFR
rate/volume endpoint pair whose complete capture finished strictly before the
forecast-origin cutoff. Selecting a latest-as-of input also requires the exact
candidate date set, both rate and volume rows, holiday treatment, capture
manifests, observed-state decisions, external timestamps, and durable-replica
lineage to be independently verified. None is present today.

Its strongest allowed positive claim is exactly:

```text
MARKETS_API_EFFR_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY
```

For an unchanged second observation, the strongest transition claim remains:

```text
NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE
```

The estimand is never `currentState`, first-public bytes, a historical
first-byte observation, an atomic publisher transaction, the final daily
state, proof that no later same-day revision or correction occurred,
authenticated publisher/transport provenance, truth, or a forecast output.
The accepted observed-state-v3 contract records literal `currentState` as
absent and forbids deriving or synthesizing it.

## Three evidence populations that must not be conflated

### Q3 endpoint-history campaign candidate

The candidate pre-origin endpoint range is 2026-07-01 through 2026-10-29. It
contains 84 weekdays after excluding exactly 2026-07-03, 2026-09-07, and
2026-10-12. This exact date set and every rate/volume row and receipt chain
remain unverified and unapproved.

The 84-date range is only a Q3 endpoint-history campaign candidate. It is not
the complete `effr_daily_history` training universe and does not establish
training-sample sufficiency.

### Model-input training history

The model-input daily-history selector start is deliberately `UNDECIDED`, its
approval is false, and training-history sufficiency is false. The project
core-three empirical contract requires at least 60 quarterly observations and
its revised geometry starts at 2000Q3; an 84-business-day 2026 range cannot
satisfy that requirement.

A successor must justify and approve an exact history start and explicitly
decide how the pre/post-2016 EFFR regimes are treated. The New York Fed states
that the EFFR methodology and data source changed for the rate effective
2016-03-01. The local contract records the official reference URLs but does not
turn a URL or local hash into authenticated publisher evidence:

- <https://www.newyorkfed.org/markets/reference-rates/effr>
- <https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates>

### August 10 restart diagnostics

The restart-v2 schedule contains exactly:

- 58 morning endpoint observations from 2026-08-10 through 2026-10-30;
- 57 later observations from 2026-08-10 through 2026-10-29;
- 115 total slots; and
- at most 57 within-campaign comparisons.

This campaign is non-first-public endpoint-transition diagnostic lineage. It
does not establish the Q3 endpoint-history range or model-training history.

The predecessor v1 campaign remains irrecoverably incomplete. It planned 117
slots, preserved one incompatible nonadmitting August 7 morning capture, and
missed the August 7 later window, leaving a theoretical maximum of 116/117.
Neither campaign may complete, borrow from, combine with, or relabel the other.
In particular, the restart cannot silently turn the old 117-slot manifest into
a completed manifest and imports no August 7 observation.

## Approval, lineage, and parent dispatch

Readiness requires all of the following through exact external artifacts:

- a model-owner approval and a distinct independent-validator approval;
- an approved three-profile legacy-to-active supersession decision;
- an exact qualified parent-v3 leaf dispatch;
- independently verified, nonsynthetic endpoint-history, training-history,
  and restart-diagnostic lineage;
- exact coverage, rate/volume, receipt, observed-state-decision, and
  predecessor chains;
- a trusted external timestamp for every required observation; and
- verified custody in at least two genuinely independent durability domains.

Self-rehashed local documents, local file hashes, transport labels, and
synthetic fixtures are insufficient. The checked-in profile contains 26
independently named false readiness conditions and emits 26 blockers.

## Retention defect

Prospective v2 retains through only `2031-10-30T14:00:00Z`. That does not cover
the full h12 truth geometry:

```text
h12 target                         2029Q3
h12 target period end              2029-09-30T23:59:59Z
mature-truth lag                   60 months
mathematical minimum custody end   2034-09-30T23:59:59Z
conservative cushion               2034-10-30T14:00:00Z
```

The conservative date is a cushion, not the derived boundary. Operational
release must occur no earlier than the later of the mathematical minimum and
verified mature-receipt completion plus a successor post-receipt audit policy.
That policy and a full-horizon successor retention contract are both missing,
so this profile cannot become ready.

## Permanent no-action surface

This v1 validator is read-only and stdlib-only. It has no downloader, network
client, runner, model, truth loader, serializer, writer, inventory mutation,
admission, forecast, scoring, promotion, or production-use surface. All gates
remain false. The prohibited-action set includes raw/receipt writes, inventory
mutation, origin admission, truth load, model execution, forecast/score
append, forecast emission, and model promotion.

The source reader rejects path escape, every symbolic-link component, and
hard-linked leaves. It reads each bound file once, checks its exact physical
SHA-256, parses only the pinned accepted contracts, independently recomputes
their semantic identities, checks critical fail-closed fields, validates the
profile's closed fixed schema and semantic self-hash, and exactly replays the
current result. These are local fixity checks, not publisher authentication.

## Exact accepted bindings

| Accepted package | Physical SHA-256 identities | Semantic SHA-256 |
|---|---|---|
| observed-state v3 | module `3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6`; protocol `d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716`; tests `55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c`; README `4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23` | `33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c` |
| prospective v2 | module `435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379`; contract `b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f`; tests `4e46ef57fd9b3b26be884175b6594b4f425719fc96944da9b0d9c60db10d1083`; README `9d51d793ea36f440eec697180a71b221331495766b424d683cb7a1bd1b28e9ad` | `5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a` |
| restart v2 | module `5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155`; schedule `670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136`; tests `0f0df50d5fbc1f1ef666084d5c20cf7e40f5116549ecc1390404959013beea33`; README `fa7288ef3addd50c4836ec89971e1b002d6940fc42b37bc8010a1773ab4305d6` | `cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b` |
| restart v4 | module `a7c2e4c092e5e7a17e1bfd4143641a2e97c5566386720630ee06f12066d8b527`; CLI `cf3b1eb6eec26f711f5a75c6c3cef7448a782d7c1ad216e79df4d41ca45e0e02`; tests `f77f66cbce8ee3d936e9b7fe61d26b449ed4759b4aeeaa9ab74842a7b3c9fda5`; README `861a43dbae2bc42f3862809fa33145ab8041ffbfbcc0f622359ada0229687d4e` | physical binding only |

## Profile and result identities

| Artifact | SHA-256 |
|---|---|
| validator module bytes | `3bb2acc114889be098c8e7acafabd5ae584448d2de64fd84692f6065b5832f4b` |
| profile TOML bytes | `7de8e23e11d202a887e20d6e90616501562c9c3682db1200c753bb207ae4451b` |
| profile semantic content | `4ed9a0f99c6c8490da35c290ce87c6051a6a1bf08da5eb2ee8ac601f75a4eaa5` |
| exact current result semantic content | `35c422d6483cabfe17df0f3aac58ef1139573c78ef5d4b9ae5fc5de94ec732a4` |
| adversarial test bytes | `f6d5dd59cc57cb1d1513bbb0cdb6bd628d19dba7eef8cc33770b1d5d1981adc1` |

The README hash is intentionally reported outside this self-description to
avoid a recursive self-hash claim.

## Verification

Run the 341-test hermetic suite from the repository root:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_endpoint_profile_v1/test_effr_prospective_endpoint_profile_v1.jl
```

Run the same suite from an unrelated working directory with absolute paths:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/effr/prospective_endpoint_profile_v1/test_effr_prospective_endpoint_profile_v1.jl
```

Check both Julia files with Runic 1.7.0:

```bash
runic --check \
  scripts/us/forecasting/vintages/effr/prospective_endpoint_profile_v1/USEFFRProspectiveEndpointProfileV1.jl \
  scripts/us/forecasting/vintages/effr/prospective_endpoint_profile_v1/test_effr_prospective_endpoint_profile_v1.jl
```

Passing establishes only the frozen offline contract mechanics and exact
`CANNOT_RUN` result. It does not establish coverage, provenance, approval,
retention, model-input readiness, origin admission, or forecast accuracy.
