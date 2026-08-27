import { mkdir, rename } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import SafeApiKitPackage from "@safe-global/api-kit";
import { config as loadEnv } from "dotenv";
import { createPublicClient, getAddress, http } from "viem";
import { base, mainnet, polygon } from "viem/chains";

import { writeJsonAtomic } from "../../js/lib/atomic-json.mjs";
import { publicBatchRecord } from "./artifact-package.mjs";
import { safeErrorMessage } from "./errors.mjs";
import { readMigrationSnapshot } from "./live-state.mjs";
import { ADDRESSES, buildMigrationArtifacts } from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";

loadEnv();

const SafeApiKit = SafeApiKitPackage.default ?? SafeApiKitPackage;

const CHAIN_CONFIG = Object.freeze({
  1: { chain: mainnet, envName: "ETHEREUM_RPC_URL" },
  137: { chain: polygon, envName: "POLYGON_RPC_URL" },
  8453: { chain: base, envName: "BASE_RPC_URL" },
});
const RPC_TIMEOUT_MS = 60_000;
const SAFE_SERVICE_TIMEOUT_MS = 30_000;

function requiredRpc(envName) {
  const value = process.env[envName];
  if (!value) throw new Error(`${envName} is missing`);
  const url = new URL(value);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`${envName} must be an HTTP(S) RPC URL`);
  }
  return value;
}

function makeClients() {
  return Object.fromEntries(
    Object.entries(CHAIN_CONFIG).map(([chainId, { chain, envName }]) => [
      chainId,
      createPublicClient({
        chain,
        transport: http(requiredRpc(envName), {
          retryCount: 2,
          timeout: RPC_TIMEOUT_MS,
        }),
      }),
    ]),
  );
}

function readNewDonationVaultArgument() {
  const configured = PUBLIC_MIGRATION_CONFIG.ethereumDonationVault;
  const argumentIndex = process.argv.indexOf("--new-donation-vault");
  if (argumentIndex !== -1) {
    const value = process.argv[argumentIndex + 1];
    if (!value || value.startsWith("--")) {
      throw new Error("--new-donation-vault requires an address");
    }
    if (getAddress(value) !== configured) {
      throw new Error(
        "--new-donation-vault does not match config/fame-public.env",
      );
    }
  }
  return configured;
}

async function withDeadline(promise, label, timeoutMs) {
  let timeout;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error(`${label} timed out after ${timeoutMs}ms`)),
          timeoutMs,
        );
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

async function readTransactionServiceState(snapshot) {
  const rateLimitedState = (address, onchainNonce) => ({
    address,
    onchainNonce,
    status: "not-executed-safe-service-rate-limited",
    nextServiceNonce: null,
    pendingTransactions: null,
  });
  const readPendingWithRetry = async (api, address, nonce) => {
    let lastError;
    for (const delayMs of [0, 1_000, 2_000, 4_000]) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      try {
        return await withDeadline(
          api.getPendingTransactions(address, nonce),
          "Safe Transaction Service request",
          SAFE_SERVICE_TIMEOUT_MS,
        );
      } catch (error) {
        lastError = error;
        if (!String(error?.message).includes("Too Many Requests")) throw error;
      }
    }
    throw lastError;
  };

  const chains = {};
  let serviceRateLimited = false;
  for (const chainId of [1, 137, 8453]) {
    const api = new SafeApiKit({ chainId: BigInt(chainId) });
    const chainState = {};
    for (const [label, address] of [
      ["oldSafe", ADDRESSES.oldSafes[chainId]],
      ["newSafe", ADDRESSES.newSafe],
    ]) {
      const onchainNonce = Number(snapshot.chains[chainId][`${label}Nonce`]);
      if (serviceRateLimited) {
        chainState[label] = rateLimitedState(address, onchainNonce);
        continue;
      }
      let pending;
      try {
        pending = await readPendingWithRetry(api, address, onchainNonce);
      } catch (error) {
        if (!String(error?.message).includes("Too Many Requests")) throw error;
        serviceRateLimited = true;
        chainState[label] = rateLimitedState(address, onchainNonce);
        continue;
      }
      const pendingTransactions = pending.results.map((transaction) => ({
        safeTxHash: transaction.safeTxHash,
        nonce: transaction.nonce,
        submissionDate: transaction.submissionDate,
      }));
      chainState[label] = {
        address,
        onchainNonce,
        status: "verified-no-pending-transactions",
        nextServiceNonce:
          pendingTransactions.length === 0
            ? onchainNonce
            : Math.max(...pendingTransactions.map((transaction) => transaction.nonce)) +
              1,
        pendingTransactions,
      };
      if (pendingTransactions.length > 0) {
        throw new Error(
          `chain ${chainId} ${label} has ${pendingTransactions.length} pending Safe Transaction Service transaction(s) at or after on-chain nonce ${onchainNonce}`,
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 350));
    }
    chains[chainId] = chainState;
  }
  return {
    checkedAt: new Date().toISOString(),
    status: Object.values(chains).some((chain) =>
      Object.values(chain).some((safe) =>
        safe.status.startsWith("not-executed"),
      ),
    )
      ? "not-fully-executed"
      : "verified-no-pending-transactions",
    policy:
      "generation fails on observed pending proposals; a rate-limited audit is recorded as not executed and requires a manual Safe queue check before proposal",
    chains,
  };
}

