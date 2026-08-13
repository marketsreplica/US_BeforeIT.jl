# USDA NASS Farms and Land in Farms profile v1

This isolated profile replaces the repository's manually copied 2024 farm
count with a reproducible parse of one exact, present-day USDA NASS PDF body.
It does not qualify a prospective origin or approve the farm-to-model-firm
mapping.

The exact body observed on 2026-08-08 was the official `Farms and Land in
Farms 2025 Summary`, SHA-256
`8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b`,
618,881 bytes. The body is not stored in this repository. Page 5 contains the
complete national 2018-2025 table. The parser binds the exact body, metadata,
17-page count, whole page-text hash, and the positions of all 32 year/farm/
land/size cells. It extracts 1,880,000 farms for 2024 and retains the adjacent
2025 value of 1,865,000 plus every other row. This prevents a state row,
economic-sales-class subtotal, adjacent year, or convenient duplicate number
elsewhere in the PDF from satisfying the selector.

Both pypdf 6.10.0 and 6.14.2 independently produced the same page-text hash
and fingerprint. Their Python/package/runtime closure is not authenticated;
that remains an explicit blocker. The checked-in fingerprint is a small
present-day derivative whose raw PDF remains external. It is not a publisher
signature, external timestamp, prospective capture receipt, durable replica,
or proof that these bytes preceded any forecast origin.

NASS's count uses its agricultural farm definition. It is not automatically a
BeforeIT firm, Census employer enterprise, establishment, or legal entity.
The mapping to `111CA Farms` therefore remains `DUBIOUS_NOT_APPROVED`, every
origin/model/scoring/promotion/production gate is false, and the current
maximum claim is
`EXACT_CURRENT_PDF_TABLE_MECHANICS_ONLY_NO_PROSPECTIVE_ORIGIN`.

Run the offline suite with either supported Python environment:

```sh
python3 \
  scripts/us/forecasting/vintages/usda_nass/farms_land_in_farms_profile_v1/\
test_usda_farms_land_in_farms_profile_v1.py
```

To rederive the fingerprint from the external exact body without writing it:

```sh
python3 \
  scripts/us/forecasting/vintages/usda_nass/farms_land_in_farms_profile_v1/\
USDAFarmsLandInFarmsProfileV1.py \
  --pdf /absolute/path/to/fnlo0226.pdf
```
