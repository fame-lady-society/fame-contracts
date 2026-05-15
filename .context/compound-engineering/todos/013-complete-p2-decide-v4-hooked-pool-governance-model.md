---
status: complete
priority: p2
issue_id: "013"
tags: [router, security, uniswap-v4, hooks, review]
dependencies: []
---

# Decide V4 Hooked Pool Governance Model

## Problem Statement

The router only enforces `v4HookDataHashEnabled` when a V4 payload has non-empty `hookData`. Hooked V4 pools with empty swap `hookData`, such as basedflick/ZORA, execute under the broader Universal Router target allowlist. This may be the intended lean trust model, but it should be explicitly accepted or tightened.

## Findings

- Review finding #3 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `src/FameRouter.sol:302` checks the hook-data allowlist only when `UniversalRouterAdapter.v4HookDataKey(leg.data)` returns `hasHookData == true`.
- basedflick/ZORA is a hook-address V4 pool with `hookData: "0x"` and is not disabled by current behavior.
- The tradeoff is target-level flexibility versus onchain restriction to a frozen V4 pool/hook universe.

## Proposed Solutions

### Option 1: Document And Accept Target-Level V4 Trust

**Approach:** Keep the contract lean. Document that enabling Universal Router permits any adapter-valid V4 payload, with slippage/deadline and offchain solver policy providing protection.

**Pros:**
- No extra calldata or storage.
- No additional owner allowlist operations for every V4 pool.
- Keeps basedflick/ZORA working as-is.

**Cons:**
- Onchain policy does not restrict execution to the fixture pool universe.
- The existing hook-data allowlist name can be misread as all hooked-pool governance.

**Effort:** Small.

**Risk:** Medium, if the intended trust model was pool-level allowlisting.

### Option 2: Add Hooked Pool/Payload Allowlist

**Approach:** Require an allowlisted key when a V4 payload has a nonzero hooks address, even when `hookData` is empty. The key should include the V4 pool identity and hook address, with hookData hash included when present.

**Pros:**
- Restricts hooked V4 pools onchain.
- Aligns allowlisting with the frozen fixture universe.

**Cons:**
- Adds owner configuration, deployment validation, and tests.
- More contract surface and operational overhead.

**Effort:** Medium.

**Risk:** Medium.

## Recommended Action

Implement Option 1 as a documentation policy. Keep the lean target-level Universal Router trust model for now, and document clearly that enabling Universal Router permits adapter-valid V4 payloads, including hooked pools with empty swap `hookData`. Do not add pool/hook-level allowlisting unless the trust model is explicitly revisited.

## Technical Details

Affected files if tightening:

- `src/FameRouter.sol`
- `src/router/adapters/UniversalRouterAdapter.sol`
- `test/router/FameRouter.t.sol`
- `script/DeployFameRouter.s.sol`
- `script/ValidateFameRouterBase.s.sol`
- router-ts fixture manifests if required keys are generated

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- Security reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/security.json`
- Security audit: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/security-audit.md`

## Acceptance Criteria

- [x] Documentation states that the current trust model is target-level Universal Router allowlisting, not V4 pool/hook-level allowlisting.

## Work Log

### 2026-05-15 - Target-Level V4 Policy Documented

**By:** Codex

**Actions:**
- Documented that v1 onchain policy allowlists the Universal Router target and validates structured payloads, rather than allowlisting each V4 pool or hook address.
- Clarified that non-empty swap `hookData` uses the hook-data hash allowlist, while hooked pools with empty swap `hookData` remain governed by solver pool-universe policy.
- [ ] Documentation states that basedflick/ZORA works because empty swap `hookData` does not require `v4HookDataHashEnabled`.
- [ ] Documentation states that `v4HookDataHashEnabled` governs non-empty V4 swap `hookData`, not all hooked pools.
- [ ] No contract pool/hook allowlist is added as part of this todo.

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #3 after clarifying that basedflick/ZORA is currently enabled, not disabled.

**Learnings:**
- The finding is a trust-model decision rather than an automatic contract bug.
