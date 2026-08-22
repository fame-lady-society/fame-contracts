import { spawn } from "node:child_process";
import process from "node:process";

import { config as loadEnv } from "dotenv";
import {
  createPublicClient,
  createWalletClient,
  decodeFunctionResult,
  http,
  keccak256,
  parseEther,
  toHex,
} from "viem";
import { base, mainnet, polygon } from "viem/chains";

import {
  FACTORY_ABI,
  SAFE_ABI,
  assertManifest,
  buildBootstrap,
  classifySafeState,
  deriveDeployment,
  validateDeploymentEvents,
} from "./core.mjs";
import { SAFE_MANIFEST } from "./manifest.mjs";
import { readSafeSnapshot, runtimeHash } from "./safe-state.mjs";

loadEnv();
assertManifest();

const FORKS = [
  { chain: base, envName: "BASE_RPC_URL" },
  { chain: polygon, envName: "POLYGON_RPC_URL" },
  { chain: mainnet, envName: "ETHEREUM_RPC_URL" },
];
const LOCAL_RPC_URL = "http://127.0.0.1:18545";
const STARTUP_TIMEOUT_MS = 30_000;

function assertSourceRpc(value, envName) {
  if (!value) throw new Error(`${envName} is missing`);
  const url = new URL(value);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`${envName} must use HTTP or HTTPS`);
  }
  return value;
}

function makeClients(chain) {
  if (!LOCAL_RPC_URL.startsWith("http://127.0.0.1:")) {
    throw new Error("rehearsal write transport must be loopback-only");
  }
  const transport = http(LOCAL_RPC_URL, { retryCount: 0 });
  return {
    publicClient: createPublicClient({ chain, transport }),
    walletClient: createWalletClient({
      account: SAFE_MANIFEST.deployer,
      chain,
      transport,
    }),
  };
}

async function waitForAnvil(child, publicClient, chainId) {
  const deadline = Date.now() + STARTUP_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error("local Anvil fork exited before becoming ready");
    }
    try {
      if ((await publicClient.getChainId()) === chainId) return;
    } catch {
      // Anvil has not opened its local port yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("timed out waiting for local Anvil fork");
}

