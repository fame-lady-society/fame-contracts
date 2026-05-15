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
