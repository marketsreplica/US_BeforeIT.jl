# US BeforeIT.jl – Serverless ETL Implementation Plan

> **Status:** Draft v0.1 ‑ _open for review & edits_

## 1 Purpose

Provide a step-by-step, production-ready roadmap for ingesting U.S. economic data into BigQuery using a modern, serverless stack.  This file supersedes the initial outline in `src/data_pipelines/ETL_PIPELINE_ARCHITECTURE.md` and will evolve with feedback.

---

## 2 Target State Architecture

```
Cloud Scheduler  →  Pub/Sub  →  Cloud Run Collectors
                               ↘︎ Cloud Storage (raw)
                                ↘︎ Cloud Functions (trigger)
                                 ↘︎ Cloud Run Transformer → BigQuery (curated)
                                                          ↘︎ Validation Service
                                                          ↘︎ Materialised Views / Data Studio
```

Key design principles: serverless, IaC-driven, idempotent, least-privilege IAM, lineage & quality first, multi-env (non-prod / prod).

---

## 3 Gap Analysis (vs current draft)

| # | Area | Gap / Risk | Fix |
|---|------|------------|-----|
| G-1 | IAM | Collectors have BigQuery rights they never use | Create separate SA per service w/ least-priv.|
| G-2 | Secrets | API keys in env-vars | Use Secret Manager + Workload Identity Federation |
| G-3 | Schema evolution | No migration/version control | `schema_versions` table + CI DDL diff-check |
| G-4 | Metadata | No lineage/catalog | Integrate Data Catalog tags or OpenLineage events |
| G-5 | Monitoring | Only 2 charts | Full dashboard + alert policies (error-rate, backlog, budget) |
| G-6 | Cost control | No slot budget / retention rules | Billing budgets, slot reservations, GCS lifecycle |
| G-7 | Back-fill | Historical load not covered | One-off Dataflow or Cloud Run back-filler |
| G-8 | Idempotency | Duplicate messages on retry | Dedup keys + MERGE loaders |
| G-9 | Orchestration | Complex deps not explicit | Consider Cloud Workflows / Airflow fallback |

_(18 additional gaps captured in prior review; see Appendix A.)_

---

## 4 Architectural Decisions (ADF)

1. **Region strategy** – default `us-central1`; revisit for BEA latency.
2. **Encryption** – CMEK for GCS & BQ; VPC-SC perimeter.
3. **Metadata tooling** – GCP Data Catalog vs OpenMetadata (TBD).
4. **Orchestration** – pure Pub/Sub or add Cloud Workflows (TBD).
5. **High-freq streaming branch for FRED** – same pipeline or separate (TBD).
6. **SLOs** – propose 90 % jobs succeed < 30 m, 99 % data freshness < 6 h.

> _Decisions marked **TBD** must be finalised before Phase 2._

---

## 5 Detailed Backlog

Tasks are grouped by phase and carry unique IDs for ticketing systems.  Dependencies are implicit by ordering; parallelisable items share the same level.

### Phase 0 – Project & IAM (Week 1)

- **T-01** Create GCP projects (`etl-nonprod`, `etl-prod`) & enable APIs
- **T-02** Set Billing Budgets & alerts
- **T-10** Design SA matrix; document in `infra/iam.yaml`
- **T-11** Implement Secret Manager + WIF for external APIs
- **T-12** Enable CMEK keys & VPC-SC

### Phase 1 – Infrastructure-as-Code & CI/CD (Weeks 2-3)

- **T-20** Provision raw bucket (`gs://mr-us-raw-data`) with retention rules
- **T-21** Decide curated bucket vs direct-to-BQ; implement if chosen
- **T-30** Translate schema into version-controlled DDL files
- **T-31** Implement `schema_versions` table & CI diff job
- **T-40** Bootstrap mono-repo with linting, tests, Docker base image
- **T-41** Add GitHub Actions or Cloud Build pipelines

### Phase 2 – Collectors (Weeks 4-6)

- **T-50** BEA Collector – GDP, NIPA, I-O
- **T-51** BLS Collector – employment & wages
- **T-52** FRED Collector – monetary series (daily streaming optional)
- **T-53** Treasury Collector – fiscal CSV extracts
- **T-54** Census Collector – trade data
- **T-55** Contract tests with VCR-style recordings

### Phase 3 – Transformer & Loader (Weeks 7-8)

- **T-60** Standalone Cloud Run transformer (pandas → Parquet)
- **T-61** Implement NAICS→BeforeIT mapping (`config/sector_mapping.yaml`)
- **T-62** Time alignment & MATLAB `datenum` helper
- **T-63** Currency & scaling utilities
- **T-64** MERGE-based BigQuery loader (dedup)

### Phase 4 – Validation & Quality (Weeks 7-8, parallel)

- **T-70** Port GDP identity & sector sum checks
- **T-71** Quarantine bucket + DLQ topic for failed rows
- **T-72** Quality summary views & Looker dashboard

### Phase 5 – Orchestration, Monitoring, Alerting (Weeks 9-10)

- **T-80** YAML-defined Cloud Scheduler jobs + Pub/Sub topics
- **T-82** (Opt) Cloud Workflows DAG for collect→transform→validate
- **T-90** Comprehensive Cloud Monitoring dashboard
- **T-91** Alert policies (error, backlog, budget, slot-usage)

### Phase 6 – Back-fill, DR, Docs (Weeks 9-10)

- **T-100** Historical back-fill runner (1990-present)
- **T-101** Replay mechanism via re-queueing
- **T-110** Staging→Prod promotion gates
- **T-120** Update CONTRIBUTING & run-books

---

## 6 Timeline Snapshot

| Phase | Weeks | Deliverables |
|-------|-------|--------------|
| 0 | 1 | Projects, IAM, CMEK, budgets |
| 1 | 2-3 | IaC repo, CI/CD, schema DDL, raw bucket |
| 2 | 4-6 | All collector services + tests |
| 3 | 7-8 | Transformer, Loader, Validator MVP |
| 4 | 9-10 | Orchestration, Monitoring, Back-fill, Docs |

_Total calendar ≈ 10 weeks; assumes 2-3 FTEs._

---

## 7 Immediate Next Steps

1. Review & approve **Architectural Decisions** (Section 4).  
2. Assign owners for Phase 0 tasks T-01…T-12.  
3. Lock tooling choices (CI system, metadata, orchestrator).  
4. Begin IAM & project provisioning.

---

## Appendix A – Full Gap List (reference)

* G-10 to G-20: row-level security, rate-limit back-off, CMEK for Pub/Sub, budget enforcement, disaster-recovery strategy, PII compliance, materialised view policy, data-dictionary automation, staging env parity, SLO definition.

_(expand as needed during design review)_
