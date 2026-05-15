---
title: Keep Generated Deployment Artifacts Out Of The Repo
date: 2026-05-15
category: docs/solutions/workflow-issues
module: fame-router
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - Foundry deployment or fork-evidence commands produce generated calldata or transaction logs.
  - Public deployment addresses need to remain discoverable without committing raw generated artifacts.
tags: [foundry, deployment, artifacts, secrets, router]
---

# Keep Generated Deployment Artifacts Out Of The Repo

## Context

Foundry `broadcast/` logs and router fork-evidence artifacts can look harmless because they usually contain public transaction metadata or deterministic calldata. They are still generated operational output, and committing them creates long-lived PR noise plus an avoidable risk that a future generated file includes sensitive or undesirable data.

The safer pattern is to keep curated public deployment facts in reviewed config/docs and keep generated artifacts out of the production-facing path unless a test explicitly needs them.

## Guidance

Do not commit Foundry `broadcast/` output. Ignore `broadcast/` and record public deployment facts in `config/fame-public.env` or release docs:

```sh
BASE_FAME_ROUTER_ADDRESS=0xAdefa5860389E8936ebf2977e1Fb4a365aA39636
```

When a generated artifact is intentionally kept for tests, label it as evidence rather than production input. For router solver artifacts, `productionExecutable: false` means a production caller must materialize a fresh route before using calldata:

```ts
if (!artifact.productionExecutable) {
  throw new Error("Fork-evidence artifacts require production materialization before calldata use");
}
```

For CE review artifacts, commit them only when a tracked todo, plan, or summary references them, and scan them before staging.

## Why This Matters

Generated deployment logs are not a stable interface. They can grow quickly, obscure the meaningful diff, and accidentally preserve operational details that should have stayed local. Curated config keeps the useful facts visible while avoiding raw run-log history.

The same principle applies to fork evidence. Test calldata is valuable for parity checks, but production execution should set current recipients, deadlines, minimums, and router-bound Universal Router payloads from a fresh quote.

## When to Apply

- After any `forge script --broadcast` or deployment rehearsal.
- When adding generated solver artifacts that include encoded route calldata.
- Before pushing branches that contain `.context/compound-engineering/ce-review/**` outputs.

## Examples

Good:

```sh
config/fame-public.env
docs/router/fame-router-validation.md
```

Avoid:

```sh
broadcast/DeployFameRouter.s.sol/8453/run-latest.json
```

## Related

- [Public Config With Doppler Secrets And Foundry Aliases](./public-config-doppler-foundry-aliases-2026-05-12.md)
- [FAME Router Validation](../../router/fame-router-validation.md)
