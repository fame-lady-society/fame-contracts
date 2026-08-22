# Society Vault Cross-Chain Migration Plan
Created: 2026-08-20
Updated: 2026-08-22

Status: **DOCUMENTATION AND PREPARATION ONLY — NO CHAIN WRITES AUTHORIZED**

## Objective

Deploy one new Society Safe at the same address on Ethereum, Base, and Polygon; initialize it as a deployer-controlled 1-of-1; immediately transition it atomically to the final 15 council signers at a 7-of-15 threshold; migrate approved vault assets, contract authority, revenue routing, and `vault.fameladysociety.eth`; and leave the old Safes in a controlled legacy state.

The approval inventory is [2026-08-20-001-ops-society-vault-asset-approval.md](2026-08-20-001-ops-society-vault-asset-approval.md). That file is the human approval surface for every known balance, NFT ID, ambiguous token, owned contract, role, and fee-recipient relationship.

## Scope

### In scope

- Destination Safe construction and same-address deployment requirements.
- Deployer-only bootstrap and immediate final owner/threshold transition preparation.
- Current owner, threshold, nonce, asset, contract-authority, and fee-route inventory.
- Unsigned transaction shapes and batch boundaries.
- Simulation, signature, execution, reconciliation, and legacy-Safe runbook.

### Deferred until required inputs are known

- Pinned released Safe version, singleton, fallback handler, factory, MultiSendCallOnly, and salt nonce.
- Predicted destination Safe address.
- Final raw calldata, Safe transaction hashes, signatures, and proposals.
- Human approval for every unchecked inventory item.

### Out of scope for this preparation step

- Broadcasting any deployment or migration transaction.
- Reading, using, printing, or storing private keys.
- Signing or proposing transactions to Safe Transaction Service.
- Treating unverified metadata labels as instructions or authenticity proof.
- Transferring Base contracts that are currently operator-owned rather than old-vault-owned. Those are separate governance decisions.

## Key findings and required corrections to the initial framing

1. **The deployment caller is not a CREATE2 input, but the bootstrap owner is.** `msg.sender` is not part of SafeProxyFactory's canonical `createProxyWithNonce` address formula. In this design, however, `0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252` is the sole owner encoded in the initializer, so that address is part of the CREATE2 input and must be identical on every chain.
2. **Use a deployer-only initializer followed by one atomic transition.** Initialize the Safe with only the FLS deployer at threshold 1. As Safe nonce 0, immediately execute one atomic `MultiSendCallOnly` transaction that adds all 15 final signers, removes the deployer, and finishes at threshold 7. Do not fund the Safe or grant it authority during the temporary 1-of-1 state.
3. **The final signer set does not determine the Safe address.** The same factory, proxy bytecode, singleton address/type, byte-for-byte one-owner initializer, and salt nonce are required. The 15 final owners live in the follow-up transaction and may be reused or changed on later chains without changing the already-defined Safe address. Protocol Kit may default to `Safe.sol` on Ethereum and `SafeL2.sol` elsewhere, producing different addresses.
4. **Do not use a chain-specific deployment.** `createChainSpecificProxyWithNonce` and Protocol Kit `deploymentType: eip155` include the chain ID and prevent address parity.
5. **Old Safes do not configure the new Safe's owners.** The deployer-controlled new Safe performs its own atomic bootstrap transaction. The old-Safe transactions move assets/control and, optionally after migration, rotate the legacy Safes to the new council.
6. **Asset movement does not redirect future Base revenue.** The old Base Safe is the fee recipient—but not owner—of the router and active/legacy marketplaces. Their current owner must execute separate `setFeeRecipient(NEW_SAFE)` calls.
7. **Polygon is token-empty but not authority-empty.** The Polygon Safe owns the verified Fameus contract at `0x3018671f3495419636519f37FfeA85BfBe3dce0f`.
8. **Ethereum has an immutable legacy receiver.** FUNKNLOVE hardcodes the old Ethereum Safe as its emergency-withdraw destination. The contract can grant the new Safe the withdrawal role, but funds will still land in the old Safe and require a second sweep.
9. **The old Ethereum Safe directly owns `vault.fameladysociety.eth`, but the parent wallet retains override authority.** The child is unwrapped, so the old Safe can update its address record and transfer the child node without the parent EOA. The EOA that owns `fameladysociety.eth`, currently `0xf11c…2A57` with reverse record `0xflick.xyz`, can still recreate or reassign the unwrapped `vault` child later.
10. **The FameLadySociety wrapper is both an asset contract and an authority target.** `0x6cF4…1574` is the wrapped FLS collection. The old Ethereum Safe is its owner, default admin, treasurer, and 5% royalty receiver. The deployed implementation inherits OpenZeppelin `Ownable2Step` and exposes no hard-transfer path. Fully sign the new Safe's acceptance/finalization batch at a reserved nonce before the old Safe starts the ownership transfer, then execute it immediately after the old-Safe handoff.
11. **The existing wrap-and-donate destination is immutable.** `0x7a27…fb9b` always mints donated wrapped NFTs to the old Safe. It must be replaced with a deployment constructed for `NEW_SAFE`, granted FLS `TREASURER_ROLE`, cut over in `fls-www` and `society-bots`, and then retired by revoking its treasurer role.
12. **The inventory is not executable calldata.** Base gained approximately `1.158 ETH` during the inventory window. Every amount, nonce, authority read, and NFT owner must be refreshed at a declared signing block.

## Current Safe baseline

| Chain | Chain ID | Old Safe | Version | Owners | Threshold | Nonce at snapshot |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Polygon | 137 | `0x560dF07ff3aB5eAE66683D6e11AbFa28f1801997` | 1.3.0 | 13 | 7 | 4 |
| Base | 8453 | `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D` | 1.3.0 | 14 | 7 | 4 |
| Ethereum | 1 | `0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF` | 1.3.0 | 14 | 7 | 32 |

