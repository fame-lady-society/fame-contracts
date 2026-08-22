# Society Vault Asset Approval Inventory
Created: 2026-08-20
Updated: 2026-08-22

Status: **PREPARATION ONLY — NOT APPROVED FOR EXECUTION**

This is the asset and authority inventory for migrating the Society vaults to one new cross-chain Safe address. It contains every current holding returned by Blockscout for Polygon and Ethereum, every Base holding recovered through the available Blockscout endpoints and historical transfer logs, and the Society-related contract authorities found in the repository and verified on-chain.

No transaction has been signed, proposed, or submitted. Token names and NFT metadata are untrusted labels; addresses, standards, token IDs, quantities, and raw amounts are the approval keys.

## Snapshot and completeness

| Chain | Old vault | Snapshot block | Coverage | Open completeness issue |
| --- | --- | ---: | --- | --- |
| Polygon (137) | `0x560dF07ff3aB5eAE66683D6e11AbFa28f1801997` | `92,363,016` | Native, ERC-20, ERC-721, and ERC-1155 inventory complete; Safe and owned-contract state read | None at snapshot |
| Base (8453) | `0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D` | Balances `50,230,051`; FAME relationship rechecked `50,293,052`; NFTs refreshed 2026-08-21; ERC-1155 raw-log scan through `50,292,456` | Paid Blockscout current portfolio plus independent raw-RPC state reads and a scan of all `TransferSingle`/`TransferBatch` events from block 0 | No current ERC-1155 holding. Blockscout's address-wide history still hangs, but it is no longer an ERC-1155 completeness blocker. |
| Ethereum (1) | `0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF` | Assets/roles `25,798,046`; ENS authority `25,808,649` | Native, ERC-20, ERC-721, and ERC-1155 inventory paginated to completion; Safe, role-bearing contract, and ENS state read | None at snapshot |

Base native balance changed materially during the inventory window—from `0.00317 ETH` at block `50,229,596` to `1.161250824601677945 ETH` at block `50,230,051`. Treat every amount below as a snapshot, not executable calldata. Regenerate exact balances immediately before transaction review.

## Approval key

- **Core value**: liquid native/ERC-20 assets that should ordinarily move.
- **Society**: canonical or directly Society-related assets that should ordinarily move.
- **Related/manual**: plausible Society, art, or community assets requiring a human keep/transfer decision.
- **Quarantine/manual**: suspicious or unclear assets retained in the inventory and isolated from core batches. They are not silently discarded.
- **Authority**: ownership, role, or fee routing rather than a token balance.

## Polygon

### Fungible and NFT balances

| Standard | Asset | Contract | Raw balance / token IDs | Classification | Approval |
| --- | --- | --- | --- | --- | --- |
| Native | POL | Native | `0` | None to transfer | N/A |
| ERC-20 | None returned | — | — | None to transfer | N/A |
| ERC-721 | None returned | — | — | None to transfer | N/A |
| ERC-1155 | None returned | — | — | None to transfer | N/A |

### Contract authority

| Contract | Address | Current relationship | Current balance | Proposed action | Approval |
| --- | --- | --- | ---: | --- | --- |
| Fameus | `0x3018671f3495419636519f37FfeA85BfBe3dce0f` | Old Polygon Safe is `owner()`; `rolesOf(oldSafe) = 0`; verified contract; creator was `0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252` | `0 POL` | Old Safe calls `transferOwnership(NEW_SAFE)` after the new Polygon Safe is deployed and verified | [x] Transfer ownership |

The Fameus ABI exposes direct Solady-style `transferOwnership(address)` and no `pendingOwner()`/`acceptOwnership()` requirement.

## Base

### Native and ERC-20 balances

