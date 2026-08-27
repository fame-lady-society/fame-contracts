import { readFileSync } from "node:fs";

import { parse } from "dotenv";
import { getAddress } from "viem";

const values = parse(
  readFileSync(new URL("../../config/fame-public.env", import.meta.url)),
);

function requiredAddress(name) {
  const value = values[name];
  if (!value) throw new Error(`${name} is missing from config/fame-public.env`);
  return getAddress(value);
}

function requiredHash(name) {
  const value = values[name];
  if (!value || !/^0x[0-9a-fA-F]{64}$/.test(value)) {
    throw new Error(`${name} must be a 32-byte hash in config/fame-public.env`);
  }
  return value.toLowerCase();
}

export const PUBLIC_MIGRATION_CONFIG = Object.freeze({
  societySafe: requiredAddress("SOCIETY_SAFE_ADDRESS"),
  societySafeProxyRuntimeHash: requiredHash(
    "SOCIETY_SAFE_PROXY_RUNTIME_HASH",
  ),
  ethereumDonationVault: requiredAddress(
    "ETHEREUM_SOCIETY_DONATION_VAULT_ADDRESS",
  ),
  ethereumDonationVaultDeploymentTx: requiredHash(
    "ETHEREUM_SOCIETY_DONATION_VAULT_DEPLOYMENT_TX",
  ),
  ethereumDonationVaultRuntimeHash: requiredHash(
    "ETHEREUM_SOCIETY_DONATION_VAULT_RUNTIME_HASH",
  ),
});
