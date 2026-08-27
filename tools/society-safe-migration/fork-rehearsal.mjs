import { spawn } from "node:child_process";
import { access, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import { config as loadEnv } from "dotenv";
import {
  concatHex,
  createPublicClient,
  createWalletClient,
  encodeFunctionData,
  getAddress,
  http,
  keccak256,
  namehash,
  parseAbi,
  parseEther,
  toBytes,
  toHex,
} from "viem";
import { base, mainnet, polygon } from "viem/chains";

import { writeJsonAtomic } from "../../js/lib/atomic-json.mjs";
import {
  MULTISEND_ABI,
  buildApprovedHashSignature,
  encodeMultiSendCalls,
} from "../society-safe-portal/core.mjs";
import { ZERO_ADDRESS } from "../society-safe-portal/manifest.mjs";
import {
  groupBatchesByChain,
  publicBatchRecord,
  validateBatchPayload,
  validateOperatorPayload,
  validateReviewManifest,
} from "./artifact-package.mjs";
import { safeErrorMessage } from "./errors.mjs";
import {
  ADDRESSES,
  CURRENT_FLS_TOKEN_IDS,
  MIGRATION_ENS_NODE,
  MIGRATION_ROLES,
  SQUAD_TOKEN_IDS,
} from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";
import { validateChecksum } from "./transaction-builder.mjs";

loadEnv();

const LOCAL_PORT = 18546;
const LOCAL_RPC_URL = `http://127.0.0.1:${LOCAL_PORT}`;
const MULTISEND_CALL_ONLY_V1_3_0 =
  "0x40A2aCCbd92BCA938b02010E17A5b8929b49130D";
const EXECUTION_SUCCESS_TOPIC = keccak256(
  toBytes("ExecutionSuccess(bytes32,uint256)"),
);
const EXECUTION_FAILURE_TOPIC = keccak256(
  toBytes("ExecutionFailure(bytes32,uint256)"),
);
const SAFE_EXECUTION_ABI = parseAbi([
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
  "function approveHash(bytes32 hashToApprove)",
  "function getTransactionHash(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce) view returns (bytes32)",
  "function execTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,bytes signatures) returns (bool success)",
]);
const ERC20_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
]);
const ERC721_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function ownerOf(uint256) view returns (address)",
]);
const ERC1155_ABI = parseAbi([
  "function balanceOf(address,uint256) view returns (uint256)",
]);
const OWNABLE_ABI = parseAbi([
  "function owner() view returns (address)",
  "function pendingOwner() view returns (address)",
]);
const FAME_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function getSkipNFT(address) view returns (bool)",
]);
const FLS_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function owner() view returns (address)",
  "function pendingOwner() view returns (address)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function royaltyInfo(uint256,uint256) view returns (address,uint256)",
]);
const FEE_ABI = parseAbi([
  "function feeRecipient() view returns (address)",
]);
const ROLES_ABI = parseAbi([
  "function rolesOf(address) view returns (uint256)",
]);
const DONATION_ABI = parseAbi([
  "function vault() view returns (address)",
  "function wrappedNFT() view returns (address)",
  "function underlying() view returns (address)",
]);
const ENS_REGISTRY_ABI = parseAbi([
  "function owner(bytes32) view returns (address)",
  "function resolver(bytes32) view returns (address)",
]);
const ENS_RESOLVER_ABI = parseAbi([
  "function addr(bytes32) view returns (address)",
  "function name(bytes32) view returns (string)",
]);

const CHAIN_CONFIG = Object.freeze({
  1: { chain: mainnet, envName: "ETHEREUM_RPC_URL" },
  137: { chain: polygon, envName: "POLYGON_RPC_URL" },
  8453: { chain: base, envName: "BASE_RPC_URL" },
});

function sameAddress(left, right) {
  return left.toLowerCase() === right.toLowerCase();
}

function requireAddress(label, actual, expected) {
  if (!sameAddress(actual, expected)) {
    throw new Error(`${label}: expected ${expected}, received ${actual}`);
  }
}