| Standard | Asset label | Contract | Decimals | Human amount | Raw amount | Classification | Approval |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| Native | ETH | Native | 18 | `1.161250824601677945` | `1161250824601678039` | Core value | [x] Transfer, using refreshed amount |
| ERC-20 | USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 | `1.041961` | `1041961` | Core value | [x] Transfer |
| ERC-20 | ZORA | `0x1111111111166b7FE7bd91427724B487980aFc69` | 18 | `0.271292401162931083` | `271292401162931083` | Core value | [x] Transfer |
| ERC-20 | FAME / Society | `0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418` | 18 | `34,086,517.708905088080739131` | `34086517708905088080739131` | Society/core value; DN404 source of the linked mirror state below | [x] Preserve the four existing mirror IDs and transfer the remaining ERC-20 balance; refresh all state first |
| ERC-20 | `Telegram @TronVanity88_bot` | `0x1e358596F48420FE4Cd147DCc850661632125E21` | 0 | `8,888` | `8888` | Quarantine/manual; label is untrusted | [x] Leave in old Safe as spam/quarantine |

### Linked Society mirror state — preserve the four existing IDs

The Base Safe currently holds four ERC-721 IDs in FAME's linked DN404 mirror:

- Contract: `0xbb5ed04dd7b207592429eb8d599d103ccad646c4`
- Standard: ERC-721
- Token IDs: `170`, `230`, `424`, `479`
- Quantity: `1` each
- Classification: Society assets linked to the FAME ERC-20 position
- Approval: [x] Transfer all four listed IDs to the new Safe

The approved migration treats FAME and its mirror as one atomic DN404 position. Each mirror `safeTransferFrom(OLD_BASE_SAFE, NEW_SAFE, tokenId)` moves that specific ERC-721 and exactly one FAME unit (`1,000,000e18`) to the recipient. The old Safe must therefore execute four mirror transfers first, followed by one FAME ERC-20 transfer for `REFRESHED_FAME_RAW_BALANCE - (4 * unit())`. This preserves IDs `170`, `230`, `424`, and `479` without double-transferring the four FAME units carried by those NFT moves.

Raw RPC rechecked the old Safe at Base block `50,293,052`: `getSkipNFT(oldSafe) = true`, the FAME raw balance remained `34086517708905088080739131`, the mirror balance remained `4`, and `unit() = 1000000000000000000000000`.

At that snapshot, the four NFT transfers carry `4000000000000000000000000` raw FAME and the final ERC-20 remainder is `30086517708905088080739131`. These are review values, not executable amounts. Immediately before signing, confirm all four `ownerOf` results, the mirror balance, `unit()`, and the old Safe's raw FAME balance; recompute the remainder and stop on any drift.

Keep `getSkipNFT(NEW_SAFE) == true` so the final ERC-20 remainder does not mint approximately 30 additional mirror NFTs. Do not include a call to `FAME.setSkipNFT(false)`. Put the four mirror calls and the remainder ERC-20 call in one atomic `MultiSendCallOnly` batch, in that order, and first verify that the new Safe's fallback handler accepts ERC-721 callbacks. The required post-state is the entire refreshed FAME position at the new Safe, exactly the four listed mirror IDs at the new Safe, and zero residual FAME or mirror NFTs at the old Safe.

### ERC-1155 balances

- On 2026-08-21, Blockscout's recovered current NFT index returned exactly four items—the four ERC-721 IDs above—with `next_page_params = null` and no ERC-1155 positions.
- The independent Base RPC accepted historical state reads and a full filtered `TransferSingle`/`TransferBatch` scan from block 0 through `50,292,456`. It found no current ERC-1155 position after direct `balanceOf` verification.
- The scan did find one anomalous historical receipt: unverified ERC-1155 contract `0x1829eA38677e1C5a80e262eA072Ad3EE9D5ABB24`, token ID `101`, amount `1`, at block `38,138,882` in transaction `0x79020abeb09a8de1a8dc63ab96f7cb957ec537a9d64d010e801e6468e797f05a`. The contract emitted no standard outgoing event for this vault, but both raw RPC and Blockscout return current `balanceOf(vault, 101) = 0`.
- Blockscout labels the unverified collection `0`; the transaction was a mass distribution and its metadata contains an unsolicited Telegram claim instruction. Treat all such metadata as untrusted. This is retained as a historical quarantine/anomaly record, but there is no current balance to approve or transfer.