async function main() {
  const generatedAt = new Date();
  const newDonationVaultAddress = readNewDonationVaultArgument();
  const clients = makeClients();
  const snapshot = await readMigrationSnapshot(clients, generatedAt, {
    newDonationVaultAddress,
  });
  const transactionService = await readTransactionServiceState(snapshot);
  const artifacts = buildMigrationArtifacts(snapshot, {
    createdAt: generatedAt.getTime(),
    newDonationVaultAddress,
  });
  const runId = generatedAt
    .toISOString()
    .replace(/[-:]/g, "")
    .replace(/\.\d{3}Z$/, "Z");
  const outputDirectory = path.resolve(
    "out",
    "society-safe-migration",
    runId,
  );
  const outputRoot = path.dirname(outputDirectory);
  const workingDirectory = path.join(
    outputRoot,
    `.${runId}.${process.pid}.incomplete`,
  );
  await mkdir(outputRoot, { recursive: true });
  await mkdir(workingDirectory);

  for (const batch of artifacts.batches) {
    await writeJsonAtomic(
      path.join(workingDirectory, batch.filename),
      batch.builder,
    );
  }

  const operatorFile = "operator-calldata-not-safe-import.json";
  await writeJsonAtomic(path.join(workingDirectory, operatorFile), {
    schemaVersion: 1,
    status: "raw-calldata-only-not-a-safe-transaction-builder-file",
    generatedAt: snapshot.generatedAt,
    calls: artifacts.operatorCalls,
  });

  const reviewManifest = {
    schemaVersion: 1,
    status: "unsigned-review-artifacts-no-proposal-no-signature-no-broadcast",
    generatedAt: snapshot.generatedAt,
    destinationSafe: ADDRESSES.newSafe,
    replacementDonationVault: artifacts.newDonationVault,
    sourcePlan:
      "docs/plans/2026-08-20-001-ops-society-vault-cross-chain-migration-plan.md",
    sourceApproval:
      "docs/plans/2026-08-20-001-ops-society-vault-asset-approval.md",
    transactionBuilder: {
      fileSchemaVersion: "1.0",
      appVersion: "2.1.0",
      officialSource:
        "https://github.com/safe-global/safe-wallet-monorepo/tree/main/apps/tx-builder",
      encoding: "raw to/value/data; Safe app constructs the outer Safe transaction",
    },
    warnings: [
      "Import each file only while connected to its exact source Safe and chain.",
      "Safe Transaction Builder files do not encode a Safe nonce; verify the nonce shown by Safe before creating each proposal.",
      ...(transactionService.status === "not-fully-executed"
        ? [
            "Safe Transaction Service queue audit was rate-limited and is NOT VERIFIED; inspect each Safe queue manually before creating any proposal.",
          ]
        : []),
      "Do not execute any conditional file until every executionGate in this manifest is satisfied.",
      "The new-Safe E-POST-MIGRATION-AUTHORITY proposal must reserve nonce 1 and be fully signed before E-FLS-AUTHORITY-HANDOFF executes.",
      "Tenderly and local fork simulations are review evidence, not authorization to sign or execute.",
    ],
    snapshot,
    transactionService,
    batches: artifacts.batches.map(publicBatchRecord),
    operatorCalldataFile: operatorFile,
    blocked: artifacts.blocked,
    externalPrerequisites: artifacts.externalPrerequisites,
  };
  const reviewFile = "review-manifest.json";
  await writeJsonAtomic(
    path.join(workingDirectory, reviewFile),
    reviewManifest,
  );

  const index = {
    schemaVersion: 1,
    generatedAt: snapshot.generatedAt,
    status: reviewManifest.status,
    reviewManifest: reviewFile,
    safeTransactionBuilderFiles: artifacts.batches.map((batch) => ({
      id: batch.id,
      filename: batch.filename,
      chainId: batch.chainId,
      sourceSafe: batch.sourceSafe,
      checksum: batch.builder.meta.checksum,
      executionGate: batch.executionGate,
    })),
    operatorCalldataFile: operatorFile,
    blocked: artifacts.blocked,
  };
  await writeJsonAtomic(path.join(workingDirectory, "index.json"), index);
  await rename(workingDirectory, outputDirectory);

  process.stdout.write(
    [
      `Generated ${artifacts.batches.length} unsigned Safe Transaction Builder files.`,
      `Output: ${outputDirectory}`,
      `Review: ${path.join(outputDirectory, reviewFile)}`,
      `Pinned blocks: Ethereum ${snapshot.chains[1].blockNumber}, Polygon ${snapshot.chains[137].blockNumber}, Base ${snapshot.chains[8453].blockNumber}`,
      `Blocked unresolved items: ${artifacts.blocked.map((item) => item.id).join(", ")}`,
    ].join("\n") + "\n",
  );
}

main().catch((error) => {
  process.stderr.write(
    `Migration artifact generation failed: ${safeErrorMessage(
      error,
      Object.values(CHAIN_CONFIG).map(({ envName }) => envName),
    )}\n`,
  );
  process.exitCode = 1;
});
