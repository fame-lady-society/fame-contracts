---
title: Public Config With Doppler Secrets And Foundry Aliases
date: 2026-05-12
category: docs/solutions/workflow-issues
module: repository-configuration
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - Contract repos have public deployment constants and secret runtime values.
  - Deployment docs or scripts currently rely on a large local .env file.
  - Foundry commands need RPC, explorer, or private-key values without exposing them in docs.
related_components:
  - documentation
  - tooling
tags:
  - public-config
  - doppler
  - foundry
  - environment
  - rpc-aliases
  - secrets
  - release-workflow
---

# Public Config With Doppler Secrets And Foundry Aliases

## Context

The repo had a mixed environment model: a large inferred local `.env` held public contract addresses beside secret-shaped values, while release docs still taught `source .env`, raw RPC variables, and direct private-key exports. That made setup brittle and made command examples harder to audit for secret leakage.

The cleanup split public deployment constants from secrets across [config/fame-public.env](/home/user/Development/fame-contracts/config/fame-public.env:1), Doppler, [foundry.toml](/home/user/Development/fame-contracts/foundry.toml:18), [README.md](/home/user/Development/fame-contracts/README.md:7), [docs/fame-release-plan.md](/home/user/Development/fame-contracts/docs/fame-release-plan.md:3), and [AGENTS.md](/home/user/Development/fame-contracts/AGENTS.md:3).

Session history enrichment was requested, but skipped because the session-history extraction scripts referenced by the skill were not available in the installed skill directories.

## Guidance

Keep public deployment values and secret runtime values separate.

Use `config/fame-public.env` for public chain IDs and contract addresses:

```sh
set -a
source config/fame-public.env
set +a
```

Use Doppler for RPC URLs, explorer API keys, private keys, mnemonics, upload wallet keys, and one-off signing keys:

```sh
doppler run -- forge test
```

Prefer Foundry aliases from `foundry.toml` instead of raw RPC URLs:

```sh
doppler run -- forge test --fork-url base
doppler run -- forge script --chain base script/DeployFameRouter.s.sol:DeployFameRouter --verify --broadcast --rpc-url base
doppler run -- forge script --chain base_sepolia script/Deploy.s.sol:Deploy --rpc-url base_sepolia
```

When a command passes a secret as a CLI argument, expand it inside the Doppler process rather than in the outer shell:

```sh
doppler run -- sh -c 'forge script script/Deploy.s.sol --rpc-url base --private-key "$BASE_DEPLOYER_PRIVATE_KEY" --broadcast'
```

If a value is public and missing, add it to `config/fame-public.env`. If a value is secret and missing, report the Doppler variable name to the user instead of inventing a placeholder. For example, `BASE_SEPOLIA_FAME_ADDRESS` stayed commented out because the previous local `.env` value had a trailing `.` and was not a valid address.

## Why This Matters

Deployment docs are often copied straight into terminals. If examples use raw RPC URLs, direct private-key exports, or shell expansion before Doppler injects secrets, sensitive values can leak through shell history, terminal scrollback, CI logs, failed command traces, or screenshots.

The split also makes the repo easier for agents and contributors to operate. Public addresses are discoverable in version control, while sensitive values stay in Doppler. Foundry aliases make commands shorter and easier to review because `--rpc-url base` is clearer than a raw provider URL.

## When to Apply

- A contract repo has deployment scripts, release plans, public addresses, and private deployment credentials.
- Documentation uses `.env` as a catch-all for both public and secret values.
- Foundry commands repeat raw RPC environment variables instead of configured aliases.
- A command example needs private keys, explorer keys, RPC URLs, mnemonics, upload keys, or snipe keys.
- A public value from local config is malformed or unconfirmed and should not be promoted into reusable setup.

## Examples

Public config plus Doppler secrets:

```sh
set -a
source config/fame-public.env
set +a
doppler run -- forge test
```

Foundry config and targeted router verification:

```sh
forge config
doppler run -- forge test --match-path test/router/FameRouter.t.sol
```

Secret CLI argument expansion inside Doppler:

```sh
doppler run -- sh -c 'cast wallet address --private-key "$BASE_DEPLOYER_PRIVATE_KEY"'
```

Invalid public value handling:

```sh
# Fill after confirming the current deployed value. The previous local .env
# value ended with a trailing "." and is not a valid address.
# BASE_SEPOLIA_FAME_ADDRESS=
```

Verification from the cleanup:

```sh
forge config
forge test --match-path test/router/FameRouter.t.sol
```

`forge test --match-path test/router/FameRouter.t.sol` passed 27 tests. Foundry emitted a non-fatal sandbox warning because it could not write `/home/user/.foundry/cache/signatures`.

## Related

- [README.md](/home/user/Development/fame-contracts/README.md:7)
- [docs/fame-release-plan.md](/home/user/Development/fame-contracts/docs/fame-release-plan.md:3)
- [foundry.toml](/home/user/Development/fame-contracts/foundry.toml:18)
- [config/fame-public.env](/home/user/Development/fame-contracts/config/fame-public.env:1)
- [docs/router/fame-router-validation.md](/home/user/Development/fame-contracts/docs/router/fame-router-validation.md:23)
- [docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md](/home/user/Development/fame-contracts/docs/plans/2026-05-11-001-feat-fame-multi-leg-router-plan.md:53)