### Fee routing and related Base authority

The old Base Safe did not own any of the repository-listed Base contracts at block `50,230,051`. It was, however, the current fee recipient for three contracts:

| Contract | Address | Current owner | Current old-vault relationship | Proposed action | Approval |
| --- | --- | --- | --- | --- | --- |
| FameRouter | `0xAdefa5860389E8936ebf2977e1Fb4a365aA39636` | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` | `feeRecipient()` is old Base Safe | Owner calls `setFeeRecipient(NEW_SAFE)` | [x] Reroute |
| UniversalPoolArtMarketplace V3 | `0x93222897902a5Fc2f20079d242c660117277930A` | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` | `feeRecipient()` is old Base Safe; `paused() = false`; authorized checkout is `0x50B9649Aa28D7d0B966B2A51092C5BcF37905a63` | Owner calls `setFeeRecipient(NEW_SAFE)` only when no settlement is active | [x] Reroute |
| Legacy marketplace | `0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e` | `0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9` | `feeRecipient()` is old Base Safe; `paused() = true`; authorized checkout is `0x1905B4a633074243f3D9FDB59596fB7419adce2c` | Owner calls `setFeeRecipient(NEW_SAFE)` while preserving its paused state | [x] Reroute |

Additional live checks at block `50,230,051`:

- FAME `0xf307…2418`: `owner() = 0x0000000000000000000000000000000000000000`; `rolesOf(oldSafe) = 0`.
- CreatorArtistMagic V3 `0x6754…86ee`: owned by `0xD52E…6FD9`; `rolesOf(oldSafe) = 0`.
- ClaimToFame `0xD6c1…117A`: owned by `0xD52E…6FD9`; `rolesOf(oldSafe) = 0`.
- CreatorArtistMagic V2 `0xC826…139F`: owned by `0xD52E…6FD9`; `rolesOf(oldSafe) = 0`.
- FameVesting `0xf930…95D2`: owned by `0x9dA2…89CE`.
- The active and legacy marketplace owners are not the old vault. Any ownership handoff is a separate governance decision, not part of moving old-vault authority.

The Blockscout Base address-wide transaction-history stream still hangs. Four successful Safe execution hashes were recovered from `ExecutionSuccess` events, and the per-transaction and raw-trace endpoints recovered on 2026-08-21:

| Transaction | Block | Decoded Safe action |
| --- | ---: | --- |
| `0x63d9c94b2d70ce6271783c842989ad1a62007c028d20d6025dcc4fc06ee45a97` | `25,304,184` | Batched Safe self-calls using `removeOwner(address,address,uint256)` and `addOwnerWithThreshold(address,uint256)` |
| `0x99072fd6118830fd8b0090ebba175ad361a1abc1d62d2353123bad565a06e034` | `37,257,955` | FAME `transfer(address,uint256)` |
| `0x25a60ece10029d8b71aab322c68f7cba8be092f3334d652433e549ed4ca6319d` | `40,868,989` | Safe self-call `addOwnerWithThreshold(address,uint256)` |
| `0x5df4b533819d39e0f1a32e216403b8b7da8591414b6aa44a4fec367961d4b898` | `48,542,040` | FAME `transfer(address,uint256)` |

The traces reveal no additional contract owned, role-controlled, or administered by the Base vault. Signature-recovery precompile calls, Safe singleton delegatecalls, and Safe self-calls are not external authority relationships.

## Ethereum

### Native and ERC-20 balances

