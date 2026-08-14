### 2026-08-08 — synthetic authenticated-evidence/common-origin v4 kernel (permanent `CANNOT_RUN`)

Implemented an isolated, synthetic-only v4 schema/validation kernel at
`scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/`.
This entry describes a design prototype, not an acquired or admitted origin.
No raw data, live network, trust anchor, key, signature, certificate, timestamp
request/response, model, truth, score, inventory entry, or production work-log
state was created or touched. No private key was generated and no TSA was
contacted. Accepted v3 bytes remain unchanged.

The v4 representation fixes the one-object-per-leaf limitation by defining one
parent-level raw-object catalog and ordered, set-valued profile selections.
Catalog/provider subjects and replica/storage identities are globally unique
and counted once; requested and final HTTPS URIs may repeat across objects but
are both bound and must be equal under the exact no-redirect policy. Method,
exact body-or-query hash and request ordinal define different request subjects;
GET binds the SHA-256 of empty bytes. The provider-object subject binds that
request to response version/media/hash/size.
The source-provider version belongs once to the catalog object; each replica
binds the enclosing catalog-object subject and has a distinct storage-object
version. The same catalog object may be selected by many profiles, but a
profile cannot repeat an object within its own ordered set. The synthetic
demonstration binds the eight BEA fixed-assets profiles to three XLSX section
workbooks in a 3/3/2 mapping and binds all six BLS CPS profiles to the same
ordered three-JSON-chunk history. The BLS chunks share one synthetic POST URI
but have distinct body hashes and ordinals 1/2/3. Six unique catalog objects
therefore support fourteen profiles and twenty-six selection references.
Checked accounting limits each object to 512 MiB and the catalog to 2 GiB.
This demonstrates the required semantics but does not supply the complete
107-profile closure.

The module implements a domain-separated typed-length canonical subject:
fixed v4 domain, separately tagged/length-bound subject kind, tagged nodes,
unsigned 64-bit big-endian payload lengths, sorted string map keys, bound list
count/order, signed 64-bit big-endian integer encoding, and rejection of floats
and unknown types. Each selection also carries a closed profile projection and
a rederived subject binding the profile, ordered objects and interpretation.
The distinct BEA table/sheet and BLS series/formula/coverage fields use explicit
unresolved-production sentinels; swapping and restamping two descriptors is
rejected and real production bindings remain a blocker. The parent subject is
the canonical hash of the entire closed parent, including every trust table,
release pin, gate, status and claim field. Trust-bootstrap, key-registry,
authenticated-decision, RFC 3161, custody, verifier-release, qualified-leaf,
origin-closure and retention schemas are present only as closed synthetic
contracts. The validator rejects inserted anchors, keys, signatures, timestamp
material, decisions, true gates, request/provider/catalog collisions,
incorrect replica independence, projection/selection ambiguity, byte overflow,
partial parent subjects and stale/fabricated results.

An independent audit rejected the first frozen v4 candidate because exported
or module-qualified callers could mutate persistent validation-policy arrays,
sets, dictionaries and canonical-domain bytes, then restamp data under the
altered in-process policy. The candidate was reopened. All persistent policy
collections are now immutable tuples or tuples of immutable named tuples; the
canonical domain and matcher patterns are strings; canonical bytes and compiled
matcher state are constructed locally; and blocker vectors and projection
tables returned to callers are fresh. Exact regressions prove that emptying one
returned blocker list cannot empty the next, reversing the persistent BLS
object order has no mutation method, replacing a BEA binding with fictitious
`FAAt999` has no mutation method and a coordinated fixture restamp is rejected,
and neither the domain string nor a previously returned canonical byte vector
can change later subjects. Compiled regular expressions were also removed from
persistent state to close the same mutation class beyond the four reported
attacks.