These nonces are historical evidence only. Never put them into a transaction manifest without a fresh read.

## Destination signer plan

The destination membership and threshold supplied on 2026-08-21 are:

- Keep all 14 existing Base/Ethereum signer addresses.
- Add `0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db`.
- Keep threshold `7`, changing the configuration from 7-of-14 to 7-of-15.

Base and Ethereum have the same 14-member set but expose it in different linked-list orders. Polygon currently has 13 owners and a different membership, so it cannot be the source set for the stated 7-of-14 to 7-of-15 destination. The confirmed canonical **final** order is the current Base order followed by the new signer:

```text
0x098Ec024CbeA5784B842E35972218e0679534258
0x8254D14d8c8c82Bf1f9Be44881Dd535488116605
0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976
0xd397557dE23d587d70b90726cC88a862AFD915D4
0x21a64eF57be4D6930d3eAF84b8362213F5133Af7
0x0A9071538696a7f2e76A6555c1eb8b6a3C030D47
0x2C0e94B4951E084832b966ec5280924bCb4ACe48
0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83
0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D
0xD4Ca157d6ee33a5d0eB811535577cC716b876304
0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c
0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491
0x007546db322B432f82FcF6067cEEe5916a95005C
0x64b7E2076c47701dF987E389eaEB7254F8a80299
0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db
```

This ordering preserves the current Base order and appends the new member. It is functionally equivalent to any ordering with the same members and threshold. Because the deployment initializer contains only the deployer, this final order does **not** affect the CREATE2 Safe address, but it must still be frozen before generating the atomic bootstrap calldata and later owner-management predecessors.

### Ordered current owners: Polygon

```text
0x8254D14d8c8c82Bf1f9Be44881Dd535488116605
0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976
0xd397557dE23d587d70b90726cC88a862AFD915D4
0x21a64eF57be4D6930d3eAF84b8362213F5133Af7
0x007546db322B432f82FcF6067cEEe5916a95005C
0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83
0x64b7E2076c47701dF987E389eaEB7254F8a80299
0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c
0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D
0xD4Ca157d6ee33a5d0eB811535577cC716b876304
0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491
0x1De45d6811d6796178C0adE37516E510C1E07f77
0x36eee7D790a5B9e8811fB0C570c883997069DF49
```

### Ordered current owners: Base

```text
0x098Ec024CbeA5784B842E35972218e0679534258
0x8254D14d8c8c82Bf1f9Be44881Dd535488116605
0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976
0xd397557dE23d587d70b90726cC88a862AFD915D4
0x21a64eF57be4D6930d3eAF84b8362213F5133Af7
0x0A9071538696a7f2e76A6555c1eb8b6a3C030D47
0x2C0e94B4951E084832b966ec5280924bCb4ACe48
0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83
0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D
0xD4Ca157d6ee33a5d0eB811535577cC716b876304
0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c
0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491
0x007546db322B432f82FcF6067cEEe5916a95005C
0x64b7E2076c47701dF987E389eaEB7254F8a80299
```

### Ordered current owners: Ethereum

```text
0x098Ec024CbeA5784B842E35972218e0679534258
0x8254D14d8c8c82Bf1f9Be44881Dd535488116605
0x21a64eF57be4D6930d3eAF84b8362213F5133Af7
0xd397557dE23d587d70b90726cC88a862AFD915D4
0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D
0xD4Ca157d6ee33a5d0eB811535577cC716b876304
0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c
0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491
0x64b7E2076c47701dF987E389eaEB7254F8a80299
0x007546db322B432f82FcF6067cEEe5916a95005C
0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976
0x0A9071538696a7f2e76A6555c1eb8b6a3C030D47
0x2C0e94B4951E084832b966ec5280924bCb4ACe48
0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83
```

## Phase 1 — Freeze the destination Safe specification

Create a reviewed public deployment manifest with these exact fields:

```text
deploymentPayer: 0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252
bootstrapOwner: 0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252
initializerOwnersOrdered: [0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252]
initializerThreshold: 1
finalOwnersOrdered: confirmed Base order plus 0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db last
finalThreshold: 7
safeRelease: 1.4.1, released=true
proxyFactoryAddress: 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67
proxyFactoryCodeHash: 0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317
proxyCreationCodeHash: 0x1856e0ee08399d74e0ea0b03adca210aeade6f748969ac023cdcb4dd62dcaf5f
singletonAddress: 0x41675C099F32341bf84BFc5382aF534df5C7461a, identical on chains 1/8453/137
singletonCodeHash: 0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4
fallbackHandlerAddress: 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99, supports ERC721/ERC1155 callbacks
fallbackHandlerCodeHash: 0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9
multiSendCallOnlyAddress: 0x9641d764fc13c8B624c04430C7356C1C7C8102e2
multiSendCallOnlyCodeHash: 0xecd5bd14a08c5d2122379900b2f272bdf107a7e92423c10dd5fe3254386c9939
setupTo: 0x0000000000000000000000000000000000000000 unless explicitly approved
setupData: 0x unless explicitly approved
initializerFallbackHandler: fallbackHandlerAddress
paymentToken: 0x0000000000000000000000000000000000000000
payment: 0
paymentReceiver: 0x0000000000000000000000000000000000000000
saltNonce: 0
deploymentMethod: createProxyWithNonce
predictedSafeAddress: 0x80801E5f8FCCd15D8be84994216f5abd066C08E3, verified unused on 1/8453/137 before approval
```

Acceptance gates:

