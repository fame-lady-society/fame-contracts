# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Atomic Marketplace Checkout

### FAME Route

An executable exact-input swap plan that binds funded input, ordered venue legs, leg-level output floors, a post-fee final output floor, a recipient, and an expiry.

### Marketplace Obligation

The FAME-denominated amount that must be paid for a marketplace action, distinct from the payment asset and input amount used to acquire that FAME.

### Atomic Checkout

The coordinated process that acquires FAME, satisfies a Marketplace Obligation, performs the marketplace action, and returns transaction-local surplus as one revertible transaction.

### Transaction-Local Surplus

The positive asset balance delta created by one Atomic Checkout after its Marketplace Obligation is paid; it belongs to that caller and excludes balances that existed before the transaction.

### Society Redemption

The atomic process that exchanges selected Society NFTs and the checkout's complete FAME inventory for the caller's selected output asset.

### Checkout Bonus

FAME already held by checkout and intentionally included in the next successful Society Redemption, rather than treated as Transaction-Local Surplus or recoverable administrator inventory.

## Relationships

An Atomic Checkout is delta-isolated and returns Transaction-Local Surplus. Society Redemption uses a deliberately different balance policy: it combines the selected NFTs' backing FAME with the Checkout Bonus and consumes the resulting FAME inventory all at once.
