# U.S. validation foundations

`USBitemporal.jl` is the first WS-1A query-layer slice. It validates the
minimum observation schema, selects only releases eligible at an exact UTC
origin, applies realtime validity intervals, fails on ambiguous latest
releases, and emits deterministic row and snapshot SHA-256 values.

Run the hermetic leakage fixtures with:

```sh
julia --project=scripts/us scripts/us/validation/test_bitemporal.jl
```

This module does not make the existing current-vintage data pseudo-real-time.
It is the fail-closed primitive that future archived source releases and
origin-manifest builders must use.

The evidence-web reseal tool and the sealed vintage-capture apparatus it
served live on the `governance-archive` branch.