- The initializer contains exactly one checksummed, non-zero owner: `0xFA3E…B252`, at threshold 1.
- The initializer's `fallbackHandler` argument is the pinned compatibility handler; it is not omitted or zeroed.
- The final 15 owner addresses are checksummed, unique, non-zero, and in one deliberately frozen order; final threshold 7 does not exceed final owner count.
- `0xFA3E…B252` is absent from `finalOwnersOrdered` and is removed in the same atomic transaction that installs the final council.
- The same initializer bytes and CREATE2 inputs independently predict the same unused address on all three chains.
- The bootstrap transaction is a separate Safe nonce-0 transaction and is not encoded through initializer `setupTo` or `setupData`.
- The bootstrap calls add owners in reverse final order with intermediate threshold 1, then call `removeOwner(finalOwnersOrdered[14], bootstrapOwner, 7)`. Simulation must prove that `getOwners()` returns the frozen final order.
- Use the same singleton type/address on all three chains. Do not accept SDK defaults without comparing the resulting deployment manifest.
- Pin addresses and bytecode from the official released Safe deployment registry, not a repository `main` branch.

### Atomic deployer-to-council bootstrap

Safe owner insertion occurs at the head of the linked list. To finish with the confirmed final order, the atomic follow-up must call `addOwnerWithThreshold(owner, 1)` for the 15 final signers in **reverse** order. The final call is:

```text
removeOwner(
  0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db,
  0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252,
  7
)
```

At that intermediate state, the new signer is the deployer's linked-list predecessor. `removeOwner` both removes the bootstrap owner and changes the threshold from 1 to 7. The outer transaction targets the pinned `MultiSendCallOnly` with `DELEGATECALL`; all 16 nested self-calls target the new Safe with normal `CALL`. The transaction template enumerates the exact structured call order, while raw calldata and transaction hashes remain unset until the Safe release and addresses are pinned.

The temporary 1-of-1 state is an explicit high-risk custody window. If the bootstrap transaction fails or cannot be simulated exactly, leave the Safe empty and authority-free, record the failed attempt, refresh nonce/state, and stop before migration. A suspected compromise of the deployer key is also a stop condition because that key controls every deployed-but-not-transitioned Safe and is fixed into the same-address initializer.

## Phase 2 — Deploy and verify the destination on all chains

1. Predict the destination address independently from the frozen manifest.
2. Verify the address has no code on chains 1, 8453, and 137.
3. For each chain, deploy with `createProxyWithNonce`, then complete the bootstrap transition before deploying or funding the next operational step. The FLS deployer pays the deployment transaction and is the initial Safe owner.
4. Immediately after each deployment and before the bootstrap transaction, verify:
   - proxy factory and singleton code hashes;
   - `VERSION()`;
   - `getOwners() == [0xFA3E…B252]`;
   - `getThreshold() == 1`;
   - nonce `0`;
   - enabled modules and pagination sentinel;
   - guard storage;
   - fallback handler storage; and
   - a zero native/token balance with no assigned external authority.
5. As Safe nonce 0, execute the prepared atomic deployer-to-council bootstrap transaction. Do not split its 15 additions, deployer removal, or threshold change across transactions.
6. Immediately verify on that chain:
   - byte-for-byte ordered `getOwners()` equals the frozen 15-member final list;
   - `getThreshold() == 7`;
   - `isOwner(0xFA3E…B252) == false`;
   - nonce `1`;
   - modules, guard, and fallback handler are unchanged; and
   - the bootstrap transaction contains only the 16 reviewed Safe self-calls.
7. After all three chains are transitioned, verify the same Safe address and matching proxy/singleton/configuration on chains 1, 8453, and 137.
8. Send independent canaries to each finalized Safe and verify native, ERC-20, ERC-721, and ERC-1155 receipt behavior before treasury batches.

Do not send an NFT with `safeTransferFrom` until the destination fallback handler has been verified to accept the relevant callback.

## Phase 3 — Close inventory and approval gates

1. Declare one signing snapshot block per chain and pause avoidable treasury activity.
2. Re-run the full Blockscout inventory at those blocks.
3. Reconfirm the Base portfolio. On 2026-08-21 the paid Blockscout address, ERC-20, NFT, per-transaction, and raw-trace endpoints recovered. The NFT endpoint returned four ERC-721 items and no next page. An independent raw-RPC scan of every Base `TransferSingle`/`TransferBatch` event involving the vault from block 0 through `50,292,456`, followed by current `balanceOf` calls, confirmed no current ERC-1155 position. At block `50,293,052`, raw RPC also reconfirmed FAME `unit() = 1,000,000e18`, `getSkipNFT(oldSafe) = true`, the unchanged raw FAME balance, and four linked mirror NFTs.
4. Recheck the four known Base Safe executions if their hashes or traces change. The recovered traces show only Safe owner-management calls and FAME transfers; they reveal no additional controlled contract.
5. Re-read old Safe owners, threshold, nonce, modules, guard, and fallback handler.
6. Re-read every known contract authority and revenue route.
7. Re-read the ENS Registry owner, resolver address record, parent owner, and old-Safe reverse record for `vault.fameladysociety.eth`.
8. Re-read FameLadySociety owner/pending owner, AccessControl roles, royalty receiver, renderer, wrap cost, existing donation-vault role/destination, Squad approval, and every current `ownerOf` result.
9. Record a human decision for every checkbox in the asset approval inventory.
10. Produce a diff from this snapshot. Any unexplained balance, owner, role, nonce, module, guard, ENS, or fee-recipient drift is a stop condition.

### Blockscout and raw-RPC verification strategy

Keep Blockscout as the primary discovery/index layer: its paid Base address, ERC-20, NFT, transaction-info, and raw-trace endpoints currently return the needed indexed data. Add raw RPC as an independent verification layer rather than replacing Blockscout:

- `eth_getBalance` for native balances.
- `eth_call` at a pinned block for ERC-20 `balanceOf`, ERC-721 `ownerOf`, ERC-1155 `balanceOf`, Safe state, contract ownership, roles, and fee recipients.
- Chunked, tightly filtered `eth_getLogs` for Safe execution events and ERC-721/1155 transfers when historical reconstruction is needed.
- `eth_getTransactionByHash` and provider-specific transaction tracing when Blockscout's address-wide history hangs.

The configured Ethereum, Base, and Polygon endpoints were capability-tested on 2026-08-21. All three returned their expected chain IDs, current balances, historical balances and Safe thresholds at the documented snapshot blocks, and filtered logs. Base also returned a `debug_traceTransaction` call trace. The endpoints do not expose `alchemy_getAssetTransfers`, so Blockscout remains the indexed discovery source. Broad `eth_getLogs` scans must use filtered adaptive ranges because providers may impose result or block-range limits.

## Phase 4 — Generate unsigned transaction manifests

Produce one immutable review manifest per chain and per signer authority. Each manifest must contain:

```text
schemaVersion
status: unsigned
chainId
snapshotBlock
oldSafe
newSafe
oldSafeNonce
safeVersion
outerTarget
outerValue
outerOperation
orderedCalls[]:
  id
  target
  value
  operation
  methodSignature
  decodedArguments
  calldata
  calldataHash
  expectedPreState
  expectedPostState
safeTransactionHash
simulationReference
approvalsReference
```

Batching rules:

- Use the official `MultiSendCallOnly` matching the pinned Safe release.
- Outer Safe operation is `DELEGATECALL`; every nested operation is `CALL`.
- Use Protocol Kit `onlyCalls: true` if the SDK is used.
- Split core value, independently transferable Society NFTs, related/manual assets, quarantine assets, contract authority, fee routing, and final native dust.
- Treat FAME on Base as one atomic DN404 position. Transfer mirror IDs `170`, `230`, `424`, and `479` first; each mirror call carries one `1,000,000e18` FAME unit. Then transfer only `refreshed FAME balance - 4 * unit()` through ERC-20 `0xf307…2418`.
- Never combine a suspicious token with core value. A reverting or nonconforming token must not block the treasury batch.
- Use fixed reviewed raw amounts, not dynamic “all balance” calldata.
- For ERC-20, verify both return semantics and recipient balance deltas. A token can return `false` without reverting.
- Chunk Ethereum NFT calls by collection and simulation/gas result. Do not force 109 ERC-721 transfers into one transaction merely because MultiSend permits it.

## Prepared transaction shapes

`NEW_SAFE`, `PREV_OWNER`, raw amounts, nonces, and calldata are deliberate placeholders. Final membership, order, and threshold are settled at 15 signers and 7-of-15. Exact bootstrap calldata must not be generated until the remaining Phase 1 deployment constants are frozen. Migration calldata must not be generated until Phases 1–3 pass.

### Polygon — old Safe authority

| ID | Signer authority | Target | Method and arguments | Purpose |
| --- | --- | --- | --- | --- |
| `P-CTRL-01` | Old Polygon Safe | `0x3018671f3495419636519f37FfeA85BfBe3dce0f` | `transferOwnership(NEW_SAFE)` | Move Fameus ownership to the new Polygon Safe |

Postcondition: `owner() == NEW_SAFE` and `rolesOf(oldSafe) == 0`. The contract held `0 POL` at preparation time.

### Base — old Safe asset batches

| ID | Batch | Target(s) | Prepared calls |
| --- | --- | --- | --- |
| `B-CORE-ERC20` | Core/Society | USDC and ZORA contracts in the inventory | `transfer(NEW_SAFE, REFRESHED_RAW_BALANCE)` per approved token |
| `B-FAME-DN404` | Atomic Society DN404 batch | FAME `0xf307…2418`; mirror `0xbb5…46c4` | Verify the new Safe's ERC-721 callback and `getSkipNFT(NEW_SAFE) == true`; call mirror `safeTransferFrom(OLD_BASE_SAFE, NEW_SAFE, tokenId)` for IDs `170`, `230`, `424`, and `479`, then call FAME `transfer(NEW_SAFE, REFRESHED_FAME_RAW_BALANCE - 4 * unit())`. Snapshot remainder: `30086517708905088080739131`; recompute before signing. |
| `B-QUAR-ERC20` | Quarantine/manual | `0x1e358596F48420FE4Cd147DCc850661632125E21` | No call; leave in the old Safe as approved spam/quarantine |
| `B-ERC1155-NONE` | Completeness record | `0x1829…bb24` historical anomaly | No transfer call. Full filtered raw-log history plus current `balanceOf` found no current ERC-1155 holding; retain token ID `101` as a zero-balance quarantine record. |
| `B-NATIVE-FINAL` | Final dust | `NEW_SAFE` | Native `CALL` with the separately approved refreshed wei amount and empty data |

### Base — current operator fee-routing calls

These are not old-Safe transactions. At block `50,230,051`, all three targets were owned by `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9`.

