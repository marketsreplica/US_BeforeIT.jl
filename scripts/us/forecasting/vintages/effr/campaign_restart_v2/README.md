# EFFR additive campaign restart v2

This directory is a hermetic, pre-capture control for a new EFFR campaign
beginning on 2026-08-10. It does not edit, relabel, backfill, or combine the
frozen 117-slot v1 campaign. That predecessor remains byte-pinned,
withdrawn for future capture, incomplete, and outside the restart coverage
denominator.

The restart was declared after the 2026-08-07 revision window was missed and
before the earliest possible restart value observation on 2026-08-10. The
selection rule uses only the operational window miss and the predeclared
calendar. EFFR numeric values and the revision outcome are not selection
variables. The declaration timestamp is a local, unauthenticated project
record, not an external timestamp.

This package contains no downloader, network client, scheduler, automation,
raw writer, source-inventory writer, or admission path. It made no live
request and wrote nothing under `data/us/raw/` during implementation or
testing.

## Frozen denominator

`effr_2026q3_restart_schedule_v2.toml` explicitly lists every slot:

- 58 first-state slots from 2026-08-10 through 2026-10-30;
- 57 same-day revision-check slots from 2026-08-10 through 2026-10-29;
- 115 slots and at most 57 complete first/revision pairs;
- weekends, 2026-09-07, and 2026-10-12 are excluded; and
- the initial effective date is 2026-08-07, after which each effective date
  is the preceding authorized publication date.

The 2026-10-30 first-state deadline is 13:15Z, before the frozen 14:00Z
origin cutoff. There is no 2026-10-30 18:30Z revision slot. The restart can
therefore attain at most 115/115 of its own denominator. That denominator is
independent of v1: v1 slots cannot complete the restart, restart slots cannot
complete v1, and cross-campaign combination is false.

The withdrawn v1 facts are preserved separately. It planned 117 slots,
captured one August 7 first-state slot with the nonadmitting one-date-contract
incompatibility status, and missed the August 7 revision slot. Its theoretical
maximum after that miss was therefore 116/117: the one captured first state
plus at most 115 then-future slots. This is a v1-only, noncombinable ceiling,
not observed coverage and not a restart numerator. The August 7 evidence is
not imported into the restart denominator.

All 115 rows contain an exact sequence, publication and effective date,
phase, state class, UTC/New York/Madrid window, transaction ID, final bundle
path, private journal path, same-day predecessor path when applicable, and
one-date rate and volume query. Examples are:

```text
2026-08-10 first
  UTC       13:00:00–13:15:00Z
  New York  09:00:00–09:15:00-04:00
  Madrid    15:00:00–15:15:00+02:00
  tx        effr-20260810-first-1300z

2026-08-10 revision-check
  UTC       18:30:00–18:45:00Z
  New York  14:30:00–14:45:00-04:00
  Madrid    20:30:00–20:45:00+02:00
  tx        effr-20260810-revision-1830z

2026-10-26 revision-check
  UTC       18:30:00–18:45:00Z
  New York  14:30:00–14:45:00-04:00
  Madrid    19:30:00–19:45:00+01:00
```

Madrid changes from UTC+02 to UTC+01 before the October 26 slot; New York
remains UTC-04 throughout this campaign. The validator reconstructs this
transition rather than trusting descriptive labels.

The restart root is separately namespaced:

```text
data/us/raw/forecasting/effr/prospective/2026q3_restart_v2
```

A first-state final path has the form:

```text
<root>/YYYY-MM-DD/FIRST_0900_STATE/effr-YYYYMMDD-first-1300z
```

A revision final path has the form:

```text
<root>/YYYY-MM-DD/SAME_DAY_1430_REVISION_CHECK/effr-YYYYMMDD-revision-1830z
```

Its predecessor is the exact same-day first-state final path. Private
journals use `.journal-<transaction-id>` at the corresponding state root.

## No retry, duplicate, or late substitution

The contract fixes the following operational rules:

- no automatic retry;
- if the final bundle or private journal exists, issue no request;
- outside the closed slot window, issue no request and record operational
  missingness through a separately reviewed mechanism;
- one transaction identity per slot; and
- no retrospective fill or cross-campaign relabeling.

These are control fields, not evidence that an operator or automation has
implemented them. The accepted recurring-acquisition v3 source is pinned as
the implementation base, but it is still bound to the old schedule. The
restart contract records
`runner_restart_binding_complete=false`. A separate reviewed successor
binding is required before scheduling any restart capture.