An early bootstrap audit found that top-level `using OpenSSL_jll` would execute
package/JLL initialization before the claimed pins were authenticated. The
import was removed. The kernel is stdlib-only (`SHA`, `TOML`) and neither loads
nor opens the crypto package/products. Its isolated machine-generated
Project/Manifest directly resolves `OpenSSL_jll` 3.5.7+0, but the package tree,
Apple Silicon artifact tree and product hashes are explicitly opaque successor
declarations. They are not a prevalidated runtime and do not establish FIPS
conformance. Julia documents that code loading depends on the environment
stack and depot search, while preferences and compiled caches can influence
loaded code; closing only Project/Manifest is insufficient
([Julia code loading](https://docs.julialang.org/en/v1/manual/code-loading/),
[environment/depot variables](https://docs.julialang.org/en/v1/manual/environment-variables/),
[system images](https://docs.julialang.org/en/v1/devdocs/sysimg/),
[Pkg Project/Manifest files](https://pkgdocs.julialang.org/v1/toml-files/)).

The minimum production successor remains: independently bootstrapped,
out-of-evidence owner and validator roots; distinct organizational identities
and keys; signed role/validity/revocation/rotation registry; detached
ECDSA-P256/SHA-256 signatures over reconstructed canonical subjects; archived
and offline-replayed RFC 3161 evidence including request/response imprint,
nonce, policy, TSA EKU/path/signature/revocation/time checks; independently
signed and timestamped verifier-release manifest; closed Julia executable,
sysimage, load path, depot, preferences, caches and complete JLL/product/config
closure; physical raw/replica/path/durability/custody replay; qualified leaf
verifiers; full ordered 107-profile closure; and frozen EFFR supersession.
NIST [FIPS 186-5](https://csrc.nist.gov/pubs/fips/186-5/final) provides the
digital-signature standard and [SP 800-57 Part 1 Rev. 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)
provides key-management guidance. [RFC 3161](https://www.rfc-editor.org/info/rfc3161/)
requires correspondence between the request and returned token plus token
signature validation. OpenSSL's official [`ts` documentation](https://docs.openssl.org/3.5/man1/openssl-ts/)
describes an implementable verification route, but no route is executed or
qualified here. V4 claims conformance to none of these standards.

Exact current blockers, in result order, are:

1. `production_trust_bootstrap_absent`
2. `production_role_keys_absent`
3. `authenticated_signature_validation_absent`
4. `rfc3161_timestamp_evidence_absent`
5. `production_profile_projection_bindings_absent`
6. `qualified_leaf_verifiers_absent`
7. `complete_107_profile_parent_absent`
8. `effr_supersession_unfrozen`
9. `physical_raw_and_replica_evidence_absent`
10. `external_custody_domain_evidence_absent`
11. `verifier_release_authentication_absent`
12. `validator_source_and_runtime_bootstrap_unauthenticated`
13. `julia_executable_sysimage_depot_preferences_cache_not_closed`
14. `jll_transitive_dependency_closure_not_independently_authenticated`

The exact maximum claim is
`SYNTHETIC_SCHEMA_AND_FAIL_CLOSED_LOGIC_ONLY_NO_AUTHENTICATED_ORIGIN`.
An author-controlled coordinated restamp changes the canonical subject but
cannot create externally authenticated evidence and remains `CANNOT_RUN`.
GO only as an inert schema/test prototype; NO-GO for origin admission,
forecast sealing, forecasting, truth access, scoring, or production trust.

Verification passed 257/257 tests under Julia 1.10.3 with
`--startup-file=no --check-bounds=yes --depwarn=error`, once from the repository
root and once from unrelated CWD `/private/tmp` using absolute project/script
paths. Runic 1.7.0 reported no formatting diff; trailing-whitespace/final-newline
checks passed. Tests confirm that `OpenSSL_jll` is not loaded. Exact SHA-256:

- module: `0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e`
- policy: `84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834`
- Project: `bce609ef93f95f71274999edbcb1616a353d3fa274fc058506c53ba884c17a96`
- Manifest: `84363c46a921645ebbffa98c479916400741c549bb55dd0d6db8ec4a1c24d1d8`
- README: `0a216df9bf656a8c20d968e4fe65461841fb5b5ea12bc85f5746aaf8d69344c3`
- tests: `df454705962596fe0b6472eb1246133cc768bca4b8a2ea5ca52a5047cb154e14`
- authenticated-decision schema: `8c27844f8d8404ef671576c2cd789a32a1f400f49fc0fbbfc4f15c15e3d54943`
- parent schema: `cc92052fb16906a8d8278029f8d7e6ce203cd04df62cf5837758e96b6891b195`
- custody-operator schema: `8baf14bebe0ac537f4b4a910518c445ef2c8253d74845aaa2a559b9c73e1d914`
- independent-result schema: `6b5c2add09cc00f025abc7ceb9f215a825ad5a9161e261e30c76b43d64f2db40`
- origin-closure schema: `df926ef5ad27736bf4d3a99b4feaf21d019a420afbe7a9e86118d5ff3f685967`
- profile-selection schema: `e7307257315a13a8a45cdf988a24dad29899e7f908d601f34b4c3b6599380987`
- qualified-leaf schema: `51e24954dc6e1c1befa307e00868e71d462dbf6b334d429193f2701b086d750f`
- raw-catalog schema: `df534859a8f8293a9428fe3b7e2196e1194b369015b2e6508be7b991e3be9030`
- retention schema: `c0aee6b8c2a1123ae929afb39cbdad51d70b4335aecb0af6b9711131fb331ef9`
- RFC 3161 schema: `5bbab2c422461d07488482847fb200b6da316da2c7c8d9dfcd4d6788455f13b2`
- trust-bootstrap schema: `4153c35aa9415ac0839f7c5fe177cfffadf772b2739cb311b6f115e875df9581`
- key-registry schema: `b40536feeff179ce469b80e23d0e19e76202119f834c1fb969e254b7f74a31d9`
- verifier-release schema: `4c253f6d4244d3355ae3e75b3eddc016daa1c2aed930262d57361b6cced40d62`

The exact synthetic fixture result remains `CANNOT_RUN` with six catalog
objects, fourteen profile selections, twenty-six selection references, 6,021
unique synthetic bytes, the fourteen blockers above and parent subject
`c784b7aff050da1a37c7f12acccee0e0dfa0b5a2b3ff847ba0790e0f677eda4f`.
For reproducible structural comparison only, the v4 `toml-document` canonical
semantic hashes are:

- Manifest: `992dbaed5fa948b7bd4617f3bef5cdac032a1bd408fc6ba814838ad1afe7901e`
- Project: `96f9e8cda5ffda65df658653e4afcd54d650c82614507fe31c922ec304dd549c`
- authenticated-decision schema: `408a9633c8904bdd51e350d56cc91fda9ef3506697ddab362a160d0cce814001`
- policy: `6f57728fb4db33786c06dba911c17f9dba60e24320aecf4aaa1945099fcb85d4`
- parent schema: `9d78983f3749978b8f8637b64dbacba4bab39d2788795ebfaa03845446714043`
- custody-operator schema: `766fc2301f3bcbf09c21a627c37a545262e692d7efa955acc5f3bcae791f134a`
- independent-result schema: `bf3e5b464120703ac5af83b856afc670573409e6f593f6486c760cdfcae4e58a`
- origin-closure schema: `f2f4bd6f4b8ceb333d7c8b26ce68afad46dc8dd0edc237115db4cd660a651e71`
- profile-selection schema: `15858a236210e99abc7968a35a1bff781ea8e22f356ed1a674a338e838cf2a6c`
- qualified-leaf schema: `cf6be8e058dc88c94aac31fbb014b316c4fc553096e592f3b7b08843bcf30ef2`
- raw-catalog schema: `a38e048795d69fcee0bbe8ac6413a052d5440a198880b1af84a6c629862f2639`
- retention schema: `ff4109d5ffa180ff591e8e51976f59ac8c154c8d12943a54995d656bfa2d4752`
- RFC 3161 schema: `155b31b0dfd3afe9f48df52d4adda323d56fe475dc47fe8398da3d9ab6f6ede5`
- trust-bootstrap schema: `5b18313b22e55836b3c4bc36c34c6a888f7769226047c23a64fcd726cd82439a`
- key-registry schema: `6bbce06722537048c98bc42d2cf335cb614c7586a7f4da12c544563d81c4ba30`
- verifier-release schema: `944d12d4d8982bfcdc4deb1656637409c436a191931067e26e340972352a420b`

These physical and semantic hashes are local, unauthenticated fixity
assertions; they do not lift any blocker or establish provenance.

The accepted v3 module/policy/parent/leaf/custody/tests/README SHA-256 values
remain respectively `b82c6ab5c2830b8f23ec92971ed3930790f60fd3d09e0beaf4c98a66938cdf57`,
`1cdd7834e76fb414761c41470319dfeded97f5dd5e9f0cf420893717d5f2d8ce`,
`cf4060554a6c53de079d728c2a2ac179309e9a7b888edc3bfa0a931ced5442a2`,
`6bcd6f26efba67bb92053dabdc20c08f6b36d9c3569a92a5e980c5117265a4cd`,
`94eb2a1bdbd1346b4918d63bdf1befcf506a8b6d39c6eeaa1b50e87eb2c79598`,
`d8a5d47ee1acaf319d5761c07fd0f7cc9d84f165f5367c6eeb4cbd074c76ba7a`,
and `991039f5e73a9aa5b3795915f9939247ca04757c9029784d7bdfc93e35b0b07d`.