function requireEqual(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${expected}, received ${actual}`);
  }
}

function requiredRpc(envName) {
  const value = process.env[envName];
  if (!value) throw new Error(`${envName} is missing`);
  return value;
}

async function latestArtifactDirectory() {
  const root = path.resolve("out", "society-safe-migration");
  const entries = (await readdir(root, { withFileTypes: true }))
    .filter(
      (entry) => entry.isDirectory() && /^\d{8}T\d{6}Z$/u.test(entry.name),
    )
    .map((entry) => entry.name)
    .sort()
    .reverse();
  for (const entry of entries) {
    const candidate = path.join(root, entry);
    try {
      await Promise.all([
        access(path.join(candidate, "index.json")),
        access(path.join(candidate, "review-manifest.json")),
      ]);
      return candidate;
    } catch {
      // Ignore incomplete historical output directories.
    }
  }
  throw new Error("no complete generated migration artifacts found");
}

function argumentValue(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
  return value;
}

async function waitForAnvil(child, publicClient, chainId) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error("Anvil fork exited during startup");
    try {
      if ((await publicClient.getChainId()) === chainId) return;
    } catch {
      // The local listener is not ready yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("timed out waiting for Anvil fork");
}

async function stopAnvil(child) {
  if (child.exitCode !== null) return;
  const waitForExit = (timeoutMs) =>
    new Promise((resolve) => {
      const onExit = () => {
        clearTimeout(timeout);
        resolve(true);
      };
      const timeout = setTimeout(() => {
        child.off("exit", onExit);
        resolve(false);
      }, timeoutMs);
      child.once("exit", onExit);
    });
  const gracefulExit = waitForExit(2_000);
  child.kill("SIGTERM");
  if (await gracefulExit) return;
  const forcedExit = waitForExit(2_000);
  if (!child.kill("SIGKILL") || !(await forcedExit)) {
    throw new Error("Anvil fork did not exit after SIGKILL");
  }
}

function localClients(chain) {
  const transport = http(LOCAL_RPC_URL, {
    retryCount: 0,
    timeout: 300_000,
  });
  return {
    publicClient: createPublicClient({ chain, transport }),
    walletFor: (account) => createWalletClient({ account, chain, transport }),
  };
}

async function impersonate(publicClient, address) {
  await publicClient.request({
    method: "anvil_impersonateAccount",
    params: [address],
  });
  await publicClient.request({
    method: "anvil_setBalance",
    params: [address, toHex(parseEther("100"))],
  });
}

function safePayload(transactions, multiSendCallOnly) {
  if (transactions.length === 1) {
    return {
      to: getAddress(transactions[0].to),
      value: BigInt(transactions[0].value),
      data: transactions[0].data,
      operation: 0,
    };
  }
  const packed = encodeMultiSendCalls(
    transactions.map((transaction) => ({
      operation: 0,
      to: transaction.to,
      value: BigInt(transaction.value),
      data: transaction.data,
    })),
  );
  return {
    to: multiSendCallOnly,
    value: 0n,
    data: encodeFunctionData({
      abi: MULTISEND_ABI,
      functionName: "multiSend",
      args: [packed],
    }),
    operation: 1,
  };
}

async function executeSafeBatch({
  publicClient,
  walletFor,
  batch,
  multiSendCallOnly,
  executionGate,
}) {
  const safeAddress = getAddress(batch.meta.createdFromSafeAddress);
  const [owners, threshold, startingNonce] = await Promise.all([
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_EXECUTION_ABI,
      functionName: "getOwners",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_EXECUTION_ABI,
      functionName: "getThreshold",
    }),
    publicClient.readContract({
      address: safeAddress,
      abi: SAFE_EXECUTION_ABI,
      functionName: "nonce",
    }),
  ]);
  const signers = [...owners]
    .slice(0, Number(threshold))
    .sort((left, right) => left.toLowerCase().localeCompare(right.toLowerCase()));
  if (signers.length !== Number(threshold)) {
    throw new Error(`${batch.meta.name}: insufficient owners for threshold`);
  }
  const payload = safePayload(batch.transactions, multiSendCallOnly);
  const hashArgs = [
    payload.to,
    payload.value,
    payload.data,
    payload.operation,
    0n,
    0n,
    0n,
    ZERO_ADDRESS,
    ZERO_ADDRESS,
    startingNonce,
  ];
  const safeTxHash = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_EXECUTION_ABI,
    functionName: "getTransactionHash",
    args: hashArgs,
  });

  for (const signer of signers) {
    await impersonate(publicClient, signer);
    const approvalHash = await walletFor(signer).writeContract({
      account: signer,
      address: safeAddress,
      abi: SAFE_EXECUTION_ABI,
      functionName: "approveHash",
      args: [safeTxHash],
    });
    await publicClient.waitForTransactionReceipt({ hash: approvalHash });
  }

  const signatures = concatHex(signers.map(buildApprovedHashSignature));
  const execArgs = [...hashArgs.slice(0, -1), signatures];
  const executor = signers[0];
  const transactionHash = await walletFor(executor).writeContract({
    account: executor,
    address: safeAddress,
    abi: SAFE_EXECUTION_ABI,
    functionName: "execTransaction",
    args: execArgs,
    gas: 55_000_000n,
  });
  const receipt = await publicClient.waitForTransactionReceipt({
    hash: transactionHash,
  });
  requireEqual(`${batch.meta.name} receipt`, receipt.status, "success");
  const executionLog = receipt.logs
    .filter((log) => sameAddress(log.address, safeAddress))
    .find((log) =>
      [EXECUTION_SUCCESS_TOPIC, EXECUTION_FAILURE_TOPIC].some(
        (topic) => log.topics[0]?.toLowerCase() === topic.toLowerCase(),
      ),
    );
  if (executionLog?.topics[0]?.toLowerCase() !== EXECUTION_SUCCESS_TOPIC.toLowerCase()) {
    const safeLogs = receipt.logs
      .filter((log) => sameAddress(log.address, safeAddress))
      .map((log) => ({ topics: log.topics, data: log.data }));
    throw new Error(
      `${batch.meta.name} did not emit ExecutionSuccess; Safe logs: ${JSON.stringify(safeLogs)}`,
    );
  }
  const finalNonce = await publicClient.readContract({
    address: safeAddress,
    abi: SAFE_EXECUTION_ABI,
    functionName: "nonce",
  });
  requireEqual(`${batch.meta.name} nonce`, finalNonce, startingNonce + 1n);
  return {
    name: batch.meta.name,
    sourceSafe: safeAddress,
    safeNonce: startingNonce.toString(),
    safeTxHash,
    transactionHash,
    gasUsed: receipt.gasUsed.toString(),
    executionGate,
  };
}

async function executeOperatorCalls(publicClient, walletFor, calls) {
  const receipts = [];
  for (const call of calls) {
    const from = getAddress(call.from);
    await impersonate(publicClient, from);
    const hash = await walletFor(from).sendTransaction({
      account: from,
      to: getAddress(call.to),
      value: BigInt(call.value),
      data: call.data,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    requireEqual(`${call.id} receipt`, receipt.status, "success");
    receipts.push({ id: call.id, transactionHash: hash, gasUsed: receipt.gasUsed.toString() });
  }
  return receipts;
}

async function verifyPolygon(publicClient) {
  const owner = await publicClient.readContract({
    address: ADDRESSES.polygonFameus,
    abi: OWNABLE_ABI,
    functionName: "owner",
  });
  requireAddress("Polygon Fameus owner", owner, ADDRESSES.newSafe);
}

async function verifyBase(publicClient, snapshot) {
  const oldSafe = ADDRESSES.oldSafes[8453];
  const [
    usdc,
    zora,
    fame,
    destinationUsdc,
    destinationZora,
    destinationFame,
    skipNft,
    ...mirrorOwners
  ] = await Promise.all([
    publicClient.readContract({ address: ADDRESSES.baseUsdc, abi: ERC20_ABI, functionName: "balanceOf", args: [oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseZora, abi: ERC20_ABI, functionName: "balanceOf", args: [oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseFame, abi: FAME_ABI, functionName: "balanceOf", args: [oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseUsdc, abi: ERC20_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseZora, abi: ERC20_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseFame, abi: FAME_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.baseFame, abi: FAME_ABI, functionName: "getSkipNFT", args: [ADDRESSES.newSafe] }),
    ...[170n, 230n, 424n, 479n].map((tokenId) =>
      publicClient.readContract({ address: ADDRESSES.baseFameMirror, abi: ERC721_ABI, functionName: "ownerOf", args: [tokenId] }),
    ),
  ]);
  requireEqual("Base old Safe USDC", usdc, 0n);
  requireEqual("Base old Safe ZORA", zora, 0n);
  requireEqual("Base old Safe FAME", fame, 0n);
  requireEqual(
    "Base destination USDC delta",
    destinationUsdc,
    BigInt(snapshot.destinationUsdcBalance) + BigInt(snapshot.usdcBalance),
  );
  requireEqual(
    "Base destination ZORA delta",
    destinationZora,
    BigInt(snapshot.destinationZoraBalance) + BigInt(snapshot.zoraBalance),
  );
  requireEqual(
    "Base destination FAME delta",
    destinationFame,
    BigInt(snapshot.destinationFameBalance) + BigInt(snapshot.fameBalance),
  );
  requireEqual("Base destination skipNFT", skipNft, true);
  mirrorOwners.forEach((owner, index) =>
    requireAddress(`Base mirror owner ${index}`, owner, ADDRESSES.newSafe),
  );
  const feeTargets = [
    ADDRESSES.baseRouter,
    ADDRESSES.baseMarketplaceV3,
    ADDRESSES.baseMarketplaceLegacy,
  ];
  const feeRecipients = await Promise.all(
    feeTargets.map((target) =>
      publicClient.readContract({
        address: target,
        abi: FEE_ABI,
        functionName: "feeRecipient",
      }),
    ),
  );
  feeRecipients.forEach((recipient, index) =>
    requireAddress(
      `Base fee recipient ${feeTargets[index]}`,
      recipient,
      ADDRESSES.newSafe,
    ),
  );
}

async function verifyEthereum(publicClient, newDonationVault, snapshot) {
  const oldSafe = ADDRESSES.oldSafes[1];
  const allFlsIds = [...CURRENT_FLS_TOKEN_IDS, ...SQUAD_TOKEN_IDS];
  const [
    oldWeth,
    newWeth,
    oldFls,
    newFls,
    flsOwner,
    pendingOwner,
    newAdmin,
    newTreasurer,
    oldAdmin,
    oldTreasurer,
    oldDonationTreasurer,
    newDonationTreasurer,
    royalty,
    ensOwner,
    ensAddress,
    funknloveRoles,
    oldFunknloveRoles,
    donationWrappedNft,
    donationUnderlying,
    donationDestination,
  ] = await Promise.all([
    publicClient.readContract({ address: ADDRESSES.weth, abi: ERC20_ABI, functionName: "balanceOf", args: [oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.weth, abi: ERC20_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "balanceOf", args: [oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: OWNABLE_ABI, functionName: "owner" }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: OWNABLE_ABI, functionName: "pendingOwner" }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.defaultAdmin, ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.treasurer, ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.defaultAdmin, oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.treasurer, oldSafe] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.treasurer, ADDRESSES.oldDonationVault] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "hasRole", args: [MIGRATION_ROLES.treasurer, newDonationVault] }),
    publicClient.readContract({ address: ADDRESSES.fls, abi: FLS_ABI, functionName: "royaltyInfo", args: [0n, 10_000n] }),
    publicClient.readContract({ address: ADDRESSES.ensRegistry, abi: ENS_REGISTRY_ABI, functionName: "owner", args: [MIGRATION_ENS_NODE] }),
    publicClient.readContract({ address: ADDRESSES.ensResolver, abi: ENS_RESOLVER_ABI, functionName: "addr", args: [MIGRATION_ENS_NODE] }),
    publicClient.readContract({ address: ADDRESSES.funknlove, abi: ROLES_ABI, functionName: "rolesOf", args: [ADDRESSES.newSafe] }),
    publicClient.readContract({ address: ADDRESSES.funknlove, abi: ROLES_ABI, functionName: "rolesOf", args: [oldSafe] }),
    publicClient.readContract({ address: newDonationVault, abi: DONATION_ABI, functionName: "wrappedNFT" }),
    publicClient.readContract({ address: newDonationVault, abi: DONATION_ABI, functionName: "underlying" }),
    publicClient.readContract({ address: newDonationVault, abi: DONATION_ABI, functionName: "vault" }),
  ]);
  requireEqual("Ethereum old Safe WETH", oldWeth, 0n);
  requireEqual(
    "Ethereum destination WETH delta",
    newWeth,
    BigInt(snapshot.destinationWethBalance) + BigInt(snapshot.wethBalance),
  );
  requireEqual("Ethereum old Safe FLS", oldFls, 0n);
  requireEqual(
    "Ethereum new Safe FLS count",
    newFls,
    BigInt(snapshot.destinationFlsBalance) + 107n,
  );
  requireAddress("FLS owner", flsOwner, ADDRESSES.newSafe);
  requireAddress("FLS pending owner", pendingOwner, ZERO_ADDRESS);
  requireEqual("new Safe FLS admin", newAdmin, true);
  requireEqual("new Safe FLS treasurer", newTreasurer, true);
  requireEqual("old Safe FLS admin", oldAdmin, false);
  requireEqual("old Safe FLS treasurer", oldTreasurer, false);
  requireEqual("old donation treasurer", oldDonationTreasurer, false);
  requireEqual("new donation treasurer", newDonationTreasurer, true);
  requireAddress("FLS royalty receiver", royalty[0], ADDRESSES.newSafe);
  requireEqual("FLS royalty bps", royalty[1], 500n);
  requireAddress("ENS owner", ensOwner, ADDRESSES.newSafe);
  requireAddress("ENS address", ensAddress, ADDRESSES.newSafe);
  if ((funknloveRoles & 2n) !== 2n) throw new Error("new Safe lacks FUNKNLOVE role 2");
  if ((oldFunknloveRoles & 2n) !== 0n) {
    throw new Error("old Safe retains FUNKNLOVE role 2");
  }
  requireAddress("replacement donation wrappedNFT", donationWrappedNft, ADDRESSES.fls);
  requireAddress("replacement donation underlying", donationUnderlying, ADDRESSES.squad);
  requireAddress("replacement donation destination", donationDestination, ADDRESSES.newSafe);
  const donationCode = await publicClient.getBytecode({ address: newDonationVault });
  requireEqual(
    "replacement donation runtime hash",
    keccak256(donationCode),
    PUBLIC_MIGRATION_CONFIG.ethereumDonationVaultRuntimeHash,
  );

  const flsOwners = await publicClient.multicall({
    allowFailure: false,
    contracts: allFlsIds.map((tokenId) => ({
      address: ADDRESSES.fls,
      abi: ERC721_ABI,
      functionName: "ownerOf",
      args: [BigInt(tokenId)],
    })),
  });
  flsOwners.forEach((owner, index) =>
    requireAddress(`FLS ownerOf ${allFlsIds[index]}`, owner, ADDRESSES.newSafe),
  );
  const squadOwners = await publicClient.multicall({
    allowFailure: false,
    contracts: SQUAD_TOKEN_IDS.map((tokenId) => ({
      address: ADDRESSES.squad,
      abi: ERC721_ABI,
      functionName: "ownerOf",
      args: [BigInt(tokenId)],
    })),
  });
  squadOwners.forEach((owner, index) =>
    requireAddress(`Squad custodian ${SQUAD_TOKEN_IDS[index]}`, owner, ADDRESSES.fls),
  );

  const relatedOwners = await Promise.all([
    publicClient.readContract({ address: ADDRESSES.yearOfTheWoman, abi: ERC721_ABI, functionName: "ownerOf", args: [8626n] }),
    publicClient.readContract({ address: ADDRESSES.baeApes, abi: ERC721_ABI, functionName: "ownerOf", args: [2520n] }),
  ]);
  relatedOwners.forEach((owner, index) =>
    requireAddress(`related ERC-721 ${index}`, owner, ADDRESSES.newSafe),
  );
  const erc1155Balances = await Promise.all([
    publicClient.readContract({ address: ADDRESSES.iamNax, abi: ERC1155_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe, 24847003539941428306476414038544445787743965496585528607173026678158422704461n] }),
    publicClient.readContract({ address: ADDRESSES.obsidianElegies, abi: ERC1155_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe, 3n] }),
    publicClient.readContract({ address: ADDRESSES.funknlove, abi: ERC1155_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe, 0n] }),
    publicClient.readContract({ address: ADDRESSES.funknlove, abi: ERC1155_ABI, functionName: "balanceOf", args: [ADDRESSES.newSafe, 1n] }),
  ]);
  ["iamNax", "obsidianElegies", "funknlove0", "funknlove1"].forEach((key, index) =>
    requireEqual(
      `related ERC-1155 balance ${key}`,
      erc1155Balances[index],
      BigInt(snapshot.destinationRelatedBalances[key]) +
        BigInt(snapshot.relatedBalances[key]),
    ),
  );

  const reverseNode = namehash(`${ADDRESSES.newSafe.slice(2).toLowerCase()}.addr.reverse`);
  const reverseResolver = await publicClient.readContract({
    address: ADDRESSES.ensRegistry,
    abi: ENS_REGISTRY_ABI,
    functionName: "resolver",
    args: [reverseNode],
  });
  const reverseName = await publicClient.readContract({
    address: reverseResolver,
    abi: ENS_RESOLVER_ABI,
    functionName: "name",
    args: [reverseNode],
  });
  requireEqual("new Safe ENS reverse name", reverseName, "vault.fameladysociety.eth");
}

async function rehearseChain({ chainId, review, batches, operatorCalls, newDonationVault }) {
  const { chain, envName } = CHAIN_CONFIG[chainId];
  const forkBlock = review.snapshot.chains[String(chainId)].blockNumber;
  const child = spawn(
    "anvil",
    [
      "--fork-url",
      requiredRpc(envName),
      "--fork-block-number",
      forkBlock,
      "--chain-id",
      String(chainId),
      "--port",
      String(LOCAL_PORT),
      "--gas-limit",
      "60000000",
      "--retries",
      "5",
      "--timeout",
      "120000",
      "--fork-retry-backoff",
      "1000",
      "--silent",
    ],
    { stdio: "ignore" },
  );
  const { publicClient, walletFor } = localClients(chain);
  try {
    await waitForAnvil(child, publicClient, chainId);
    const results = [];
    for (const { record, batch } of batches) {
      const sourceSafe = getAddress(batch.meta.createdFromSafeAddress);
      const multiSendCallOnly = sameAddress(sourceSafe, ADDRESSES.newSafe)
        ? "0xA83c336B20401Af773B6219BA5027174338D1836"
        : MULTISEND_CALL_ONLY_V1_3_0;
      results.push(
        await executeSafeBatch({
          publicClient,
          walletFor,
          batch,
          multiSendCallOnly,
          executionGate: record.executionGate,
        }),
      );
    }
    const operatorResults = await executeOperatorCalls(
      publicClient,
      walletFor,
      operatorCalls,
    );
    if (chainId === 137) await verifyPolygon(publicClient);
    if (chainId === 8453) {
      await verifyBase(publicClient, review.snapshot.chains[8453]);
    }
    if (chainId === 1) {
      await verifyEthereum(
        publicClient,
        newDonationVault,
        review.snapshot.chains[1],
      );
    }
    return { chainId, forkBlock, batches: results, operatorCalls: operatorResults, status: "passed" };
  } finally {
    await stopAnvil(child);
  }
}

async function main() {
  const artifactDirectory = path.resolve(
    argumentValue("--artifacts") ?? (await latestArtifactDirectory()),
  );
  const review = JSON.parse(
    await readFile(path.join(artifactDirectory, "review-manifest.json"), "utf8"),
  );
  const expectedArtifacts = validateReviewManifest(review);
  const loadedBatches = await Promise.all(
    expectedArtifacts.batches.map(async (expectedBatch) => {
      const record = publicBatchRecord(expectedBatch);
      const batch = JSON.parse(
        await readFile(path.join(artifactDirectory, record.filename), "utf8"),
      );
      validateBatchPayload(record, batch, expectedBatch);
      return { record, batch };
    }),
  );
  const batchesByChain = groupBatchesByChain(loadedBatches);
  const operatorPayload = JSON.parse(
    await readFile(
      path.join(artifactDirectory, review.operatorCalldataFile),
      "utf8",
    ),
  );
  validateOperatorPayload(review, operatorPayload, expectedArtifacts);
  const operatorByChain = { 1: [], 137: [], 8453: [] };
  for (const call of operatorPayload.calls) operatorByChain[call.chainId].push(call);

  const results = [];
  for (const chainId of [137, 8453, 1]) {
    results.push(
      await rehearseChain({
        chainId,
        review,
        batches: batchesByChain[chainId],
        operatorCalls: operatorByChain[chainId],
        newDonationVault: getAddress(review.replacementDonationVault),
      }),
    );
  }
  const evidence = {
    schemaVersion: 1,
    status: "passed-local-forks-no-chain-writes",
    rehearsedAt: new Date().toISOString(),
    artifactDirectory,
    results,
  };
  const evidencePath = path.join(artifactDirectory, "fork-rehearsal.json");
  await writeJsonAtomic(evidencePath, evidence);
  process.stdout.write(
    `Fork rehearsal passed for Polygon, Base, and Ethereum.\nEvidence: ${evidencePath}\n`,
  );
}

main().catch((error) => {
  process.stderr.write(
    `Migration fork rehearsal failed: ${safeErrorMessage(
      error,
      Object.values(CHAIN_CONFIG).map(({ envName }) => envName),
    )}\n`,
  );
  process.exitCode = 1;
});
