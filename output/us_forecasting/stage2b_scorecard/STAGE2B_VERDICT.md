# Stage-2b preregistered verdict

- abm_all_available_common_cells: v3 = 0.828; best non-ABM = `dsge_sw07` at 0.857 -> **v3 wins**
- abm_balanced_h12_common_cells: v3 = 0.828; best non-ABM = `dsge_sw07_median` at 0.856 -> **v3 wins**
- abm_pandemic_masked_common_cells: v3 = 0.792; best non-ABM = `univariate_ar_p1_constant` at 0.848 -> **v3 wins**

Point condition (a): v3 beats the best non-ABM column in 3 of 3 tracks -> **MET**
- abm_all_available_common_cells density: v3 weighted CRPS 1.58 vs best challenger `dsge_sw07` 1.796 (ok); v3 90% coverage 0.832 vs best challenger distance 0.005 (worse)
- abm_balanced_h12_common_cells density: v3 weighted CRPS 1.671 vs best challenger `dsge_sw07` 1.914 (ok); v3 90% coverage 0.812 vs best challenger distance 0.008 (worse)
- abm_pandemic_masked_common_cells density: v3 weighted CRPS 0.883 vs best challenger `dsge_sw07` 1.12 (ok); v3 90% coverage 0.906 vs best challenger distance 0.047 (ok)

Density condition (b): **NOT MET** in at least one track

## Verdict: point superiority holds but the density bar is **NOT MET** — the honest-success clause applies.

(DM significance per horizon: stage2b_dm_tests.csv; this verdict is invalid without it.)
