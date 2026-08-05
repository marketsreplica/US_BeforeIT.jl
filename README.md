# US BeforeIT

> An independent, U.S.-focused fork of
> [BeforeIT.jl](https://github.com/bancaditalia/BeforeIT.jl), created by
> Banca d'Italia and its contributors.
>
> This fork is maintained by
> [MarketsReplica](https://github.com/MarketsReplica). It is not an official
> Banca d'Italia project and is not endorsed by Banca d'Italia.

US BeforeIT extends the upstream agent-based macroeconomic model with:

- auditable U.S. 2024 Q4 structural and 2026 Q1 nowcast calibrations;
- updated Austrian structural, nowcast, and scenario artifacts;
- reproducible calibration, validation, forecasting, and back-test pipelines;
- a local Simulation Lab and Economy Complexity Explorer.

The initial public branch is based on upstream commit
[`060a206`](https://github.com/bancaditalia/BeforeIT.jl/commit/060a2060e99e106024ce3301c9572cfd44cd9092),
which contains BeforeIT.jl v0.6.0.

## Quick start

Install this fork directly from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/MarketsReplica/US_BeforeIT.jl")
```

Load and run the current U.S. baseline:

```julia
import BeforeIT as Bit

baseline = Bit.load_us_baseline(:nowcast)
model = Bit.Model(baseline.parameters, baseline.initial_conditions)
Bit.run!(model, 20)
```

For development:

```sh
git clone https://github.com/MarketsReplica/US_BeforeIT.jl.git
cd US_BeforeIT.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Run the web application:

```sh
julia --project=apps/web -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=apps/web apps/web/src/server.jl
```

Then open `http://127.0.0.1:8080`.

See the [U.S. pipeline guide](scripts/us/README.md), the
[web application guide](apps/web/README.md), and
[changes from upstream](CHANGES_FROM_UPSTREAM.md) for details.

## Origin, citation, and license

The original BeforeIT.jl model and implementation are the work of Aldo
Glielmo, Mitja Devetak, Adriano Meligrana, Sebastian Poledna, and other
upstream contributors. Please cite the original software paper:

```bibtex
@article{glielmo2025beforeit,
  title={BeforeIT.jl: High-Performance Agent-Based Macroeconomics Made Easy},
  author={Glielmo, Aldo and Devetak, Mitja and Meligrana, Adriano and Poledna, Sebastian},
  journal={arXiv preprint arXiv:2502.13267},
  year={2025}
}
```

Source code is distributed under the
[Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.
Datasets and third-party materials remain subject to their respective source
terms; provenance is recorded in the country pipeline and validation files.