| ID | Signer authority | Target | Method and arguments | Required condition |
| --- | --- | --- | --- | --- |
| `B-FEE-01` | Current router owner | `0xAdefa5860389E8936ebf2977e1Fb4a365aA39636` | `setFeeRecipient(NEW_SAFE)` | `owner()` and old `feeRecipient()` refreshed |
| `B-FEE-02` | Current V3 marketplace owner | `0x93222897902a5Fc2f20079d242c660117277930A` | `setFeeRecipient(NEW_SAFE)` | No active settlement; keep marketplace active unless a separate approved operation requires pause |
| `B-FEE-03` | Current legacy marketplace owner | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` | `setFeeRecipient(NEW_SAFE)` | Preserve paused state |

All three reroutes are approved. Latest Blockscout multicall reads on 2026-08-22 reconfirmed that each fee recipient is the old Base Safe and each contract owner is `0xD52E…6FD9`; V3 remains active and the legacy marketplace remains paused. These are three operator-authority calls, not old-Safe calls. Update the curated public fee-recipient constants only after successful receipts.

Do not conflate the Society vault with the separate Base launch multisig `0xafC3194EE6139fadD53ED20571F2C78a7e47Cb93`.

### Ethereum — old Safe asset batches

| ID | Batch | Target(s) | Prepared calls |
| --- | --- | --- | --- |
| `E-CORE-ERC20` | Core | WETH `0xC02a…6Cc2` | `transfer(NEW_SAFE, REFRESHED_RAW_BALANCE)` |
| `E-QUAR-ERC20` | Quarantine/manual | GumBoy `0x70c5…5608` | No call; leave in the old Safe as approved spam/quarantine |
| `E-FLS-721-n` | Society, chunked | FameLadySociety `0x6cF4…1574` | `safeTransferFrom(OLD_ETH_SAFE, NEW_SAFE, tokenId)` for the refreshed 107-token inventory after approved Squad wrapping |
| `E-SQUAD-WRAP-FIRST` | Society, approved normalization | FameLadySquad `0xf3E6…1B47`; existing donation vault `0x7a27…fb9b` | Existing donation vault `wrapAndDonate(all 27 IDs)` before the FLS transfer chunks, producing 107 FLS NFTs at the old Safe. Direct transfer is not generated. |
| `E-RELATED-721` | Related/manual | YEAR OF THE WOMAN and Bae Apes contracts | One isolated `safeTransferFrom` per approved ID |
| `E-SOCIETY-1155` | Society/related | OpenSea Shared Storefront and FUNKNLOVE | Approved `safeTransferFrom`; FUNKNLOVE may use `safeBatchTransferFrom(OLD_ETH_SAFE, NEW_SAFE, [0,1], [11,1], 0x)` after a fresh balance check |
| `E-RELATED-1155` | Related/manual | Obsidian Elegies `0x85A6…b95a` | Approved isolated `safeTransferFrom(OLD_ETH_SAFE, NEW_SAFE, 3, 1, 0x)` |
| `E-NATIVE-FINAL` | Final dust | `NEW_SAFE` | Native `CALL` with separately approved refreshed wei amount and empty data |

### Ethereum — ENS forward ownership and primary name

At Ethereum block `25,808,649`, old Safe `0xCDF3…e1cF` directly owned the unwrapped Registry node for `vault.fameladysociety.eth`, and its Public Resolver address record pointed to that Safe. Parent `fameladysociety.eth` was owned in both the Registry and BaseRegistrar by EOA `0xf11cc36Cc9e0F2925a3660D5E4dC6bb232CF2A57`, whose reverse record reports `0xflick.xyz`.

| ID | Signer authority | Target | Method and arguments | Purpose |
| --- | --- | --- | --- | --- |
| `E-ENS-FORWARD-ADDR` | Old Ethereum Safe | Public Resolver `0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63` | `setAddr(0x2e52…72ae, NEW_SAFE)` | Change the forward address while the old Safe still controls resolver authorization |
| `E-ENS-OWNER` | Old Ethereum Safe | ENS Registry `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e` | `setOwner(0x2e52…72ae, NEW_SAFE)` | Transfer direct ownership of the `vault` child node |
| `E-ENS-REVERSE` | New Ethereum Safe | ReverseRegistrar `0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb` | `setName("vault.fameladysociety.eth")` | Set the new Safe's primary/reverse name after it owns the forward node |

The first two calls are an ordered old-Safe batch: forward address first, node ownership second. The reverse call is a later transaction from the new Safe. The parent EOA does not need to sign any of them. Parent ownership remains unchanged and retains the ability to recreate or reassign this unwrapped child; changing that posture through NameWrapper fuses or parent transfer is outside this migration.

### Ethereum — FameLadySociety authority and donation-vault replacement

Live reads on 2026-08-22 established:

- FameLadySociety `0x6cF4…1574`: old Safe is `owner()`, `DEFAULT_ADMIN_ROLE`, `TREASURER_ROLE`, and the 5% royalty receiver; `pendingOwner()` is zero.
- Existing donation vault `0x7a27…fb9b`: immutable `vault()` is the old Safe, underlying is FameLadySquad, wrapped output is FameLadySociety, and it currently has FLS `TREASURER_ROLE`.
- The old Safe already has `isApprovedForAll(oldSafe, oldDonationVault) == true` on FameLadySquad.
- The original FameLadySquad contract owner is `0x7Df89AA9e9665335b474b79a1640bCdabfb037af`, not the old Safe.
- FLSNaming, NamedLadyRenderer, and checked SaveLady deployments are deployer-owned; the old Safe has no roles on FLSNaming or NamedLadyRenderer.

Deployment/cutover shape, now explicitly in scope as a post-Safe-launch phase after the new Ethereum Safe address is known:

Implement the deployment in `/Users/user/Development/fls-contracts` as a parameterized Hardhat Ignition module, proposed path `ignition/modules/WrappedNFTDonationVaultModule.ts`. The module takes the final Ethereum Safe as required `vault`, defaults `wrappedNFT` to `0x6cF4…1574`, and deploys only. Do not extend legacy `deploy/50_VaultDonate.ts`; it hardcodes the old Safe and uses the repository's obsolete `hardhat-deploy` path. No Solidity change is required.

| ID | Signer authority | Target | Prepared action | Purpose |
| --- | --- | --- | --- | --- |
| `E-FLS-DONATION-DEPLOY` | Deployment payer | New deployment | `new WrappedNFTDonationVault(0x6cF4…1574, NEW_SAFE)` | Create the immutable replacement |
| `E-FLS-DONATION-GRANT` | Old Ethereum Safe as FLS default admin | FameLadySociety | `grantRole(TREASURER_ROLE, NEW_DONATION_VAULT)` | Allow fee-free donation wrapping |
| `E-FLS-ADMIN-GRANT` | Old Ethereum Safe | FameLadySociety | `grantRole(DEFAULT_ADMIN_ROLE, NEW_SAFE)` | Install new role administrator before removing old authority |
| `E-FLS-TREASURER-GRANT` | Old Ethereum Safe | FameLadySociety | `grantRole(TREASURER_ROLE, NEW_SAFE)` | Transfer wrap-cost, royalty, and withdrawal authority |
| `E-FLS-ROYALTY` | Old Ethereum Safe | FameLadySociety | `setDefaultRoyalty(NEW_SAFE, 500)` | Redirect 5% EIP-2981 royalties |
| `E-FLS-OWNER-START` | Old Ethereum Safe | FameLadySociety | `transferOwnership(NEW_SAFE)` | Begin the contract-required two-step handoff only after the new Safe acceptance batch is fully signed at a reserved nonce |

After deploying and granting the replacement donation vault, update `fls-www` and `society-bots` and prove a donation plus event-indexing canary. Do not revoke the old donation vault until the replacement is live. The old contract has no mutable destination and no upgrade path.

Before executing `E-FLS-OWNER-START`, fully collect the new Safe signatures for the following batch and reserve its Safe nonce. The deployed contract has no external one-step/hard ownership-transfer function. Simulate the paired old-Safe/new-Safe sequence on a fork in the post-handoff state; a current-state simulation of `acceptOwnership()` will correctly revert before `pendingOwner` is set. After every required old-Safe handoff transaction succeeds, execute the already-signed new-Safe batch immediately and do not consume its reserved nonce with another transaction:

1. `FameLadySociety.acceptOwnership()`.
2. `FameLadySociety.revokeRole(TREASURER_ROLE, OLD_ETH_SAFE)`.
3. `FameLadySociety.revokeRole(DEFAULT_ADMIN_ROLE, OLD_ETH_SAFE)`.
4. `FameLadySociety.revokeRole(TREASURER_ROLE, OLD_DONATION_VAULT)` after the application/bot cutover gate.
5. `ReverseRegistrar.setName("vault.fameladysociety.eth")`.

Thus the new Safe still needs only one authority-finalization Ethereum transaction. Its signatures are collected before the old Safe starts the two-step transfer, eliminating a signature-collection delay while `pendingOwner()` is set. If any prerequisite is incomplete, do not execute `transferOwnership`; keep the old Safe as owner until the entire pair is ready.

### Ethereum — FUNKNLOVE role and immutable receiver

These are contract-owner calls, not old-Safe owner-management calls:

| ID | Signer authority | Target | Method | Purpose |
| --- | --- | --- | --- | --- |
| `E-FNL-ROLE-01` | FUNKNLOVE owner `0xFA3E…B252` | `0xf407EE7289CA1941a0D9c89C57fe53F665AD237B` | `grantRoles(NEW_SAFE, 2)` | Let the new Safe trigger emergency withdrawal |
| `E-FNL-ROLE-02` | FUNKNLOVE owner `0xFA3E…B252` | Same | `revokeRoles(OLD_ETH_SAFE, 2)` | Approved cleanup after `rolesOf(NEW_SAFE) == 2` is verified |

The mint is over, so this role handoff is compatibility/authority hygiene rather than a launch requirement. The contract has no setter for its hardcoded `FLS_VAULT_ADDRESS`; future `emergencyWithdraw()` calls always send ETH to the old Ethereum Safe. Maintain the old Safe and a documented old-to-new sweep transaction indefinitely unless the contract is replaced.

## Optional legacy-Safe owner rotation

The new Safe reaches its final owner configuration through the atomic nonce-0 bootstrap transaction. Separately, after asset/control migration is reconciled, the three old Safes may be rotated to the same final council so they remain recoverable legacy receivers.

For each chain, generate the owner calls from that chain's **fresh ordered owner linked list**:

1. If the one new member replaces a departing owner, prefer:

   ```text
   swapOwner(PREV_OWNER, DEPARTING_OWNER, NEW_MEMBER)
   ```

2. Remove every other excluded current owner one at a time:

   ```text
   removeOwner(PREV_OWNER, EXCLUDED_OWNER, THRESHOLD_AFTER_THIS_REMOVAL)
   ```

3. If no swap is appropriate, add the new member first:

   ```text
   addOwnerWithThreshold(NEW_MEMBER, INTERMEDIATE_THRESHOLD)
   ```

4. Finish with `changeThreshold(FINAL_THRESHOLD)` only if the earlier calls did not already set it.

Rules:

- Sentinel predecessor is `0x0000000000000000000000000000000000000001` for the first linked-list owner.
- Every add/remove/swap mutates owner order. Compute `PREV_OWNER` sequentially against simulated intermediate state; never copy predecessors between Polygon, Base, and Ethereum.
- All owner-manager functions are Safe self-calls and must execute through the old Safe.
- Do not rotate or reduce the old owner sets before assets and contract authority are migrated. That adds signing risk and can strand the immutable FUNKNLOVE receiver.
- Produce a distinct owner-rotation manifest from the asset/control manifest.
- Final membership and threshold are known, but exact calls still require an explicit legacy-rotation decision plus a fresh ordered owner linked list and nonce from each old Safe.

## Phase 5 — Simulate and sign

1. Simulate every exact transaction against the signing snapshot block or a current fork with identical state.
2. Inspect decoded calls, trace, expected state deltas, gas, and receiver callbacks.
3. Re-read the Safe nonce immediately before computing the Safe transaction hash.
4. Have signers independently compare chain ID, old/new Safe addresses, nonce, outer operation, every target, every value, and every decoded argument to the reviewed manifest.
5. Collect signatures separately on each chain. Safe EIP-712 signatures are chain-specific even when the Safe address is identical.
6. Do not distribute a signature until the transaction is intended for execution. A distributed Safe signature cannot be revoked off-chain; cancellation consumes the nonce with a replacement transaction.

## Phase 6 — Execute in controlled batches

Recommended sequence:

1. On each chain, deploy the 1-of-1 Safe and immediately execute and verify the atomic transition to 7-of-15 before any funding or authority assignment.
2. After all three chains match, complete canary receipts on all three finalized Safes.
3. Execute one low-value asset batch and reconcile.
4. Polygon: move Fameus ownership and verify.
5. Base: core ERC-20s; the atomic four-mirror-ID plus remainder-ERC-20 FAME batch; all three approved fee routes; then native dust. Leave the Telegram-labeled spam token quarantined in the old Safe.
6. Ethereum: after the new Safe address is known, deploy and grant the approved replacement donation vault; wrap the 27 Squad NFTs through the old donation vault; transfer the resulting 107 FLS NFTs; transfer approved ERC-1155/manual assets; collect signatures for the reserved-nonce new-Safe finalization batch; move ENS and FLS authority with the old Safe only after that batch is fully signed; execute the pre-signed finalization batch immediately; grant the approved FUNKNLOVE role to the new Safe and revoke it from the old Safe after verification; then move native dust. Leave GumBoy quarantined in the old Safe.
7. Only after all balances, NFTs, roles, ownership, and fee routes reconcile, rotate legacy Safe owners if approved.

Do not execute a later batch merely because the transaction before it succeeded. Reconcile each batch's explicit postconditions first.

## Phase 7 — Reconciliation and closeout

Per chain, record:

- deployment transaction and receipt;
- verified proxy factory/singleton/configuration;
- old Safe transaction hash and execution receipt for every batch;
- pre/post native and ERC-20 raw balances;
- every independently transferred ERC-721 `ownerOf(tokenId)` result;
- for Base FAME, the old/new ERC-20 balance delta, destination `getSkipNFT` state, and `ownerOf` results for mirror IDs `170`, `230`, `424`, and `479`;
- every ERC-1155 `balanceOf(newSafe, id)` and old balance;
- contract `owner()`, role bitmap, fee recipient, pending owner, signer/treasurer/admin roles where applicable;
- old Safe leftover inventory and explanation;
- destination Safe nonce and old Safe nonce;
- any failed or skipped item, without marking it migrated.

Closeout gates:

- All approved assets are present at the destination.
- Every unapproved/left-behind asset is explicitly recorded.
- Fameus is owned by the new Polygon Safe.
- Approved Base fee routes point to the new Base Safe address.
- FameLadySociety `owner()`, default admin, treasurer, and 5% royalty receiver point to the new Safe; `pendingOwner()` is zero; the old Safe no longer has admin or treasurer.
- The replacement donation vault immutably points to the new Safe, has treasurer authority, is wired into `fls-www` and `society-bots`, and has a successful end-to-end canary. The old donation vault no longer has treasurer authority and cannot donate to the old Safe.
- The 27 approved Squad IDs are either directly owned by the new Safe or are wrapped and represented by the same 27 FameLadySociety IDs at the new Safe—never both and never stranded.
- ENS Registry owner and Public Resolver address for `vault.fameladysociety.eth` equal the new Ethereum Safe; the new Safe's reverse name forward-resolves back to it; parent owner remains the documented `0xf11c…2A57` EOA.
- FUNKNLOVE new role policy is verified and its immutable old-Safe receiver is documented.
- Before the Base FAME migration, the indexed portfolio and direct mirror reads reconcile the four linked IDs, `unit()`, and the refreshed raw balance. Afterward, the new Safe has the entire refreshed FAME position, exactly linked IDs `170`, `230`, `424`, and `479`, and `getSkipNFT(newSafe) == true`; the old Safe has no residual FAME balance or linked NFTs.
- Refreshed Base raw-RPC ERC-1155 balance checks remain zero, and the four known historical Safe traces remain explainable.
- Old Safes remain monitored through a reconciliation window and the Ethereum legacy receiver remains operational.
- Public deployment constants and curated docs are updated after confirmed receipts; generated broadcast logs are not committed.

## Blocking inputs before calldata generation

- [x] Bootstrap model: deployer-only 1-of-1 initializer followed immediately by one atomic transition transaction.
- [x] Final owner order confirmed for bootstrap calldata: current Base order, then `0x6c9bB7BBa02404a3Dd0cE572a67a8639af0712Db` last.
- [x] Final membership: existing Base/Ethereum 14 plus the new signer.
- [x] Final threshold: 7-of-15.
- [x] `0xFA3E…B252` is deployment payer and temporary bootstrap owner, then is removed from the final owner set atomically.
- [x] Pinned Safe v1.4.1 release, same singleton, factory, fallback handler, MultiSendCallOnly, and salt nonce `0`.
- [x] Predicted same Safe address `0x80801E5f8FCCd15D8be84994216f5abd066C08E3` on chains 1/8453/137 and verified it unused before approval.
- [x] All asset and authority policy decisions are resolved; unchecked mutually exclusive alternatives in the inventory are not selected.
- [x] Recovered Base current NFT index returns four ERC-721s, no ERC-1155s, and no next page.
- [x] Scanned Base ERC-1155 `TransferSingle`/`TransferBatch` history through block `50,292,456`; the only anomalous receipt has current `balanceOf = 0` and is documented as a historical quarantine record.
- [x] Decoded/reviewed Base's four historical Safe executions; only owner management and FAME transfers were found.
- [x] Base FAME policy: atomically transfer linked mirror `0xbb5…46c4` IDs `170`, `230`, `424`, and `479`, then transfer only the refreshed FAME ERC-20 remainder after subtracting the four units carried by those NFT transfers.
- [x] Base assets and fee policy: transfer native ETH, USDC, and ZORA; leave the Telegram-labeled token quarantined; reroute all three identified fee recipients, including the paused legacy marketplace.
- [x] Ethereum asset policy: transfer native ETH, WETH, all listed Society/related ERC-721s and ERC-1155s; leave GumBoy quarantined.
- [x] FameLadySquad policy: wrap all 27 IDs first through the existing donation vault, then migrate the resulting 107 FameLadySociety NFTs; do not generate direct Squad transfers.
- [x] Approve migration of FameLadySociety ownership, default-admin, treasurer, and 5% royalty authority, plus post-Safe-launch deployment/cutover of a replacement immutable donation vault targeting the new Safe.
- [x] ENS migration policy: old Safe updates the forward address and transfers direct ownership of `vault.fameladysociety.eth`; new Safe sets its reverse name; parent EOA ownership and override remain unchanged.
- [ ] Implement and test the parameterized `fls-contracts` Ignition module for `WrappedNFTDonationVault(FLS, NEW_SAFE)`; deploy only after the new Ethereum Safe address is finalized.
- [ ] Freeze the replacement donation-vault address and application/bot cutover evidence before retiring the old vault.
- [ ] Reserve the new Ethereum Safe nonce and fully sign `E-POST-MIGRATION-AUTHORITY` before the old Safe executes `E-FLS-OWNER-START`; do not start the two-step handoff without an immediately executable acceptance batch.
- [x] FUNKNLOVE role policy: grant role `2` to the new Safe, verify it, then revoke role `2` from the old Safe while retaining the old Safe as the immutable withdrawal receiver.
- [ ] Decide whether and when to rotate legacy Safe owners.

## Repository and on-chain evidence

- Base FAME's `1,000,000e18` unit is defined in `src/Fame.sol:74-81`; DN404 mirror transfers move one unit with the selected NFT in `src/DN404.sol:1069-1145`; and mirror `safeTransferFrom` and receiver callbacks are implemented in `src/DN404Mirror.sol:288-349`.
- The separate launch multisig, Society fee recipient, and intended future marketplace owner are recorded in `config/fame-public.env:29-60`.
- Current Base V3 contract addresses are recorded in `config/fame-public.env:75-107` and `script/manifests/creator-artist-magic-v3-base.json:49-59`.
- Router fee routing is owner-controlled in `src/FameRouter.sol:145-149`.
- Marketplace fee routing is owner-controlled and settlement-guarded in `src/UniversalPoolArtMarketplace.sol:305-313`.
- FUNKNLOVE hardcodes the old Ethereum Safe and grants it role `2` in `src/FUNKNLOVE.sol:72-120`; emergency withdrawal sends only to that hardcoded Safe in `src/FUNKNLOVE.sol:270-279`.
- The legacy FameLadySociety and donation-vault implementations are in `/Users/user/Development/fls-contracts/contracts/WrappedNFT.sol` and `WrappedNFTDonationVault.sol`; the latter stores `vault` as an immutable constructor value and exposes no setter. `fls-www` and `society-bots` both currently hardcode `0x7a27…fb9b`.
- The replacement donation deployment should use a new parameterized Hardhat Ignition module in `fls-contracts`. Legacy `deploy/50_VaultDonate.ts` hardcodes the old Safe and should not be extended; the current repository deployment convention is Ignition.
- The deployed FLS ABI exposes `transferOwnership`, `pendingOwner`, and `acceptOwnership`; the deployed historical source inherits OpenZeppelin `Ownable2Step`. `_transferOwnership` is internal, so no external hard-transfer call exists. Pre-signing the new-Safe acceptance batch is the approved operational mitigation.
- Latest 2026-08-22 Blockscout multicalls reconfirmed the FLS owner/roles/royalty, donation-vault immutables/role, Squad approval/owner, related deployer-owned contract posture, all three Base fee routes, and Polygon Fameus ownership. Refresh again at the signing snapshot.
- Live Ethereum RPC reads at block `25,808,649` established the ENS child owner, resolver/address, reverse name, parent Registry/BaseRegistrar owner, and unwrapped authority posture. These reads are snapshot-sensitive and must be repeated before signing.
- All current balances, Safe state, Fameus authority, FUNKNLOVE role state, and Base authority reads in the approval inventory were obtained through Blockscout using the configured paid API key. No secret values are included here.

Official Safe references:

- [SafeProxyFactory source and CREATE2 behavior](https://github.com/safe-fndn/safe-smart-account/blob/main/contracts/proxies/SafeProxyFactory.sol)
- [Protocol Kit initialization and deployment types](https://docs.safe.global/reference-sdk-protocol-kit/initialization/init)
- [Safe multi-chain deployment guidance](https://help.safe.global/articles/9317165368-deploying-a-multi-chain-safe)
- [Official Safe deployment registry](https://github.com/safe-global/safe-deployments)
- [OwnerManager v1.3.0 source](https://github.com/safe-fndn/safe-smart-account/blob/v1.3.0/contracts/base/OwnerManager.sol)
- [MultiSendCallOnly v1.3.0 source](https://github.com/safe-fndn/safe-smart-account/blob/v1.3.0/contracts/libraries/MultiSendCallOnly.sol)
- [Safe fallback-handler guidance](https://docs.safe.global/advanced/smart-account-fallback-handler)
- [Ethereum JSON-RPC methods](https://ethereum.org/developers/docs/apis/json-rpc/)

Official ENS references:

- [ENS Registry ownership and subnode operations](https://docs.ens.domains/registry/ens/)
- [NameWrapper ownership and parent-control fuses](https://docs.ens.domains/wrapper/)
- [Primary names for contract wallets](https://docs.ens.domains/web/naming-contracts/)
