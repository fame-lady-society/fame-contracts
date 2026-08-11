# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Atomic Marketplace Checkout

### FAME Route

An executable exact-input swap plan that binds funded input, ordered venue legs, leg-level output floors, a post-fee final output floor, a recipient, and an expiry.

### Marketplace Obligation

The FAME-denominated amount that must be paid for a marketplace action, distinct from the payment asset and input amount used to acquire that FAME.

### Atomic Checkout

The coordinated process that acquires FAME, satisfies a Marketplace Obligation, performs the marketplace action, and returns remaining snapshotted route-asset balances as one revertible transaction.

### Route-Asset Boon

On successful purchase or redemption, the full remaining balance of each asset in the route snapshot is paid to the caller (latent ambient plus transaction-local surplus). Assets not on that route stay until a later successful call that includes them. Finders-keepers; no owner rescue.

### Transaction-Local Surplus

The positive asset balance delta created by one settlement after the Marketplace Obligation is paid; under Route-Asset Boon it is paid together with any pre-existing balance of the same snapshotted assets.

### Society Redemption

The atomic process that exchanges selected Society NFTs and the checkout's complete FAME inventory for the caller's selected output asset, then boons residual snapshotted non-FAME route balances to the redeemer.

### Checkout Bonus

FAME already held by checkout and intentionally included in the next successful Society Redemption's all-in FAME input (and, if any FAME residue remained, subject to Route-Asset Boon). Not recoverable as administrator inventory.

## Relationships

Atomic Checkout and Society Redemption both settle as one revertible transaction. Redemption all-ins FAME (backing + Checkout Bonus). Both entrypoints apply Route-Asset Boon to snapshotted balances on success.
