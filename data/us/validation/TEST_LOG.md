# U.S. calibration test log

Generated: `2026-08-04T00:27:13.126`

## Executed stages

| Stage | Test | Status | Seconds | Detail |
|---|---|---|---:|---|
| collect | bea | APPROVED | 5.101 |  |
| collect | fred | APPROVED | 6.811 |  |
| collect | bls_cps | APPROVED | 2.539 |  |
| collect | qcew | APPROVED | 14.177 |  |
| collect | census_susb | APPROVED | 5.057 |  |
| collect | usda | APPROVED | 1.327 |  |
| build | input_output | APPROVED | 0.923 |  |
| build | annual_nipa | APPROVED | 0.094 |  |
| build | quarterly_panel | APPROVED | 2.099 |  |
| build | sector_accounts | APPROVED | 0.698 |  |
| build | calibration_and_baselines | APPROVED | 3.127 |  |
| validate | model_contract | APPROVED | 0.336 |  |
| validate | secret_hygiene | APPROVED | 0.454 |  |
| simulation | structural_4q | APPROVED | 0.122 |  |
| simulation | nowcast_4q | APPROVED | 0.038 |  |

## Acquisition ledger

| Source | Dataset | Request | HTTP | Status | Bytes | SHA-256 | Raw path | Detail |
|---|---|---|---:|---|---:|---|---|---|
| BEA | InputOutput | table_259-2024 | 200 | APPROVED | 1089247 | `2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918` | `data/us/raw/bea/inputoutput/vintage=2026-08-04/table_259-2024/2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | InputOutput | table_262-2024 | 200 | APPROVED | 400251 | `91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8` | `data/us/raw/bea/inputoutput/vintage=2026-08-04/table_262-2024/91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T11000-A-2024 | 200 | APPROVED | 7544 | `6cecbaf30f36bf8618117042434a84321a064f7440ea3d6d97dc1e4699ecab91` | `data/us/raw/bea/nipa/vintage=2026-08-04/t11000-a-2024/6cecbaf30f36bf8618117042434a84321a064f7440ea3d6d97dc1e4699ecab91.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T20100-A-2024 | 200 | APPROVED | 13320 | `5981c20aacf6a038f67b7ae906d54a32954730ab73affa6d6c208d16009e2ae6` | `data/us/raw/bea/nipa/vintage=2026-08-04/t20100-a-2024/5981c20aacf6a038f67b7ae906d54a32954730ab73affa6d6c208d16009e2ae6.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T30100-A-2024 | 200 | APPROVED | 12726 | `88e2ad5a6b9c8daa5b5706585415569e93d70446344f9300b51e16c4c90416d9` | `data/us/raw/bea/nipa/vintage=2026-08-04/t30100-a-2024/88e2ad5a6b9c8daa5b5706585415569e93d70446344f9300b51e16c4c90416d9.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T30600-A-2024 | 200 | APPROVED | 9447 | `a63b2652d46209cb0384c3d0fefac38573f1ea792a1f871743a1adeebbb5cec8` | `data/us/raw/bea/nipa/vintage=2026-08-04/t30600-a-2024/a63b2652d46209cb0384c3d0fefac38573f1ea792a1f871743a1adeebbb5cec8.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T31200-A-2024 | 200 | APPROVED | 14294 | `bf72593f8dcccf1f40a30fa31a5f95982a3c6e7cce3c5071de1f7b01ce1eb828` | `data/us/raw/bea/nipa/vintage=2026-08-04/t31200-a-2024/bf72593f8dcccf1f40a30fa31a5f95982a3c6e7cce3c5071de1f7b01ce1eb828.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T51100-A-2024 | 200 | APPROVED | 18676 | `def1a538357384e48a0fe64daf67a607dd8d6e42c75585f83a32253104b0bce8` | `data/us/raw/bea/nipa/vintage=2026-08-04/t51100-a-2024/def1a538357384e48a0fe64daf67a607dd8d6e42c75585f83a32253104b0bce8.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T71100-A-2024 | 200 | APPROVED | 29133 | `0b9f2129d74e9120a19b71b209bb84a34c18be32718d899ec1e8af0509e3c700` | `data/us/raw/bea/nipa/vintage=2026-08-04/t71100-a-2024/0b9f2129d74e9120a19b71b209bb84a34c18be32718d899ec1e8af0509e3c700.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T10103-Q-history | 200 | APPROVED | 1777818 | `1b9d0114fb45590cdf01ba7cb3edd046c9678070aae678e6a4e9dc38915a9b48` | `data/us/raw/bea/nipa/vintage=2026-08-04/t10103-q-history/1b9d0114fb45590cdf01ba7cb3edd046c9678070aae678e6a4e9dc38915a9b48.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T10105-Q-history | 200 | APPROVED | 1896972 | `a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574` | `data/us/raw/bea/nipa/vintage=2026-08-04/t10105-q-history/a80351ce2daeccd5994caea385c6ee9f5201fa46ce0c4cab3e7fa19fc8dec574.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | NIPA | T10106-Q-history | 200 | APPROVED | 1109350 | `21c8c2207024fa70d9c941b5d40f03c00c8067125f38ed764990214fd5b9d0b2` | `data/us/raw/bea/nipa/vintage=2026-08-04/t10106-q-history/21c8c2207024fa70d9c941b5d40f03c00c8067125f38ed764990214fd5b9d0b2.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt301ESI-2024 | 200 | APPROVED | 26773 | `2d76397b0eec272a62e745f00b05365dececd259a0ba149e1701361b884811cc` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat301esi-2024/2d76397b0eec272a62e745f00b05365dececd259a0ba149e1701361b884811cc.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt304ESI-2024 | 200 | APPROVED | 26632 | `f30c0026141e1c0eb90fc0fcf25001e6929a5ab64afea47b2a6b42335dc48e31` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat304esi-2024/f30c0026141e1c0eb90fc0fcf25001e6929a5ab64afea47b2a6b42335dc48e31.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt501-2024 | 200 | APPROVED | 4357 | `050912d4dac039818c31754cc181344846a683326babc0e5ef67ad04b2702c08` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat501-2024/050912d4dac039818c31754cc181344846a683326babc0e5ef67ad04b2702c08.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt504-2024 | 200 | APPROVED | 4313 | `00597b6767063eae3a3c0048271348b2ef69f4253126578046613be89b9955d4` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat504-2024/00597b6767063eae3a3c0048271348b2ef69f4253126578046613be89b9955d4.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt701-2024 | 200 | APPROVED | 23386 | `141f2a03308c216d6d277cf3b1522d45e9c717ea5f04082e662e9abdab49c554` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat701-2024/141f2a03308c216d6d277cf3b1522d45e9c717ea5f04082e662e9abdab49c554.json` | API response credential echo redacted: BEA_API_KEY |
| BEA | FixedAssets | FAAt703-2024 | 200 | APPROVED | 23192 | `c9cf148c060b1fa64443a516e6a82f3384c3acc5f52a37fd4777d8b138af95b4` | `data/us/raw/bea/fixedassets/vintage=2026-08-04/faat703-2024/c9cf148c060b1fa64443a516e6a82f3384c3acc5f52a37fd4777d8b138af95b4.json` | API response credential echo redacted: BEA_API_KEY |
| FRED | series_metadata | A576RC1 | 200 | APPROVED | 704 | `077c674c0a7313d105fbf158384f84f29b8a8e06e4f87193179de3528b65646e` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/a576rc1/077c674c0a7313d105fbf158384f84f29b8a8e06e4f87193179de3528b65646e.json` |  |
| FRED | series_observations | A576RC1 | 200 | APPROVED | 34968 | `146684d312e941b71287095f8a04952f8b2493120e2034aba4d810df96069fcd` | `data/us/raw/fred/series_observations/vintage=2026-08-04/a576rc1/146684d312e941b71287095f8a04952f8b2493120e2034aba4d810df96069fcd.json` |  |
| FRED | series_metadata | BOGZ1FL144104005Q | 200 | APPROVED | 1205 | `093e42d62ba88818e80a11d106ada88ede20f1f6612a1f0b95f60f1837bfef15` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/bogz1fl144104005q/093e42d62ba88818e80a11d106ada88ede20f1f6612a1f0b95f60f1837bfef15.json` |  |
| FRED | series_observations | BOGZ1FL144104005Q | 200 | APPROVED | 12151 | `d088f1aa6b0f78bb0ec3ea919d07055c0d675f5f78b4765e5fee70d6bcee2044` | `data/us/raw/fred/series_observations/vintage=2026-08-04/bogz1fl144104005q/d088f1aa6b0f78bb0ec3ea919d07055c0d675f5f78b4765e5fee70d6bcee2044.json` |  |
| FRED | series_metadata | BOGZ1FL704190005Q | 200 | APPROVED | 1196 | `0d182630fb2d3c18889cc5d43511beb0f5fdbb5348227334ba99d7cab0e10e0f` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/bogz1fl704190005q/0d182630fb2d3c18889cc5d43511beb0f5fdbb5348227334ba99d7cab0e10e0f.json` |  |
| FRED | series_observations | BOGZ1FL704190005Q | 200 | APPROVED | 12163 | `f1067618d7b204fe2e94a5de409f6439a63613d8cc659d745431449cac530dc9` | `data/us/raw/fred/series_observations/vintage=2026-08-04/bogz1fl704190005q/f1067618d7b204fe2e94a5de409f6439a63613d8cc659d745431449cac530dc9.json` |  |
| FRED | series_metadata | BOGZ1FL704194005Q | 200 | APPROVED | 1207 | `53e757145214c209d4b1a8a68a74af4fb3db1dc88db94340b116fb6393fcea08` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/bogz1fl704194005q/53e757145214c209d4b1a8a68a74af4fb3db1dc88db94340b116fb6393fcea08.json` |  |
| FRED | series_observations | BOGZ1FL704194005Q | 200 | APPROVED | 12168 | `41e26fa6a26c68eb5b2142b8222947d5157d2c3c5a6ea357ea7f21843f85ef88` | `data/us/raw/fred/series_observations/vintage=2026-08-04/bogz1fl704194005q/41e26fa6a26c68eb5b2142b8222947d5157d2c3c5a6ea357ea7f21843f85ef88.json` |  |
| FRED | series_metadata | FEDFUNDS | 200 | APPROVED | 4435 | `3738bfc8c0c1a014422eaa9444a67b26ed3c36fa5aa10a972d17fecc6b2ff11a` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/fedfunds/3738bfc8c0c1a014422eaa9444a67b26ed3c36fa5aa10a972d17fecc6b2ff11a.json` |  |
| FRED | series_observations | FEDFUNDS | 200 | APPROVED | 34293 | `cc2967edf61552b131940566eb903ac6a5eccbf254b7c2dc1cd1076f89ff0cf6` | `data/us/raw/fred/series_observations/vintage=2026-08-04/fedfunds/cc2967edf61552b131940566eb903ac6a5eccbf254b7c2dc1cd1076f89ff0cf6.json` |  |
| FRED | series_metadata | FGTCMDODNS | 200 | APPROVED | 1195 | `7eca488f58109b94b5e711b7d659491d1da10172c3ddf23dfedad1d6fe32a62a` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/fgtcmdodns/7eca488f58109b94b5e711b7d659491d1da10172c3ddf23dfedad1d6fe32a62a.json` |  |
| FRED | series_observations | FGTCMDODNS | 200 | APPROVED | 12139 | `cb200ab9aec8a3f3b58c92b361c5fabdbae5869359de2699bce5446c6d1b630a` | `data/us/raw/fred/series_observations/vintage=2026-08-04/fgtcmdodns/cb200ab9aec8a3f3b58c92b361c5fabdbae5869359de2699bce5446c6d1b630a.json` |  |
| FRED | series_metadata | HNOCDAQ027S | 200 | APPROVED | 1213 | `d85621bc04097aed02dc4bc02488e52a720c757e68cb539992c0a5b0b2e2de99` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/hnocdaq027s/d85621bc04097aed02dc4bc02488e52a720c757e68cb539992c0a5b0b2e2de99.json` |  |
| FRED | series_observations | HNOCDAQ027S | 200 | APPROVED | 12113 | `889ad752b9aba68b8afca78790f797ce5438663d980ca5b0eaa7bcdecd0d6d34` | `data/us/raw/fred/series_observations/vintage=2026-08-04/hnocdaq027s/889ad752b9aba68b8afca78790f797ce5438663d980ca5b0eaa7bcdecd0d6d34.json` |  |
| FRED | series_metadata | NCBCDTQ027S | 200 | APPROVED | 1207 | `9ec570c9a3ca8b39a7767ae9f40410b014255d14b0d705b6fcf1a802ad3596ab` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/ncbcdtq027s/9ec570c9a3ca8b39a7767ae9f40410b014255d14b0d705b6fcf1a802ad3596ab.json` |  |
| FRED | series_observations | NCBCDTQ027S | 200 | APPROVED | 12003 | `ea9ed37f79adc070113e3fbf4f039d1aad82ccd0a298e902ea74e7ede5597f5f` | `data/us/raw/fred/series_observations/vintage=2026-08-04/ncbcdtq027s/ea9ed37f79adc070113e3fbf4f039d1aad82ccd0a298e902ea74e7ede5597f5f.json` |  |
| FRED | series_metadata | NNBCDAQ027S | 200 | APPROVED | 1209 | `1fcc8fa72e0ee93769ab04efaaba662b2a4277863592c4c56b03c7d05611a10c` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/nnbcdaq027s/1fcc8fa72e0ee93769ab04efaaba662b2a4277863592c4c56b03c7d05611a10c.json` |  |
| FRED | series_observations | NNBCDAQ027S | 200 | APPROVED | 12009 | `ba801ba44a1320f4da9e9952152cfc1f12b8a83bdd19b5fa7c6b599e4b35e5f0` | `data/us/raw/fred/series_observations/vintage=2026-08-04/nnbcdaq027s/ba801ba44a1320f4da9e9952152cfc1f12b8a83bdd19b5fa7c6b599e4b35e5f0.json` |  |
| FRED | series_metadata | SLGTCMDODNS | 200 | APPROVED | 1205 | `861db55d9a4c2a37f678a5e2a190fd5aba6160ca5e47a09b9846edec37055a9f` | `data/us/raw/fred/series_metadata/vintage=2026-08-04/slgtcmdodns/861db55d9a4c2a37f678a5e2a190fd5aba6160ca5e47a09b9846edec37055a9f.json` |  |
| FRED | series_observations | SLGTCMDODNS | 200 | APPROVED | 12076 | `158afd731d1d353c3f1e0bb7bfa2d63177ce4aa2c5638b4b9a27058f924d1d6c` | `data/us/raw/fred/series_observations/vintage=2026-08-04/slgtcmdodns/158afd731d1d353c3f1e0bb7bfa2d63177ce4aa2c5638b4b9a27058f924d1d6c.json` |  |
| BLS | Public Data API | registered-key-health | 200 | APPROVED | 1133 | `f590646e93ea615778230c061c78c8c666f2c130f54b5f9d5885efe6857fde50` | `data/us/raw/bls/public-data-api/vintage=2026-08-04/registered-key-health/f590646e93ea615778230c061c78c8c666f2c130f54b5f9d5885efe6857fde50.json` |  |
| BLS | CPS | 1996-2005-registered | 200 | APPROVED | 63165 | `15baa5589af0e5f1f7264e65a176ab95cf7f77a272f3b55739b0685a96afff72` | `data/us/raw/bls/cps/vintage=2026-08-04/1996-2005-registered/15baa5589af0e5f1f7264e65a176ab95cf7f77a272f3b55739b0685a96afff72.json` |  |
| BLS | CPS | 2006-2015-registered | 200 | APPROVED | 64455 | `9a23dd39fbe48fcc24768a335e74997602ffeda76db8984a6904b9e1ae1428d2` | `data/us/raw/bls/cps/vintage=2026-08-04/2006-2015-registered/9a23dd39fbe48fcc24768a335e74997602ffeda76db8984a6904b9e1ae1428d2.json` |  |
| BLS | CPS | 2016-2025-registered | 200 | APPROVED | 64882 | `ed6c3c92c4b2039b1f23f842958b2c4f4b7deb3fd39dcb0dd54338890ad1b2e6` | `data/us/raw/bls/cps/vintage=2026-08-04/2016-2025-registered/ed6c3c92c4b2039b1f23f842958b2c4f4b7deb3fd39dcb0dd54338890ad1b2e6.json` |  |
| BLS | CPS | 2026-2026-registered | 200 | APPROVED | 4472 | `2769315744070707f786cbf00185af04ee0197c9a5ed668f1cc05844b077e25a` | `data/us/raw/bls/cps/vintage=2026-08-04/2026-2026-registered/2769315744070707f786cbf00185af04ee0197c9a5ed668f1cc05844b077e25a.json` |  |
| BLS | QCEW | 2022-annual-US-area | 200 | APPROVED | 823163 | `c45cbb64a1b1eef16bfd743510d9d02792ccad82f60e9df202c5daa3e8c5cc18` | `data/us/raw/bls/qcew/vintage=2026-08-04/2022-annual-us-area/c45cbb64a1b1eef16bfd743510d9d02792ccad82f60e9df202c5daa3e8c5cc18.csv` |  |
| BLS | QCEW | 2024-annual-US-area | 200 | APPROVED | 847197 | `48db086828a01798731242c6d3d4957f80f941afe75463a1ff7d43de774bea46` | `data/us/raw/bls/qcew/vintage=2026-08-04/2024-annual-us-area/48db086828a01798731242c6d3d4957f80f941afe75463a1ff7d43de774bea46.csv` |  |
| Census | SUSB | 2022-US-state-six-digit-NAICS | 200 | APPROVED | 56000447 | `6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513` | `data/us/raw/census/susb/vintage=2026-08-04/2022-us-state-six-digit-naics/6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513.txt` |  |
| USDA | Farms and Land in Farms | 2025-summary-containing-2024 | 200 | APPROVED | 618881 | `8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b` | `data/us/raw/usda/farms-and-land-in-farms/vintage=2026-08-04/2025-summary-containing-2024/8ed104e9df2280f1daf85ce37b20e68ced001ae23d5c3755c7c32fafecada25b.pdf` |  |

