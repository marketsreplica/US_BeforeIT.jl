# Authenticated-evidence/common-origin v4 synthetic kernel

This isolated directory is a synthetic design-and-validation kernel for a
separately versioned successor to `common_origin_acquisition_v3`. It resolves
the v3 representation defect for shared raw objects and set-valued selections,
and it specifies the authenticated trust boundary that a production successor
would need. It does **not** implement or exercise that trust boundary.

The exact v4 candidate is permanently `CANNOT_RUN`. No input can make it return
`READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED`. It contains no real trust anchor,
public or private key, signature, certificate, timestamp request or response,
physical raw object, qualified leaf result, model, truth, or score. It never
uses the network, invokes a crypto process, generates a key, signs a subject,
contacts a TSA, opens raw data, or mutates inventory or the project work log.
All fixtures are in-memory synthetic metadata.

## Implemented structural kernel

`USCommonOriginAcquisitionV4.jl` provides a stdlib-only validator and these
public operations:

- `canonical_subject_bytes` and `canonical_subject_sha256` create a
  domain-separated typed-length subject. Every node carries a type tag and
  unsigned 64-bit big-endian payload length; maps sort string keys, lists bind
  their count and order, integers are signed 64-bit big-endian two's
  complement, and floating-point or unknown values are rejected.
- `validate_raw_object_catalog` validates one parent-level catalog. Raw object
  IDs and paths, and replica IDs, paths, storage-object
  versions and custody-attestation IDs are globally unique. The source-provider
  object version belongs once to its catalog object. Requested and final HTTPS
  URIs may repeat across objects, but both are bound and must be equal under the
  exact no-redirect policy. Request identity also binds source, method, exact
  body-or-query hash and ordinal; GET binds the SHA-256 of empty bytes. A
  globally unique rederived provider-object subject then binds that request
  subject to response version, media type, hash and size.
  Each replica binds the canonical catalog-object subject (including the
  provider-object subject) and has equal hash/size plus a distinct domain,
  backend, storage-object version, custody key and attestation. An operator key
  may attest multiple different raw objects; independence is required within
  each raw object's replica pair, not globally across the corpus.
- `validate_profile_selections` validates ordered, nonempty sets of catalog
  object IDs. Reuse across profiles is allowed and does not duplicate catalog
  storage accounting. Duplicate IDs within one selection and unresolved IDs
  are rejected. Each row also carries a closed projection descriptor and a
  rederived subject binding profile ID, ordered object set and interpretation.
  The synthetic descriptors distinguish BEA section/table/sheet/line/year/unit
  and BLS series/formula/coverage/no-gap/unit semantics. Unresolved production
  selectors are explicit sentinels and therefore remain a blocker.
- `validate_parent`, `verify_parent`, and `validate_result` close the synthetic
  sentinel structure and replay the parent. The advertised parent subject is
  the canonical hash of the entire closed parent table—not a hand-selected
  projection—so all trust tables, release pins, limits, gates and claim/status
  fields are bound. The only result is `CANNOT_RUN` with all action and
  authenticated-evidence counts zero.
- `declared_successor_crypto_runtime` exposes opaque design pins without
  importing, resolving, opening, or validating the declared crypto package or
  products.

All persistent validation-policy collections are immutable tuples or tuples of
immutable named tuples. The canonical domain and validation patterns are held
as strings; canonical-domain bytes and compiled regular expressions are made
locally for each call. Public operations return fresh mutable blocker vectors
and projection tables, so a caller may alter its own result without changing
subsequent validation policy. Regression tests exercise the previously
possible empty-blocker, reversed-BLS-order, fictitious-`FAAt999`, and
canonical-domain mutation attacks and then revalidate clean state.

The demonstration geometry is deliberate:

- the eight BEA fixed-assets profiles bind to three section workbooks in a
  3/3/2 profile-to-object mapping; and
- all six BLS CPS profiles bind to the same ordered three-object history set,
  whose three objects share one synthetic POST URI but bind distinct request
  body hashes and ordinals 1/2/3, demonstrating a selected multi-chunk history
  rather than a fabricated one-object leaf.

The fixed-assets objects use the closed XLSX media type, and the API chunks use
JSON. The schema also admits exact ZIP, CSV, TSV and plain-text types needed by
other source/catalog artifacts; it does not treat a URL alone as an object
identity.

The catalog therefore contains six unique objects, while the fourteen profile
selections contain twenty-six object references. Storage bytes are summed over
the six objects once using checked integer addition. Each synthetic object is
bounded at 512 MiB and the catalog at 2 GiB; declarations exceeding either
limit or overflowing `Int` are rejected. This is not the complete 107-profile
origin.

## Why OpenSSL is declared but not loaded

The isolated `Project.toml` directly constrains `OpenSSL_jll = "=3.5.7"`, and
the machine-generated `Manifest.toml` resolves `3.5.7+0` plus its exact package
tree and dependency graph. The policy also records the observed Apple Silicon
artifact and product hashes. These are **opaque, unauthenticated successor
declarations**, not a trusted runtime and not evidence of FIPS conformance.

