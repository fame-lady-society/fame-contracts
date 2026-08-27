# Society Safe deployment portal

This is a local-only, one-time operator portal for deploying the approved Society Safe at the same
address on Base, Polygon, and Ethereum, then installing the final 7-of-15 council through one atomic
Safe transaction on each chain.

It contains no private key, backend, configurable addresses, asset migration calls, or production
deployment configuration. Rabby remains the signing boundary.

## Run

```sh
npm run society-safe:portal:test
npm run society-safe:portal
```

To rehearse the exact deployment and bootstrap payloads against local Anvil
forks of Base, Polygon, and Ethereum:

```sh
npm run society-safe:portal:rehearse
```

The rehearsal reads the three RPC URLs from `.env`, impersonates the approved
deployer only inside a loopback-bound Anvil process, and never sends a write to
an upstream RPC.

Open `http://127.0.0.1:4173`, connect Rabby, and verify the connected account is
`0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252`.

Complete Base, Polygon, and Ethereum in that order. For each chain, the portal:

1. verifies chain ID, canonical Safe component bytecode, proxy creation code, deterministic address,
   destination vacancy or deployed Safe state, balance, and transaction simulation;
2. requests an explicit Rabby confirmation for `createProxyWithNonceL2` and requires both
   `ProxyCreation` and `ProxyCreationL2` in the receipt;
3. verifies the deployment receipt and exact deployer-only Safe state;
4. requests a separate Rabby confirmation for the nonce-0 atomic 7-of-15 bootstrap; and
5. verifies the exact owner order, threshold, nonce, fallback handler, guard, modules, and deployer
   removal.

Transaction evidence is stored only in browser local storage and can be downloaded as JSON.

## Stop conditions

Stop if any check is red, if Rabby shows a different target or calldata than the portal, or if the
portal reports an unexpected receipt or Safe state. Do not fund the temporary Safe or grant it any
authority before the bootstrap is verified.
