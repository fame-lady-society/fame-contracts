# Security Audit

Scope: current branch diff against merge-base `1f6086a8570c33d9a54a43abcbec9f0b17bd389a`, using `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/diff.patch` plus current tree inspection.

Focus: hardcoded secrets, leaked RPC/private keys/API keys/mnemonics, deployment-doc safety, and FameRouter approval, custody, target allowlist, slippage/deadline, reentrancy, and native ETH/WETH behavior.

## Findings

### P2 - Native ETH route-local dust can revert otherwise valid routes for contract senders

- Location: `src/FameRouter.sol:124-125`, `src/FameRouter.sol:359-364`, `src/FameRouter.sol:386-390`
- Impact: successful multi-leg routes can be made unusable for account-abstraction wallets, Safe modules, or other contract senders that cannot receive ETH.
- Details: after fee and final-output settlement, `_refundRouteLocalLeftovers` refunds every positive route-local leftover to `msg.sender`. If an intermediate leg leaves native ETH dust, `_transferAsset` uses `safeTransferETH(msg.sender, local)`. A non-payable or rejecting contract sender causes the refund to revert, unwinding the whole route even though slippage and custody checks already passed. This is not a theft path, but it is a native-flow integration DoS and can break relayed/contract-wallet execution.
- Recommendation: add an explicit refund recipient, allow native leftovers to be wrapped to canonical WETH, or reject native-leftover route shapes for non-payable senders.

### P3 - V4 hook-data allowlist does not constrain empty-hookData hooked pools

- Location: `src/FameRouter.sol:301-305`, `src/router/adapters/UniversalRouterAdapter.sol:182-186`, `src/router/adapters/UniversalRouterAdapter.sol:163-173`
- Impact: once the Universal Router target is enabled for `UniswapV4`, callers can submit any V4 pool key matching `tokenIn`/`tokenOut` when `hookData` is empty, including nonzero hook addresses. The configured `v4HookDataHashEnabled` gate only applies when `payload.hookData.length != 0`.
- Details: the current fixtures intentionally support production hooked pools with empty swap hook data, so this may be a policy choice. The security boundary should be explicit: if hook address and pool key are part of the production allowlist, empty-hookData hooked pools need a pool/hook allowlist too. If arbitrary user-supplied V4 pool keys are intended, document that target allowlisting does not imply pool/hook allowlisting and that route builders own pool trust and slippage.
- Recommendation: either enforce an allowlist key for all nonzero-hook V4 pool keys, even when `hookData == 0x`, or document the broader user-supplied pool-key trust model in the schema and launch docs.

## Secret Scan Status

Status: pass for changed branch content.

- No committed raw RPC URLs, private key values, API key values, mnemonic phrases, or password literals found in changed files.
- `config/fame-public.env` contains public chain IDs, public contract addresses, fee config, and a fixture snapshot hash only.
- `foundry.toml` uses environment substitutions for RPC and explorer keys.
- Router deploy/validation scripts read secrets through `vm.env*`; no secret values are hardcoded.
- Broadcast artifacts contain deployment transaction calldata, addresses, transaction hashes, timestamps, and chain IDs. I did not find private keys, mnemonics, API keys, or RPC endpoint values in the committed broadcast JSON.

Advisory: some legacy release-plan commands still pass private keys to `forge`/`cast` as CLI arguments inside `doppler run -- sh -c ...`. That avoids committing or printing literal values, but it can still expose expanded secrets through local process arguments. The new router deployment path is safer because it uses a Foundry script reading `BASE_DEPLOYER_PRIVATE_KEY` via `vm.envUint`.

## Checks That Passed

- Route validation runs before pulling ERC-20 input and enforces version, deadline, recipient, amount, leg count, enabled venue family, enabled target, payload size, same-asset rejection, final-output production, and final-output consumption.
- Direct ERC-20 approvals are exact per leg and cleared after successful dispatch; Permit2 approvals are exact and cleared after Universal Router execution.
- Universal Router V3/V4 adapters decode structured payloads and construct constrained commands internally; raw `execute(...)` payloads are rejected.
- Final recipient delivery for ERC-20 tokenOut is measured after transfer, protecting `minAmountOutAfterFee` from fee-on-transfer under-delivery.
- Route-local accounting fails closed on malformed/reverting ERC-20 `balanceOf`.
- `executeRoute` and `rescue` are protected by `nonReentrant`; reentrant token callbacks cannot reenter route execution or owner rescue during execution.