function requireHash(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label} did not match the immutable manifest`);
  }
}

async function stopAnvil(child) {
  if (child.exitCode !== null) return;
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 2_000);
    child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
    child.kill("SIGTERM");
  });
}

async function rehearseFork({ chain, envName }) {
  const sourceRpc = assertSourceRpc(process.env[envName], envName);
  const child = spawn(
    "anvil",
    [
      "--fork-url",
      sourceRpc,
      "--chain-id",
      String(chain.id),
      "--port",
      "18545",
      "--silent",
    ],
    { stdio: "ignore" },
  );
  const { publicClient, walletClient } = makeClients(chain);

  try {
    await waitForAnvil(child, publicClient, chain.id);
    await publicClient.request({
      method: "anvil_impersonateAccount",
      params: [SAFE_MANIFEST.deployer],
    });
    await publicClient.request({
      method: "anvil_setBalance",
      params: [SAFE_MANIFEST.deployer, toHex(parseEther("100"))],
    });

    const manifest = SAFE_MANIFEST.safe;
    const [factoryCode, singletonCode, handlerCode, multiSendCode, proxyCode] =
      await Promise.all([
        publicClient.getBytecode({ address: manifest.factory }),
        publicClient.getBytecode({ address: manifest.singleton }),
        publicClient.getBytecode({ address: manifest.fallbackHandler }),
        publicClient.getBytecode({ address: manifest.multiSendCallOnly }),
        publicClient.readContract({
          address: manifest.factory,
          abi: FACTORY_ABI,
          functionName: "proxyCreationCode",
        }),
      ]);
    requireHash(
      "factory runtime",
      runtimeHash(factoryCode),
      manifest.factoryCodeHash,
    );
    requireHash(
      "singleton runtime",
      runtimeHash(singletonCode),
      manifest.singletonCodeHash,
    );
    requireHash(
      "fallback handler runtime",
      runtimeHash(handlerCode),
      manifest.fallbackHandlerCodeHash,
    );
    requireHash(
      "MultiSendCallOnly runtime",
      runtimeHash(multiSendCode),
      manifest.multiSendCallOnlyCodeHash,
    );

    const deployment = deriveDeployment(proxyCode);
    requireHash(
      "proxy creation code",
      deployment.proxyCreationCodeHash,
      manifest.proxyCreationCodeHash,
    );
    if (deployment.predictedAddress !== manifest.predictedAddress) {
      throw new Error("CREATE2 result did not match the approved Safe address");
    }
    const existingCode = await publicClient.getBytecode({
      address: manifest.predictedAddress,
    });
    if (existingCode && existingCode !== "0x") {
      throw new Error("approved Safe address is already occupied on the fork");
    }

    const deploymentSimulation = await publicClient.call({
      account: SAFE_MANIFEST.deployer,
      to: manifest.factory,
      data: deployment.transactionData,
    });
    const simulatedAddress = decodeFunctionResult({
      abi: FACTORY_ABI,
      functionName: manifest.creationMethod,
      data: deploymentSimulation.data,
    });
    if (simulatedAddress !== manifest.predictedAddress) {
      throw new Error("deployment simulation returned an unexpected address");
    }

    const deploymentHash = await walletClient.sendTransaction({
      to: manifest.factory,
      data: deployment.transactionData,
    });
    const deploymentReceipt = await publicClient.waitForTransactionReceipt({
      hash: deploymentHash,
    });
    if (deploymentReceipt.status !== "success") {
      throw new Error("local deployment transaction reverted");
    }
    validateDeploymentEvents(deploymentReceipt.logs, deployment);

    const deployedCode = await publicClient.getBytecode({
      address: manifest.predictedAddress,
    });
    const bootstrapSnapshot = await readSafeSnapshot(
      publicClient,
      deployedCode ?? "0x",
    );
    const bootstrapState = classifySafeState(bootstrapSnapshot);
    if (bootstrapState.phase !== "bootstrap-ready") {
      throw new Error("deployed Safe did not match the bootstrap-ready state");
    }

    const bootstrap = buildBootstrap();
    const bootstrapSimulation = await publicClient.call({
      account: SAFE_MANIFEST.deployer,
      to: manifest.predictedAddress,
      data: bootstrap.transactionData,
    });
    const simulatedSuccess = decodeFunctionResult({
      abi: SAFE_ABI,
      functionName: "execTransaction",
      data: bootstrapSimulation.data,
    });
    if (!simulatedSuccess)
      throw new Error("bootstrap simulation returned false");

    const bootstrapHash = await walletClient.sendTransaction({
      to: manifest.predictedAddress,
      data: bootstrap.transactionData,
    });
    const bootstrapReceipt = await publicClient.waitForTransactionReceipt({
      hash: bootstrapHash,
    });
    if (bootstrapReceipt.status !== "success") {
      throw new Error("local bootstrap transaction reverted");
    }

    const finalSnapshot = await readSafeSnapshot(publicClient, deployedCode);
    const finalState = classifySafeState(finalSnapshot);
    if (finalState.phase !== "complete") {
      throw new Error("Safe did not reach the exact terminal 7-of-15 state");
    }

    return {
      chain: chain.name,
      chainId: chain.id,
      deploymentGas: deploymentReceipt.gasUsed,
      bootstrapGas: bootstrapReceipt.gasUsed,
      finalOwners: finalSnapshot.owners.length,
      finalThreshold: finalSnapshot.threshold,
      finalNonce: finalSnapshot.nonce,
      payloadHashes: {
        deployment: keccak256(deployment.transactionData),
        bootstrap: keccak256(bootstrap.transactionData),
      },
    };
  } finally {
    await stopAnvil(child);
  }
}

for (const fork of FORKS) {
  const result = await rehearseFork(fork);
  console.log(
    [
      `${result.chain} (${result.chainId})`,
      `deployment gas ${result.deploymentGas}`,
      `bootstrap gas ${result.bootstrapGas}`,
      `${result.finalOwners} owners`,
      `threshold ${result.finalThreshold}`,
      `nonce ${result.finalNonce}`,
      `deployment payload ${result.payloadHashes.deployment}`,
      `bootstrap payload ${result.payloadHashes.bootstrap}`,
    ].join(" · "),
  );
}