| Standard | Asset label | Contract | Decimals | Human amount | Raw amount | Classification | Approval |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| Native | ETH | Native | 18 | `0.4024921637142857` | `402492163714285700` | Core value | [x] Transfer, using refreshed amount |
| ERC-20 | WETH | `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | 18 | `0.1040007142857143` | `104000714285714300` | Core value | [x] Transfer |
| ERC-20 | GumBoy | `0x70c573C15e95EeBd71Bae6A4B0a786B7bA3f5608` | 18 | `1,000,000` | `1000000000000000000000000` | Quarantine/manual; label is untrusted | [x] Leave in old Safe as spam/quarantine |

### ERC-721 balances

#### FameLadySociety

- Contract: `0x6cF4328f1Ea83B5d592474F9fCDC714FAAfd1574`
- Count: `80`
- Classification: Society
- Approval: [x] Transfer all 80 currently held IDs; if the Squad wrap-first path is approved, also transfer the 27 newly wrapped IDs

```text
328, 593, 649, 722, 724, 757, 801, 1348, 1402, 1546,
1703, 1778, 1820, 1896, 2193, 2247, 2335, 2349, 2372, 2676,
2709, 2792, 2899, 2918, 2986, 2998, 3163, 3170, 3261, 3269,
3328, 3653, 3670, 3729, 4042, 4090, 4243, 4276, 4289, 4404,
4456, 4516, 4520, 4543, 4567, 4975, 5037, 5149, 5246, 5272,
5309, 5402, 5550, 5632, 5846, 5865, 6040, 6091, 6659, 6772,
6850, 7124, 7203, 7283, 7325, 7350, 7527, 7576, 7832, 7914,
7961, 8061, 8256, 8283, 8368, 8371, 8579, 8583, 8587, 8688
```

#### FameLadySquad

- Contract: `0xf3E6DbBE461C6fa492CeA7Cb1f5C5eA660EB1B47`
- Count: `27`
- Classification: Society
- Approval: [x] Migrate all 27 IDs by wrapping first into FameLadySociety / [ ] Direct transfer (not selected)

```text
2392, 2630, 2639, 2642, 2645, 3416, 3809, 3812, 3815,
3817, 3902, 3904, 4097, 4268, 4410, 5605, 5610, 5627,
5761, 5882, 5885, 5920, 6170, 6182, 6270, 6495, 7161
```

These 27 original FameLadySquad NFTs are currently unwrapped. Existing donation contract `0x7a276F4B91A97267D652500aa4aB8b2Fa388fb9b` can wrap them fee-free into the FameLadySociety contract and mint the same 27 token IDs back to the old Safe. The old Safe already approves that donation contract, and the donation contract currently has the FLS `TREASURER_ROLE` required to temporarily set `wrapCost` to zero.

Approved path: simulate and execute `wrapAndDonate(tokenIds)` from the old Safe before asset migration, chunking only if gas requires it. The old Safe will then hold 107 FameLadySociety NFTs—its current 80 plus the 27 newly wrapped IDs—and the migration will transfer one canonical collection. Wrapping remains reversible through `unwrap`. The direct-transfer alternative is retained only as a non-generated audit record.

#### Other ERC-721

| Collection label | Contract | Token ID | Quantity | Classification | Approval |
| --- | --- | ---: | ---: | --- | --- |
| YEAR OF THE WOMAN | `0x3C7b5B7ea8e7C7ce8297baC167FEb97BF5A1ad98` | `8626` | `1` | Related/manual | [x] Transfer |
| Bae Apes NFT | `0xb56011FBfdAfe460b905A40A4845A49C94712272` | `2520` | `1` | Related/manual | [x] Transfer |

### ERC-1155 balances

| Collection label | Contract | Token ID | Quantity | Classification | Approval |
| --- | --- | ---: | ---: | --- | --- |
| OpenSea Shared Storefront; metadata label `IAMNAX - FIRED UP` | `0x495f947276749Ce646f68AC8c248420045cb7b5e` | `24847003539941428306476414038544445787743965496585528607173026678158422704461` | `1` | Society-related/manual; metadata claims FLS inspiration | [x] Transfer |
| Obsidian Elegies | `0x85A6b52F30839acbd12e1cD189e850467bCcb95a` | `3` | `1` | Related/manual | [x] Transfer |
| Funk N' Love | `0xf407EE7289CA1941a0D9c89C57fe53F665AD237B` | `0` | `11` | Society | [x] Transfer |
| Funk N' Love | `0xf407EE7289CA1941a0D9c89C57fe53F665AD237B` | `1` | `1` | Society | [x] Transfer |

### FameLadySociety contract authority and donation cutover

The FameLadySociety NFT contract is `0x6cF4328f1Ea83B5d592474F9fCDC714FAAfd1574`. It is the wrapped collection whose 80 vault-held NFTs are listed above; its immutable underlying collection is FameLadySquad `0xf3E6…1B47`. The earlier inventory recorded its tokens but missed the separate contract-authority lane.

Latest Blockscout multicall reads on 2026-08-22 found:

- `owner()` is the old Ethereum Safe; `pendingOwner()` is zero. Ownership uses a two-step handoff.
- The old Safe has `DEFAULT_ADMIN_ROLE` and `TREASURER_ROLE`; it does not have `UPDATE_RENDERER_ROLE` or `EMIT_METADATA_ROLE`.
- The 5% default royalty receiver is the old Safe.
- Existing donation vault `0x7a276…fb9b` has `TREASURER_ROLE`, and its immutable `vault()` is the old Safe.
- The FLS deployer `0xFA3E…B252` has none of those four AccessControl roles on FameLadySociety.
- FameLadySquad itself is owned by `0x7Df89AA9e9665335b474b79a1640bCdabfb037af`, not the old Safe.
- FLSNaming, NamedLadyRenderer, and the checked SaveLady deployments are owned by `0xFA3E…B252`; the old Safe has no roles on FLSNaming or NamedLadyRenderer. Those are separate deployer-governance handoffs, not old-vault authority migrations.

The existing `WrappedNFTDonationVault` has no owner, role, or setter that can change its immutable destination. Continuing to use it after migration would mint future donated FLS NFTs to the old Safe. Required cutover:

1. Deploy a replacement `WrappedNFTDonationVault(FLS, NEW_SAFE)` after the new Ethereum Safe is finalized.
2. Old Safe grants the replacement donation vault FLS `TREASURER_ROLE`.
3. Update `fls-www` and `society-bots` to the replacement address and verify wrapping plus event monitoring.
4. New Safe revokes `TREASURER_ROLE` from the old donation vault only after the replacement is live; this deliberately makes the old `wrapAndDonate` entrypoint revert instead of donating to the legacy Safe.

Required FLS authority migration:

1. Old Safe grants `DEFAULT_ADMIN_ROLE` and `TREASURER_ROLE` to the new Safe.
2. Old Safe calls `setDefaultRoyalty(NEW_SAFE, 500)` and `transferOwnership(NEW_SAFE)`.
3. Because the deployed FLS implementation inherits OpenZeppelin `Ownable2Step`, there is no external hard-transfer function. Before the old Safe executes `transferOwnership(NEW_SAFE)`, collect all signatures for the new Safe's acceptance/finalization transaction at a reserved nonce. Execute that already-signed transaction immediately after the old-Safe handoff so there is no post-handoff signature-collection window.
4. The new-Safe transaction calls `acceptOwnership()`, then revokes the old Safe's `TREASURER_ROLE` and `DEFAULT_ADMIN_ROLE` after verification.

Approval: [x] Migrate FLS ownership, default-admin, treasurer, and royalty authority using the required pre-signed two-step ownership sequence / [x] Deploy, cut over, and retire the immutable old donation vault after the new Safe address is known / [x] Wrap first for the 27 Squad NFTs

### ENS subdomain authority

Live Ethereum reads at block `25,808,649` established the following authority for `vault.fameladysociety.eth`:

- Namehash: `0x2e52a3ea02db5dd1e719509b39047494a77b5f986dfa33bfa5ac69a204e172ae`.
- ENS Registry `0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e` owner: old Ethereum Safe `0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF`.
- Public Resolver: `0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63`; its address record points to the old Ethereum Safe.
- The old Safe's primary/reverse name is `vault.fameladysociety.eth`.
- Parent `fameladysociety.eth` Registry and BaseRegistrar owner: EOA `0xf11cc36Cc9e0F2925a3660D5E4dC6bb232CF2A57`, whose reverse record reports `0xflick.xyz`.
- The subdomain and parent are unwrapped. The old Safe is therefore the direct current subdomain owner and can update its resolver record and transfer the node without a signature from the parent EOA. Because the child is unwrapped, the parent owner retains superior authority to recreate or reassign the `vault` child later through `setSubnodeOwner`.

Approved migration shape:

1. While the old Safe still owns the node, call Public Resolver `setAddr(node, NEW_SAFE)`.
2. In the same ordered old-Safe batch, call ENS Registry `setOwner(node, NEW_SAFE)`.
3. After the new Safe owns the node, the new Safe calls ReverseRegistrar `0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb.setName("vault.fameladysociety.eth")` to establish its primary name.

The order is mandatory: transferring the registry node first removes the old Safe's authority to update the resolver. The parent EOA does not need to sign this migration. This plan intentionally leaves parent ownership and its parent-level override unchanged; wrapping/emancipating the subdomain or changing parent ownership is a separate governance decision.

Approval: [x] Move the forward record and direct subdomain ownership to the new Safe, then set the new Safe's primary name; retain the documented parent override

### FUNKNLOVE authority

At block `25,798,046`:

- Contract: `0xf407EE7289CA1941a0D9c89C57fe53F665AD237B`
- `owner()`: `0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252`
- `rolesOf(oldEthereumSafe)`: `2`, the contract's `WITHDRAW_ROLE`
- Native contract balance: `0 ETH`
- The source hardcodes the old Ethereum Safe as `FLS_VAULT_ADDRESS`; `emergencyWithdraw()` always sends ETH there. There is no recipient setter.

Approved authority action:

1. Contract owner `0xFA3E…B252` calls `grantRoles(NEW_SAFE, 2)`.
2. Verify `rolesOf(NEW_SAFE) = 2`.
3. Call `revokeRoles(OLD_ETH_SAFE, 2)` only after the new Safe role is verified. This removes obsolete caller authority even though future emergency withdrawals still land in the old Safe.
4. Keep the old Ethereum Safe operational as a legacy receiver, with a documented sweep path to the new Safe.

Approval: [x] Grant new Safe role to preserve the authority posture / [ ] Retain old role / [x] Revoke old role after the new role is verified

## Approval summary

| Chain | Native | ERC-20 contracts | ERC-721 token IDs | ERC-1155 token IDs | Authority/fee items |
| --- | ---: | ---: | ---: | ---: | ---: |
| Polygon | 0 balance | 0 | 0 | 0 | 1 owned contract |
| Base | 1 balance | 4 | 4 linked DN404 IDs approved for transfer | 0 current | 3 approved fee-recipient routes |
| Ethereum | 1 balance | 2 | 109 before any Squad wrapping | 4 IDs / 14 units | FLS owner/admin/treasurer/royalty, donation-vault replacement, 1 ENS subdomain, 1 withdrawal-role relationship, and 1 immutable legacy receiver |

Only explicitly checked decisions are approved. Base native ETH, USDC, ZORA, FAME, and all three fee routes are approved; the Telegram-labeled token is approved to remain as spam/quarantine. Ethereum native ETH, WETH, the listed Society/related NFTs, ENS, wrap-first Squad normalization, FLS ownership/role/royalty handoff, replacement donation vault, and FUNKNLOVE role grant/revocation are approved; GumBoy is approved to remain as spam/quarantine. Unchecked mutually exclusive alternatives are deliberately not selected. Remaining deployment/configuration gates are tracked in the migration plan, and all balances/authorities must be refreshed before calldata generation.