## Parameter tests

| Parameter | Check | Status | Shape | Detail |
|---|---|---|---:|---|
| intermediate_consumption | source_mapping | DUBIOUS | 68×68×1 | 68×68 column-controlled model bridge; approved raw source retained. |
| household_consumption | source_mapping | APPROVED | 68×1 | Table 259 F010. |
| fixed_capitalformation | source_mapping | APPROVED | 68×1 | Table 259 private fixed-investment uses F02E+F02N+F02R+F02S, excluding inventories. |
| exports | source_mapping | APPROVED | 68×1 | Table 259 F040. |
| compensation_employees | source_mapping | APPROVED | 68×1 | Table 259 V001. |
| operating_surplus | source_mapping | APPROVED | 68×1 | Table 259 V003. |
| government_consumption | source_mapping | APPROVED | 68×1 | Table 259 federal and state/local consumption plus gross-investment uses F06*/F07*/F10*, matching broad NIPA government demand. |
| taxes_production | source_mapping | APPROVED | 68×1 | Table 259 T00OTOP−T00OSUB. |
| taxes_products | source_mapping | DUBIOUS | 68×1 | Table 262 commodity tax valuation bridge allocated to intermediate industries; current model intentionally sets it to zero. |
| taxes_products_household | source_mapping | DUBIOUS | 1 | Table 262 commodity tax valuation bridge allocated to F010. |
| taxes_products_capitalformation | source_mapping | DUBIOUS | 1 | Table 262 commodity tax valuation bridge allocated to fixed-investment uses. |
| taxes_products_government | source_mapping | DUBIOUS | 1 | Table 262 commodity tax valuation bridge allocated to government-consumption uses. |
| gross_capitalformation_dwellings | source_mapping | DUBIOUS | 1 | Table 259 F02R plus the Table 262 valuation-bridge product tax. |
| imports | source_mapping | APPROVED | 68×1 | Table 262 commodity MCIF+MADJ. Negative CIF/FOB adjustment entries are floored at zero and positive entries are proportionally rescaled to the T017 structural control net of Other/Used commodities. |
| purchasers_to_basic_price | valuation_bridge | APPROVED | 68×1 | T013/T016 by commodity; model retail sector 4A0 aggregates supply rows 441, 445, 452, and 4A0 before division. |
| social_benefits | line_mapping | APPROVED | 1 | Government social benefits to persons. |
| mixed_income | line_mapping | APPROVED | 1 | Proprietors' income. |
| capital_taxes | line_mapping | APPROVED | 1 | Federal and state/local estate and gift taxes. |
| interest_government_debt | line_mapping | APPROVED | 1 | Consolidated government interest paid. |
| corporate_tax | line_mapping | APPROVED | 1 | Taxes on corporate income. |
| pension_benefits | line_mapping | APPROVED | 1 | Narrow Social Security definition. |
| property_income | line_mapping | DUBIOUS | 1 | Rental-income boundary plus personal interest/dividends is explicit. |
| firm_interest | line_mapping | DUBIOUS | 1 | Nonfinancial corporate plus noncorporate interest paid. |
| unemployment_benefits | line_mapping | APPROVED | 1 | Unemployment insurance benefits. |
| social_contributions | line_mapping | APPROVED | 1 | Employer plus employee/self-employed contributions. |
| government_deficit | line_mapping | APPROVED | 1 | Positive-deficit convention. |
| income_tax | line_mapping | APPROVED | 1 | Personal plus corporate tax required by code. |
| real_imports_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_gdp_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| nominal_gdp_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_exports_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_government_consumption_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_household_consumption_quarterly | saar_conversion | APPROVED | 119 | Official quarterly SAAR flow divided by four; stock series are handled separately. |
| real_fixed_capitalformation_quarterly | saar_conversion | DUBIOUS | 119 | Official quarterly SAAR levels divided by four where published; the pre-2007 history is linked from the official quantity index because T10106 exposes chained-dollar fixed-investment levels only from 2007Q1. |
| firm_debt_quarterly | stock_panel | APPROVED | 118 | Nonfinancial business debt securities and loans; liability, level |
| bank_equity_quarterly | stock_panel | APPROVED | 118 | Private depository institutions total liabilities and equity less liabilities |
| household_cash_quarterly | stock_panel | APPROVED | 118 | Households and nonprofit organizations; total currency and deposits; asset, level |
| government_debt_quarterly | stock_panel | APPROVED | 118 | Federal plus state and local debt securities and loans; liability, level |
| firm_cash_quarterly | stock_panel | APPROVED | 118 | Nonfinancial corporate and noncorporate currency and deposits; asset, level |
| population | annual_person_control | APPROVED | 1 | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| unemployed_census | annual_person_control | APPROVED | 1 | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| inactive_census | annual_person_control | APPROVED | 1 | 2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons. |
| unemployment_rate_quarterly | monthly_to_quarterly | DUBIOUS | 122 | Quarterly means of SA monthly rates; 2025Q4 includes the explicitly flagged October shutdown interpolation. |
| euribor | semantic_adapter | APPROVED | 119 | Field name is retained at the model boundary; values are quarterly means of the effective federal funds rate divided by 100. |
| nominal_wages_quarterly | monthly_saar_conversion | APPROVED | 119 | Quarterly mean of three monthly SAAR wage-and-salary disbursement levels, multiplied by 1,000 and divided by four. |
| gdp_deflator_quarterly | derived_identity | APPROVED | 119 | Nominal GDP divided by real GDP without multiplying by 100, matching the web Economic outlook ratio. |
| employees | jobs_to_people_bridge | DUBIOUS | 68×1 | QCEW payroll-job distribution scaled to the 2024 CPS employed-person annual control. |
| wages_by_sector | sector_allocation | DUBIOUS | 68×1 | Constrained allocation preserves the NIPA wage total and keeps every sector below BEA compensation. |
| firms | firm_concept_bridge | DUBIOUS | 68×1 | SUSB employer enterprises are nowcast 2022→2024 by QCEW establishments; farms and government require explicit proxies. |
| fixed_assets | sector_mapping | DUBIOUS | 68×1 | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| dwellings | sector_mapping | DUBIOUS | 68×1 | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| capital_consumption | sector_mapping | DUBIOUS | 68×1 | Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator. |
| years_num | model_contract | APPROVED | 1 | 2024 year-end structural axis. |
| quarters_num | model_contract | APPROVED | 118 | Financial-stock quarter axis 1996Q4–2026Q1. |
| firm_debt_consolidation_ratio_quarterly | model_contract | DUBIOUS | 118 | Set to 1 pending a documented consolidated/nonconsolidated bridge. |
| ea.nominal_gdp_quarterly | model_contract | APPROVED | 119 | U.S. GDP repeated for the U.S. monetary-policy block. |
| ea.real_gdp_quarterly | model_contract | APPROVED | 119 | U.S. real GDP repeated for the U.S. monetary-policy block. |