Loading `OpenSSL_jll` before checking the effective Julia executable, sysimage,
load path, depot, preferences, compiled caches, package entrypoint, transitive
JLL source trees, artifact selection and product bytes would execute code on
the wrong side of the bootstrap boundary. V4 therefore does not import it at
all. Julia's own documentation explains that package identity depends on the
environment stack and that package paths are searched through depot roots;
preferences can also affect compilation and cached package images. A
Project/Manifest pair improves reproducibility but is not, by itself, an
authenticated release. See the official Julia documentation for
[code loading](https://docs.julialang.org/en/v1/manual/code-loading/),
[environment/depot behavior](https://docs.julialang.org/en/v1/manual/environment-variables/),
[system images](https://docs.julialang.org/en/v1/devdocs/sysimg/), and
[Project/Manifest semantics](https://pkgdocs.julialang.org/v1/toml-files/).

## Minimum production trust stack (not implemented)

A production successor should be a new version, not a relaxation of v4. The
minimum practical design is:

1. Establish owner and independent-validator bootstrap fingerprints outside
   the evidence tree through a documented ceremony. Keep private keys outside
   the repository and preferably in independently administered signing
   services or hardware. The evidence may identify keys but must never define
   its own roots of trust.
2. Use distinct owner and validator organizations and keys. A signed key
   registry must bind role, P-256 public key/SPKI identity, validity interval,
   registry epoch, revocation state, rotation predecessor/successor, and
   compromise handling. Verification evaluates the registry and revocation
   state applicable to the decision time. NIST
   [FIPS 186-5](https://csrc.nist.gov/pubs/fips/186-5/final) specifies digital
   signature algorithms used for signatory authentication and modification
   detection; [SP 800-57 Part 1 Rev. 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)
   supplies the key-management boundary. V4 claims conformance to neither.
3. Reconstruct, rather than trust, the exact domain-separated typed-length
   subject and verify detached `ECDSA-P256/SHA-256` owner and validator
   signatures against the out-of-evidence bootstrap and signed registry.
4. Archive and independently replay an RFC 3161 request/response. Verification
   must check response status, request/response message imprint and algorithm,
   nonce, policy, TSA signer identity and timestamping EKU, signed token,
   certificate path, applicable revocation evidence, and time. RFC 3161
   requires verifying that the returned token corresponds to the request and
   validating its signature; see the
   [RFC Editor text](https://www.rfc-editor.org/info/rfc3161/). OpenSSL's
   official [`ts` documentation](https://docs.openssl.org/3.5/man1/openssl-ts/)
   is an implementable verifier option, but its exit status is useful only
   after the executable, configuration, providers, trust store and inputs are
   independently closed.
5. Authenticate a verifier-release manifest with separate owner and validator
   decisions plus RFC 3161 evidence. The subject must bind the Julia executable
   and sysimage, source, Project/Manifest, a single-entry load path, immutable
   depot layout, absence or exact bytes of preferences, disabled or
   authenticated compiled caches, all package entrypoint/tree identities,
   transitive JLL wrappers/artifacts/products, OpenSSL configuration/providers,
   and the offline replay procedure. Only after a stdlib-only pre-load gate
   validates that closure may crypto code be loaded.
6. For every raw object, independently open and validate the physical source
   request method/requested URI/final URI/redirect policy/body-or-query
   bytes/ordinal, provider response identity, and two durable replicas, exact
   bytes, sizes, inode/link/path
   constraints, provider object versions, immutable-retention evidence, and
   authenticated custody-operator decisions. Then verify exact production
   projection descriptors and qualified leaf results, the full ordered
   107-profile closure, the EFFR supersession decisions, custody, release
   authentication, and origin chronology without loading truth.

The command-line OpenSSL route is the smallest auditable implementation on the
current Julia/macOS stack because it can verify ECDSA/CMS/X.509/RFC 3161 using
an exact product. Direct `ccall` into `libcrypto` would remove process parsing
but materially enlarges the Julia ABI, ownership and error-handling surface.
A pure Julia implementation would require a separately audited standards and
X.509 stack. None is selected or qualified here.

## Threat model and claim ceiling

V4 detects schema drift, type confusion, ambiguous canonical serialization,
request/provider/catalog identity collisions, stale response bindings,
within-object replica non-independence, incorrect 3/3/2 sharing, reordered or
duplicated multi-chunk selections, swapped-and-restamped profile projections,
partial parent-subject projections, injected self-asserted trust material,
opened gates, and stale or fabricated result objects.

It does not authenticate the policy, source, runtime pins, official-source
bytes, storage providers, operators, people, organizations, keys, clocks or
timestamps. It does not inspect physical files or resist a same-user pathname
race. An author can rewrite the entire local synthetic closure and recompute
all hashes; the changed subject will be visible, but no external party vouches
for either version. Such a self-restamp remains `CANNOT_RUN`.

The maximum honest claim is exactly:

`SYNTHETIC_SCHEMA_AND_FAIL_CLOSED_LOGIC_ONLY_NO_AUTHENTICATED_ORIGIN`

This kernel is a **GO** as an inert schema/test prototype and a **NO-GO** for
origin admission, forecast sealing, forecasting, truth access, scoring, or any
claim that production trust has been established.

## Failure behavior

Unknown fields or types, non-lowercase hashes, unsafe paths, unsorted catalog
or profile rows, global identity collisions, mismatched replica bytes/sizes,
incorrect source-provider/replica subject binding, duplicate storage versions,
oversized or overflowing byte declarations, incorrect selection
membership/order, nonempty trust/key/timestamp/decision arrays, any true
operational gate, or a replay mismatch are rejected. A
structurally valid parent still returns the exact fourteen blockers and
`CANNOT_RUN`; there is no conditional ready branch.

## Verification

From the repository root:

```sh
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4 \
  scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/test_common_origin_acquisition_v4.jl
```

The same command is intended to pass from an unrelated current working
directory when the script and project are given as absolute paths. Runic 1.7.0
must report no formatting diff. The suite verifies the dependency closure
without importing `OpenSSL_jll`, the physical schema pins, canonical-subject
vectors and type/domain/order separation, shared-object and multi-chunk
geometry, global collisions, fail-closed trust sentinels, result replay, exact
zero action counts, immutable persistent policy and fresh returned containers,
and the opaque/non-loaded status of crypto declarations.

No v3 file is modified by this directory.