## Evidence claim ceiling

Even a structurally valid capture can establish only:

```text
MARKETS_API_ENDPOINT_STATE_OBSERVED_AS_OF_CAPTURE_TIME_ONLY
```

If a revision check is unchanged, the strongest permitted result is:

```text
NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE
```

It does not prove first publication, historical first-byte visibility, that
no later same-day revision occurred, the final state for the day, transport
provenance, or origin admissibility. Every origin, empirical forecasting,
accuracy evaluation, scoring, promotion, production, inventory mutation,
and readiness gate remains false.

## Exact source bindings

The schedule pins the accepted recurring-acquisition v3 bytes, capture
contract, Julia environment, current source inventory, untouched predecessor
campaign, and independently accepted observed-state v3 contract.

| Artifact | SHA-256 |
|---|---|
| recurring module | `3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de` |
| recurring CLI | `e2f293dd77da818c5fd0ee64e8bb520a162f62e805c17fdc6cf6131f6db3800f` |
| recurring tests | `256eac940dace2e749efb98be33e9ba059f21883da5b6d0bf92fdac2beb7e41b` |
| recurring README | `052d02b3117037d86830de50783f43f782907ae84824fa7507acd36b70784d02` |
| capture-contract module | `6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651` |
| capture-contract tests | `6356f2f8ae4efb74ecbd063fb962f82a423d36c665276449679da3b197af3197` |
| capture-contract README | `6bc9934611c5641eed63a4802ac6dd83a55e0abe796e6f817a6a2855fecce326` |
| `scripts/us/Project.toml` | `72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c` |
| `scripts/us/Manifest.toml` | `c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263` |
| current inventory | `110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae` |
| predecessor campaign module | `83db9b24f88e7ad48ba21726f7905b2ba7a00638e681ff40d8fdcf0c728edd02` |
| predecessor campaign schedule | `ddbc7a089a636d09f97e68e67da7f534ecca6c88d6b7dbc8bf78080ce7400e25` |
| predecessor campaign tests | `f7b51987952baddccc254bce70aa22b7d1a1179b21f3d1e4169fdad2963b9cce` |
| predecessor campaign README | `fe4fd2db322674a9f1773016f9c7aae2e618670cc449d1138809570cc306a7f5` |
| observed-state v3 module | `3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6` |
| observed-state v3 protocol file | `d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716` |
| observed-state v3 tests | `55bfbf5a4b252804f4e3b2e91100c83b8ff98bffbf10eec5bdd3bd83d96ad66c` |
| observed-state v3 README | `4368b69641138bd5701a9fb4d6be382e23d6b02e0e756192fb9c12b124e12e23` |

The observed-state protocol semantic SHA-256 is
`33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c`.
Independent audit reproduced 253/253 tests from the repository and an
unrelated temporary working directory. Acceptance is explicitly limited to
the narrow offline, permanently nonadmitting role and does not relax any
provenance or downstream gate.

The untouched predecessor schedule semantic SHA-256 is
`fb984becfc5608922cd4acffd7e3e3bdf997022935f816acad221ec32dcd0383`.

## Closed validation

`USEFFRCampaignRestartV2.jl`:

- requires exact root, section, and row key sets and exact field types;
- recomputes the weekday/holiday calendar, effective-date chain, all 115
  slots, UTC/local clocks, transaction IDs, paths, predecessors, and queries;
- rejects any opened gate, broader claim, imported predecessor coverage,
  outcome-driven amendment, retry/backfill rule, or terminal revision slot;
- verifies every bound source file's exact byte SHA-256; and
- recomputes the schedule's typed, length-aware semantic self-hash after
  removing only `artifact.content_sha256`.

Run the hermetic test suite from any working directory:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/effr/campaign_restart_v2/test_effr_campaign_restart_v2.jl
```

Check both Julia sources with Runic 1.7.0:

```bash
runic --check \
  scripts/us/forecasting/vintages/effr/campaign_restart_v2/USEFFRCampaignRestartV2.jl \
  scripts/us/forecasting/vintages/effr/campaign_restart_v2/test_effr_campaign_restart_v2.jl
```

The tests cover the full calendar and post-holiday chain, terminal cutoff,
Madrid DST boundary, exact IDs/paths/predecessors/queries, all permanent
gates, amendment and maximum-coverage semantics, exact source tampering,
TOML failures, unknown/missing fields, type confusion, and slot-level
mutations. Passing tests establish only the offline contract mechanics.
