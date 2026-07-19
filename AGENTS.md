# Repository Instructions

## Environment And Secrets

- `docs/solutions/` contains documented solutions to past problems and workflow learnings, organized by category with YAML frontmatter such as `module`, `tags`, and `problem_type`; it is relevant when implementing or debugging in documented areas.
- Keep public deployment constants in `config/fame-public.env`.
- Keep secrets in Doppler. This includes RPC URLs, private keys, mnemonics, explorer API keys, snipe keys, and upload wallet keys.
- Prefer Foundry chain aliases from `foundry.toml` (`base`, `base_sepolia`, `sepolia`) instead of passing raw RPC URLs in docs or scripts.
- Do not commit Foundry `broadcast/` logs. Preserve public deployment facts in curated config/docs instead of generated transaction artifacts.
- Commit `.context/compound-engineering/ce-review/` run artifacts only when they are intentionally referenced by tracked todos, plans, or review summaries; scan them for secrets before staging.
- When a command needs both public config and secrets, load public config first, then run through Doppler:

```sh
set -a
source config/fame-public.env
set +a
doppler run -- forge test
```

- Do not echo RPC URLs, private keys, mnemonics, or explorer API keys in logs.
- If a required value is public but missing, add it to `config/fame-public.env`. If it is secret, report the missing Doppler variable name to the user rather than inventing a placeholder.

## Sandbox, Doppler, And Integration Verification

- Codex's default command sandbox may be unable to access macOS Keychain, Doppler credentials, local services, or external RPC and network endpoints.
- Never interpret a failure observed only inside the sandbox as proof that a credential, Doppler configuration, RPC URL, keychain item, or local service is missing.
- If an important command fails with a keyring error, DNS or connection failure, a missing variable normally supplied by Doppler, or inability to reach a local service, rerun the exact command with escalated sandbox permissions before diagnosing the environment or asking the user to reconfigure anything.
- For Doppler, do not ask the user to run `doppler login` or `doppler setup` until these read-only checks also fail with escalated permissions:

```sh
doppler configure get project
doppler configure get config
```

- When public configuration and Doppler secrets are both required, preserve the loading order shown above and run the resulting command with escalated permissions.
- A fork, integration, deployment-validation, or runtime test that skips because its RPC, credentials, or environment are unavailable is **not** a passing verification gate. Report it as `not executed`, never as verified, green, or covered by local tests.
- Do not declare implementation complete when its Definition of Done requires an environment-backed gate that has not actually run. Escalate first; if it still cannot run, report the exact unresolved gate.
