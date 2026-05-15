---
status: complete
priority: p2
issue_id: "017"
tags: [repo-hygiene, deployment, security, review]
dependencies: []
---

# Remove Broadcast Artifacts And Tighten Artifact Policy

## Problem Statement

The repo currently tracks Foundry `broadcast/**` JSON. Even when these artifacts contain only public transaction metadata, publishing generated deployment logs creates avoidable risk because mistakes can happen and future runs could accidentally include sensitive or operationally undesirable data. The branch also includes historical `.context/compound-engineering/ce-review/**` outputs, which add review noise to the merge diff.

## Findings

- Review finding #8 from `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`.
- `broadcast/DeployFameRouter.s.sol/8453/*.json` files are tracked and contain public transaction metadata.
- The repo has 44 tracked `broadcast` files totaling about 21 MB, so this is existing tracked history rather than a one-off new artifact.
- `.context/compound-engineering/ce-review/**` artifacts are tracked in this branch.
- `AGENTS.md` does not currently define a rule that forbids these artifacts, so this is a policy decision rather than a standards violation.
- Secret scan passed: no raw RPC URLs, private keys, API keys, mnemonics, bearer tokens, or password literals were found in changed branch content.
- The maintainer is comfortable rewriting this feature branch's pushed tip if needed to remove broadcast artifacts before PR review.

## Proposed Solutions

### Option 1: Remove Broadcast Artifacts From The Branch

**Approach:** Remove tracked `broadcast/**` files from the feature branch and add ignore/policy guidance so future Foundry broadcast output is not published. Preserve public deployment facts in curated docs/config instead of raw generated logs.

**Pros:**
- Minimizes risk of publishing future generated output by mistake.
- Keeps deployment facts public without raw run logs.
- Reduces PR noise and repository size.

**Cons:**
- Requires a history rewrite or force push if the goal is to remove them from the pushed branch history, not just the final tree.

**Effort:** Small.

**Risk:** Medium if rewriting pushed history; acceptable here because this is a single-maintainer branch.

### Option 2: Remove Only New Router Broadcast Artifacts

**Approach:** Remove only `broadcast/DeployFameRouter.s.sol/8453/*.json` from this branch and leave older broadcast history untouched.

**Pros:**
- Smaller change.
- Avoids disturbing older tracked deployment provenance.

**Cons:**
- Leaves the broader policy/risk in place.
- Future generated broadcast files may still be committed.

**Effort:** Small.

**Risk:** Low to medium.

### Option 3: Keep Everything With A Secret-Scan Gate

**Approach:** Treat `.context` and broadcast outputs as acceptable artifacts, but add automated scanning to prove they contain no secrets before merge.

**Pros:**
- Maximum traceability.

**Cons:**
- Large diffs and long-term artifact churn.

**Effort:** Medium.

**Risk:** Medium.

## Recommended Action

Implement Option 1 in the next resolve batch. Remove tracked `broadcast/**` artifacts from this feature branch, update ignore/policy guidance so Foundry broadcast output is not committed going forward, and preserve public deployment facts such as deployed router address in curated config/docs. Rewriting the pushed feature-branch tip with a force push is acceptable for this cleanup because the maintainer is the only contract repo contributor.

## Technical Details

Affected areas:

- `.gitignore`
- `broadcast/**`
- `.context/compound-engineering/ce-review/**`
- `.context/compound-engineering/todos/**`
- possibly a lightweight secret-scan script or verification step for `config/fame-public.env` and retained artifacts

## Resources

- Review synthesis: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/synthesis.md`
- Maintainability reviewer artifact: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/maintainability.json`
- Security audit: `.context/compound-engineering/ce-review/20260515-103118-codex-main-review/security-audit.md`

## Acceptance Criteria

- [x] Tracked `broadcast/**` artifacts are removed from the feature branch.
- [x] If needed, the pushed feature branch is force-updated so broadcast artifacts are absent from the branch history/tip being reviewed.
- [x] Public deployment facts remain documented in curated config/docs, including deployed Base router address.
- [x] `.gitignore` or repo guidance prevents future Foundry broadcast output from being committed accidentally.
- [x] The repo has an explicit policy for retaining or excluding `.context/compound-engineering/ce-review/**` run artifacts.
- [x] No raw secrets are published to the repo.

## Work Log

### 2026-05-15 - Initial Todo

**By:** Codex

**Actions:**
- Created from ce:review finding #8 and related advisory artifact-retention findings.

**Learnings:**
- The immediate secret scan passed; the remaining question is repo policy and PR hygiene.

### 2026-05-15 - Broadcast Artifacts Removed

**By:** Codex

**Actions:**
- Removed tracked `broadcast/**` artifacts from the feature branch and changed `.gitignore` to ignore all future Foundry broadcast logs.
- Added repository policy to preserve public deployment facts in curated config/docs and to commit CE review artifacts only when intentionally referenced.
- Confirmed `config/fame-public.env` retains the deployed Base router address.

**Verification:**
- Secret scan over the working tree and tracked content found no raw RPC URLs, private keys, mnemonics, bearer tokens, explorer API keys, or password literals.
