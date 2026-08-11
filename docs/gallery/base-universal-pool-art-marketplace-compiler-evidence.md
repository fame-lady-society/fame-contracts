---
chain: base
status: compiler-upgrade-qualified-production-broadcast-not-authorized
contracts: UniversalPoolArtMarketplace + FameMarketplaceCheckout
solidity: 0.8.36
foundry_profile: universal_marketplace
---

# Marketplace Solidity 0.8.36 evidence

This record covers the compiler-specific portion of the production acceptance
gate. It is not broadcast authorization. The scoped local, invariant, Base-fork,
provider-cap, selected-exit, and manifest recovery campaigns passed with no
required skip; production submission still requires separate authorization and
a final stable-compiler recheck.

## Pinned build

The `universal_marketplace` profile pins:

- Solidity `0.8.36`;
- EVM target `cancun`;
- optimizer enabled with 200 runs;
- legacy code generation (`via_ir = false`); and
- storage layout in the compiler artifact output.

Every release command must set `FOUNDRY_PROFILE=universal_marketplace`.
`js/release/marketplace-release-evidence.mjs` rejects artifacts produced by a
different compiler, EVM target, optimizer configuration, or pipeline. It hashes
the canonical ABI, storage layout, creation bytecode, and runtime bytecode, and
enforces EIP-170 and EIP-3860 only for the two deployable release contracts.

## Intervening release and known-bug review

Official Solidity release notes from `0.8.29` through `0.8.36` were reviewed:

- `0.8.29` added experimental EOF and custom storage layouts. Neither is used.
- `0.8.30` changed the compiler's default EVM target from Cancun to Prague. The
  explicit Cancun pin prevents that default from changing release bytecode.
- `0.8.31` introduced deprecation warnings for features scheduled for removal
  in `0.9.0`, including virtual modifiers. The warnings emitted here originate
  in pinned Solady and inherited DN404 base code; the feature remains supported
  by `0.8.36` and does not change this release's ABI, storage layout, or selected
  pipeline.
- `0.8.32` fixed an exotic storage-array write bug; `0.8.33` immediately fixed
  a compile-time regression introduced in `0.8.32`.
- `0.8.34` fixed a transient-storage clearing bug limited to the IR pipeline.
  This release explicitly keeps `via_ir = false` and does not use the affected
  transient-delete pattern.
- `0.8.35` added experimental features that require explicit opt-in. None are
  enabled by this profile.
- `0.8.36` fixed the inheritance-order warning corruption and mutually
  recursive Yul spilling bugs. The official current `bugs_by_version.json`
  entry for released `0.8.36` contains no listed known bug.

Sources:

- <https://www.soliditylang.org/blog/category/releases/>
- <https://www.soliditylang.org/blog/2026/07/09/solidity-0.8.36-release-announcement/>
- <https://raw.githubusercontent.com/argotorg/solidity/develop/docs/bugs_by_version.json>

Immediately before any production broadcast, recheck the official stable
release list. A newer stable compiler is a no-go until the pin is deliberately
updated and this complete gate is rerun.

## Build-warning disposition

The `0.8.36` scoped build completes successfully. Its compiler warnings are:

- virtual-modifier deprecations in pinned Solady and inherited DN404 base code,
  scheduled for Solidity `0.9.0`; accepted for this `0.8.36` release and not
  suppressed;
- two existing unused locals in `CreatorArtistMagic`, outside the deployable
  release targets and unchanged by the compiler upgrade; and
- existing Foundry lint notices for bounded casts and deadline timestamp use.
  The marketplace guards fee values before each `uint96` cast, caps provider
  units before the `uint32` casts, and intentionally uses the transaction
  deadline supplied by the route.

No new warning indicates changed marketplace or checkout runtime behavior.

## Compiler delta from 0.8.28

The machine-readable baseline is
`docs/gallery/evidence/base-universal-pool-art-marketplace-solc-0.8.28-baseline.json`.
It was rebuilt from clean source commit
`98a8853997e07940d33f121ac52eb88dee806be4` with the same Cancun, optimizer,
non-IR, and storage-layout-output settings.

| Contract | ABI | Storage layout | Initcode | Runtime |
|---|---:|---:|---:|---:|
| `UniversalPoolArtMarketplace` | unchanged | unchanged | 17,149 → 17,149 bytes (0) | 14,986 → 14,986 bytes (0) |
| `FameMarketplaceCheckout` | unchanged | unchanged | 18,007 → 18,007 bytes (0) | 16,225 → 16,225 bytes (0) |

The initcode measurements include both creation bytecode and ABI-encoded
constructor arguments: 224 bytes for `UniversalPoolArtMarketplace` and 160
bytes for `FameMarketplaceCheckout`. The corresponding raw creation bytecode
sizes are 16,925 and 17,847 bytes.

Creation and runtime hashes change because Solidity embeds compiler metadata;
the target gate records the exact hashes rather than assuming byte-for-byte
stability across compiler versions.

## Solidity 0.8.36 size result

| Contract | Runtime / EIP-170 | Runtime headroom | Initcode / EIP-3860 | Initcode headroom |
|---|---:|---:|---:|---:|
| `UniversalPoolArtMarketplace` | 14,986 / 24,576 bytes | 9,590 bytes | 17,149 / 49,152 bytes | 32,003 bytes |
| `FameMarketplaceCheckout` | 16,225 / 24,576 bytes | 8,351 bytes | 18,007 / 49,152 bytes | 31,145 bytes |

The check reads only these two artifact paths. Oversized local-only Forge
scripts cannot change its exit status; the full repository build remains a
separate regression gate.

## Commands

```sh
FOUNDRY_PROFILE=universal_marketplace forge build \
  src/UniversalPoolArtMarketplace.sol src/FameMarketplaceCheckout.sol --force

npm run marketplace:size
npm run marketplace:evidence:test
```

After the release commit and complete gas/test campaigns, create the final
review artifact with the exact source commit and gas evidence:

```sh
FOUNDRY_PROFILE=universal_marketplace node \
  js/release/marketplace-release-evidence.mjs write \
  --baseline docs/gallery/evidence/base-universal-pool-art-marketplace-solc-0.8.28-baseline.json \
  --gas-evidence docs/gallery/evidence/base-universal-pool-art-marketplace-gas-evidence.json \
  --output docs/gallery/evidence/base-universal-pool-art-marketplace-solc-0.8.36-release.json
```
