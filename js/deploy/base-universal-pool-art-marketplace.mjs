#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { config as loadEnv } from "dotenv";
import {
  createPublicClient,
  createWalletClient,
  decodeEventLog,
  encodeDeployData,
  encodeFunctionData,
  getAddress,
  getContractAddress,
  http,
  keccak256,
  parseAbi,
  stringToHex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";

import { canonicalJson } from "../lib/canonical-json.mjs";

import {
  assertRpcMode,
  deploymentErrorDetails,
  deploymentErrorMessage,
  parseCommandArguments,
} from "./base-universal-pool-art-marketplace-helpers.mjs";

import {
  BASE_CHAIN_ID,
  DeploymentNoGoError,
  SOCIETY_SAFE,
  ZERO_ADDRESS,
  applyReplacement,
  assertManifest,
  assertSamePayload,
  classifyDeployment,
  isReceiptLookupMiss,
  isTransactionLookupMiss,
  prepareLifecycleOperation,
  recordCanonicalOperation,
  recordCanonicalOperationFailure,
  recordSubmission,
  writeManifestAtomic,
} from "./base-universal-pool-art-marketplace-state.mjs";

const PROFILE = "universal_marketplace";
const SOLC_VERSION = "0.8.36";
const MAX_RECONCILIATION_BLOCKS = 10_000n;
const RECONCILIATION_BLOCK_BATCH_SIZE = 25n;

const MARKET_ABI = parseAbi([
  "function fame() view returns (address)",
  "function mirror() view returns (address)",
  "function creatorMagic() view returns (address)",
  "function communityFee() view returns (uint96)",
  "function providerFee() view returns (uint96)",
  "function feeRecipient() view returns (address)",
  "function authorizedCheckout() view returns (address)",
  "function activeProviderCap() view returns (uint256)",
  "function owner() view returns (address)",
  "function paused() view returns (bool)",
  "function setAuthorizedCheckout(address)",
  "function unpause()",
  "function transferOwnership(address)",
  "event MarketUnpaused(address indexed account)",
  "event OwnershipTransferred(address indexed oldOwner, address indexed newOwner)",
]);
const CHECKOUT_ABI = parseAbi([
  "function router() view returns (address)",
  "function market() view returns (address)",
  "function fame() view returns (address)",
  "function usdc() view returns (address)",
  "function weth() view returns (address)",
]);
const FAME_ABI = parseAbi([
  "function fameMirror() view returns (address)",
  "function renderer() view returns (address)",
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function unit() view returns (uint256)",
  "function getSkipNFT(address) view returns (bool)",
]);
const CREATOR_MAGIC_ABI = parseAbi([
  "function fame() view returns (address)",
  "function childRenderer() view returns (address)",
  "function owner() view returns (address)",
]);
const SAFE_EXECUTION_ABI = parseAbi([
  "event ExecutionSuccess(bytes32 txHash, uint256 payment)",
  "event ExecutionFailure(bytes32 txHash, uint256 payment)",
]);
const SAFE_EXECUTION_TOPICS = new Set([
  keccak256(stringToHex("ExecutionSuccess(bytes32,uint256)")),
  keccak256(stringToHex("ExecutionFailure(bytes32,uint256)")),
]);

function fail(message) {
  throw new DeploymentNoGoError(message);
}

function env(name) {
  const value = process.env[name];
  if (!value) fail(`missing required environment variable: ${name}`);
  return value;
}

function addressEnv(name) {
  return getAddress(env(name));
}

function normalize(value) {
  return value?.toLowerCase();
}

function assertEqual(label, expected, actual) {
  const comparableExpected = typeof expected === "string" ? expected.toLowerCase() : expected;
  const comparableActual = typeof actual === "string" ? actual.toLowerCase() : actual;
  if (comparableExpected !== comparableActual) {
    fail(`${label} mismatch: expected ${expected}, got ${actual}`);
  }
}

function hashJson(value) {
  return keccak256(stringToHex(canonicalJson(value)));
}

function bytecodeObject(artifact, field) {
  const value = artifact[field]?.object;
  if (!value || value === "0x") fail(`artifact ${field} is empty`);
  return value.startsWith("0x") ? value : `0x${value}`;
}

function immutableWord(value) {
  const raw = typeof value === "bigint" ? value.toString(16) : value.replace(/^0x/, "");
  if (raw.length > 64) fail("immutable value does not fit in one EVM word");
  return raw.padStart(64, "0");
}

function expectedRuntimeBytecode(artifact, immutableValues) {
  const references = artifact.deployedBytecode?.immutableReferences ?? {};
  const ids = Object.keys(references).sort((left, right) => Number(left) - Number(right));
  if (ids.length !== immutableValues.length) {
    fail(`immutable reference count mismatch: expected ${immutableValues.length}, got ${ids.length}`);
  }
  let runtime = bytecodeObject(artifact, "deployedBytecode").slice(2);
  ids.forEach((id, index) => {
    const word = immutableWord(immutableValues[index]);
    for (const reference of references[id]) {
      if (reference.length !== 32) fail(`unsupported immutable width for AST id ${id}`);
      const start = reference.start * 2;
      runtime = `${runtime.slice(0, start)}${word}${runtime.slice(start + 64)}`;
    }
  });
  return `0x${runtime}`;
}

function artifactCompiler(artifact) {
  const metadata = typeof artifact.metadata === "string" ? JSON.parse(artifact.metadata) : artifact.metadata;
  return {
    solcVersion: metadata?.compiler?.version?.split("+")[0],
    evmVersion: metadata?.settings?.evmVersion,
    optimizerEnabled: metadata?.settings?.optimizer?.enabled,
    optimizerRuns: metadata?.settings?.optimizer?.runs,
    viaIr: metadata?.settings?.viaIR ?? false,
  };
}

async function readJson(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

async function readManifest(path) {
  const manifest = await readJson(path);
  return assertManifest(manifest);
}

async function artifact(path) {
  return readJson(resolve(path));
}

function rpcUrlForMode(mode) {
  const rpcUrl = env("RPC_URL");
  assertRpcMode(mode, rpcUrl);
  return rpcUrl;
}

function makePublicClient(mode) {
  return createPublicClient({ chain: base, transport: http(rpcUrlForMode(mode)) });
}

function deploymentMode() {
  const mode = process.env.MARKETPLACE_DEPLOYMENT_MODE ?? "production";
  if (mode !== "production" && mode !== "fork-rehearsal") {
    fail(`unsupported MARKETPLACE_DEPLOYMENT_MODE: ${mode}`);
  }
  return mode;
}

function makeWalletClient(manifest) {
  const rpcUrl = rpcUrlForMode(manifest.intent.deploymentMode);
  if (manifest.intent.deploymentMode === "fork-rehearsal") {
    const account = getAddress(manifest.intent.deployer);
    return {
      account,
      accountAddress: account,
      client: createWalletClient({ account, chain: base, transport: http(rpcUrl) }),
    };
  }
  const account = privateKeyToAccount(env("DEPLOYER_PRIVATE_KEY"));
  return {
    account,
    accountAddress: account.address,
    client: createWalletClient({ account, chain: base, transport: http(rpcUrl) }),
  };
}

function hashCode(code) {
  return code && code !== "0x" ? keccak256(code) : null;
}

async function requireCode(client, label, address, blockNumber) {
  const code = await client.getBytecode({ address, ...(blockNumber ? { blockNumber } : {}) });
  if (!code || code === "0x") fail(`${label} has no deployed code at ${address}`);
  return code;
}

async function readAt(client, address, abi, functionName, blockNumber) {
  return client.readContract({ address, abi, functionName, ...(blockNumber ? { blockNumber } : {}) });
}

async function validateCanonicalDependencies(client, values) {
  await Promise.all([
    requireCode(client, "FAME", values.fame),
    requireCode(client, "Society mirror", values.mirror),
    requireCode(client, "CreatorArtistMagic", values.creatorMagic),
    requireCode(client, "child renderer", values.childRenderer),
    requireCode(client, "FAME router", values.router),
    requireCode(client, "USDC", values.usdc),
    requireCode(client, "WETH", values.weth),
    requireCode(client, "Society Safe", values.safe),
  ]);
  const [mirror, renderer, name, symbol, unit, routerSkips, creatorFame, childRenderer, creatorOwner] =
    await Promise.all([
      readAt(client, values.fame, FAME_ABI, "fameMirror"),
      readAt(client, values.fame, FAME_ABI, "renderer"),
      readAt(client, values.fame, FAME_ABI, "name"),
      readAt(client, values.fame, FAME_ABI, "symbol"),
      readAt(client, values.fame, FAME_ABI, "unit"),
      client.readContract({
        address: values.fame,
        abi: FAME_ABI,
        functionName: "getSkipNFT",
        args: [values.router],
      }),
      readAt(client, values.creatorMagic, CREATOR_MAGIC_ABI, "fame"),
      readAt(client, values.creatorMagic, CREATOR_MAGIC_ABI, "childRenderer"),
      readAt(client, values.creatorMagic, CREATOR_MAGIC_ABI, "owner"),
    ]);
  assertEqual("FAME mirror", values.mirror, mirror);
  assertEqual("FAME renderer", values.creatorMagic, renderer);
  assertEqual("FAME name", "Society", name);
  assertEqual("FAME symbol", "FAME", symbol);
  assertEqual("FAME unit", 1_000_000n * 10n ** 18n, unit);
  assertEqual("router skipNFT", true, routerSkips);
  assertEqual("CreatorArtistMagic FAME", values.fame, creatorFame);
  assertEqual("CreatorArtistMagic child renderer", values.childRenderer, childRenderer);
  assertEqual("CreatorArtistMagic owner", values.deployer, creatorOwner);
}

function releaseValues() {
  const values = {
    fame: addressEnv("BASE_FAME_ADDRESS"),
    mirror: addressEnv("BASE_FAME_NFT_ADDRESS"),
    creatorMagic: addressEnv("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"),
    childRenderer: addressEnv("BASE_CREATOR_ARTIST_MAGIC_CHILD_RENDERER_ADDRESS"),
    router: addressEnv("BASE_FAME_ROUTER_ADDRESS"),
    usdc: addressEnv("BASE_USDC_ADDRESS"),
    weth: addressEnv("BASE_WETH_ADDRESS"),
    deployer: addressEnv("BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"),
    owner: addressEnv("BASE_UNIVERSAL_MARKETPLACE_OWNER"),
    feeRecipient: addressEnv("BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
    safe: addressEnv("BASE_UNIVERSAL_MARKETPLACE_FUTURE_OWNER"),
    communityFee: BigInt(env("BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE")),
    providerFee: BigInt(env("BASE_UNIVERSAL_MARKETPLACE_PROVIDER_FEE")),
    activeProviderCap: BigInt(env("BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP")),
  };
  assertEqual("initial owner", values.deployer, values.owner);
  assertEqual("fee recipient", SOCIETY_SAFE, values.feeRecipient);
  assertEqual("future owner", SOCIETY_SAFE, values.safe);
  return values;
}

async function prepare(path) {
  if (process.env.FOUNDRY_PROFILE !== PROFILE) {
    fail(`FOUNDRY_PROFILE must be exactly ${PROFILE}`);
  }
  const mode = deploymentMode();
  const client = makePublicClient(mode);
  const chainId = await client.getChainId();
  assertEqual("chain id", BASE_CHAIN_ID, chainId);
  const values = releaseValues();
  await validateCanonicalDependencies(client, values);

  const [marketArtifact, checkoutArtifact] = await Promise.all([
    artifact("out/UniversalPoolArtMarketplace.sol/UniversalPoolArtMarketplace.json"),
    artifact("out/FameMarketplaceCheckout.sol/FameMarketplaceCheckout.json"),
  ]);
  const marketCompiler = artifactCompiler(marketArtifact);
  const checkoutCompiler = artifactCompiler(checkoutArtifact);
  for (const [label, compiler] of [
    ["marketplace", marketCompiler],
    ["checkout", checkoutCompiler],
  ]) {
    assertEqual(`${label} compiler`, SOLC_VERSION, compiler.solcVersion);
    assertEqual(`${label} EVM version`, "cancun", compiler.evmVersion);
    assertEqual(`${label} optimizer`, true, compiler.optimizerEnabled);
    assertEqual(`${label} optimizer runs`, 200, compiler.optimizerRuns);
    assertEqual(`${label} via IR`, false, compiler.viaIr);
  }

  const [latestNonce, pendingNonce, preparedAtBlock] = await Promise.all([
    client.getTransactionCount({ address: values.deployer, blockTag: "latest" }),
    client.getTransactionCount({ address: values.deployer, blockTag: "pending" }),
    client.getBlock({ blockTag: "latest" }),
  ]);
  assertEqual("untouched deployer nonce", latestNonce, pendingNonce);
  const marketplace = getContractAddress({ from: values.deployer, nonce: BigInt(latestNonce) });
  const checkout = getContractAddress({ from: values.deployer, nonce: BigInt(latestNonce) + 1n });
  const [marketCode, checkoutCode] = await Promise.all([
    client.getBytecode({ address: marketplace }),
    client.getBytecode({ address: checkout }),
  ]);
  if (marketCode && marketCode !== "0x") fail("predicted marketplace address is already occupied");
  if (checkoutCode && checkoutCode !== "0x") fail("predicted checkout address is already occupied");

  const marketArgs = [
    values.fame,
    values.creatorMagic,
    values.communityFee,
    values.providerFee,
    values.feeRecipient,
    values.owner,
    values.activeProviderCap,
  ];
  const checkoutArgs = [values.router, marketplace, values.fame, values.usdc, values.weth];
  const marketCreationBytecode = bytecodeObject(marketArtifact, "bytecode");
  const checkoutCreationBytecode = bytecodeObject(checkoutArtifact, "bytecode");
  const marketInput = encodeDeployData({
    abi: marketArtifact.abi,
    bytecode: marketCreationBytecode,
    args: marketArgs,
  });
  const checkoutInput = encodeDeployData({
    abi: checkoutArtifact.abi,
    bytecode: checkoutCreationBytecode,
    args: checkoutArgs,
  });
  const authorizationInput = encodeFunctionData({
    abi: MARKET_ABI,
    functionName: "setAuthorizedCheckout",
    args: [checkout],
  });
  const marketRuntime = expectedRuntimeBytecode(marketArtifact, [
    values.fame,
    values.mirror,
    values.creatorMagic,
    values.activeProviderCap,
  ]);
  const checkoutRuntime = expectedRuntimeBytecode(checkoutArtifact, checkoutArgs);
  const sourceCommit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  const dirty = execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" }).trim();
  if (dirty && mode === "production") fail("production deployment preparation requires a clean working tree");
  const forgeVersion = execFileSync("forge", ["--version"], { encoding: "utf8" }).trim();

  const manifest = {
    schemaVersion: 1,
    kind: "base-universal-pool-art-marketplace",
    status: "prepared",
    chain: {
      chainId,
      preparedAtBlock: preparedAtBlock.number.toString(),
      preparedAtBlockHash: preparedAtBlock.hash,
    },
    intent: {
      deployer: values.deployer,
      deploymentMode: mode,
      startingNonce: latestNonce.toString(),
      marketplace,
      checkout,
      sourceCommit,
      workingTreeClean: !dirty,
      foundryProfile: PROFILE,
      forgeVersion,
      solcVersion: SOLC_VERSION,
      evmVersion: "cancun",
      optimizerRuns: 200,
      viaIr: false,
    },
    artifacts: {
      marketplace: {
        abiHash: hashJson(marketArtifact.abi),
        creationBytecodeHash: keccak256(marketCreationBytecode),
        runtimeTemplateHash: keccak256(bytecodeObject(marketArtifact, "deployedBytecode")),
        expectedRuntimeCodeHash: keccak256(marketRuntime),
      },
      checkout: {
        abiHash: hashJson(checkoutArtifact.abi),
        creationBytecodeHash: keccak256(checkoutCreationBytecode),
        runtimeTemplateHash: keccak256(bytecodeObject(checkoutArtifact, "deployedBytecode")),
        expectedRuntimeCodeHash: keccak256(checkoutRuntime),
      },
    },
    inputs: {
      canonicalDependencies: {
        mirror: values.mirror,
        childRenderer: values.childRenderer,
      },
      marketplaceConstructor: {
        values: {
          fame: values.fame,
          creatorMagic: values.creatorMagic,
          communityFee: values.communityFee.toString(),
          providerFee: values.providerFee.toString(),
          feeRecipient: values.feeRecipient,
          owner: values.owner,
          activeProviderCap: values.activeProviderCap.toString(),
        },
        encodedHash: keccak256(marketInput),
      },
      checkoutConstructor: {
        values: {
          router: values.router,
          marketplace,
          fame: values.fame,
          usdc: values.usdc,
          weth: values.weth,
        },
        encodedHash: keccak256(checkoutInput),
      },
      authorization: {
        target: marketplace,
        checkout,
        calldataHash: keccak256(authorizationInput),
      },
    },
    steps: [
      deploymentStep("deploy-marketplace", latestNonce, null, marketplace, marketInput),
      deploymentStep("deploy-checkout", latestNonce + 1, null, checkout, checkoutInput),
      deploymentStep("authorize-checkout", latestNonce + 2, marketplace, null, authorizationInput),
    ],
    operations: [],
  };
  await writeManifestAtomic(path, manifest);
  console.log(`Prepared ${path}`);
  console.log(`Marketplace: ${marketplace}`);
  console.log(`Checkout: ${checkout}`);
}

function deploymentStep(id, nonce, target, predictedAddress, input) {
  return {
    id,
    purpose: id,
    sender: addressEnv("BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"),
    nonce: String(nonce),
    target,
    predictedAddress,
    transactionInputHash: keccak256(input),
    transactionInput: input,
    submittedHash: null,
    submittedAtBlock: null,
    replacementHistory: [],
    receipt: null,
    observedResult: null,
  };
}

async function assertPinnedDeploymentContext(client, manifest, manifestPath) {
  if (process.env.FOUNDRY_PROFILE !== PROFILE) {
    fail(`FOUNDRY_PROFILE must be exactly ${PROFILE}`);
  }
  assertEqual("deployment mode", manifest.intent.deploymentMode, deploymentMode());
  assertEqual("manifest Foundry profile", PROFILE, manifest.intent.foundryProfile);
  assertEqual("manifest compiler", SOLC_VERSION, manifest.intent.solcVersion);
  assertEqual("manifest EVM version", "cancun", manifest.intent.evmVersion);
  assertEqual("manifest optimizer runs", 200, manifest.intent.optimizerRuns);
  assertEqual("manifest via IR", false, manifest.intent.viaIr);

  const sourceCommit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  assertEqual("source commit", manifest.intent.sourceCommit, sourceCommit);
  if (manifest.intent.deploymentMode === "production") {
    const manifestRelativePath = relative(resolve("."), manifestPath);
    const dirtyLines = execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" })
      .trim()
      .split("\n")
      .filter(Boolean);
    const unexpectedDirtyLines = dirtyLines.filter(
      (line) => !line.endsWith(` ${manifestRelativePath}`),
    );
    if (unexpectedDirtyLines.length > 0) {
      fail("production deployment requires the pinned source tree to remain clean");
    }
  }

  const values = releaseValues();
  await validateCanonicalDependencies(client, values);
  assertEqual("predicted marketplace", manifest.intent.marketplace, getContractAddress({
    from: values.deployer,
    nonce: BigInt(manifest.intent.startingNonce),
  }));
  assertEqual("predicted checkout", manifest.intent.checkout, getContractAddress({
    from: values.deployer,
    nonce: BigInt(manifest.intent.startingNonce) + 1n,
  }));

  const marketValues = manifest.inputs.marketplaceConstructor.values;
  const checkoutValues = manifest.inputs.checkoutConstructor.values;
  const dependencies = manifest.inputs.canonicalDependencies;
  for (const [label, expected, actual] of [
    ["FAME", marketValues.fame, values.fame],
    ["Society mirror", dependencies.mirror, values.mirror],
    ["CreatorMagic", marketValues.creatorMagic, values.creatorMagic],
    ["child renderer", dependencies.childRenderer, values.childRenderer],
    ["community fee", marketValues.communityFee, values.communityFee.toString()],
    ["provider fee", marketValues.providerFee, values.providerFee.toString()],
    ["fee recipient", marketValues.feeRecipient, values.feeRecipient],
    ["initial owner", marketValues.owner, values.owner],
    ["provider cap", marketValues.activeProviderCap, values.activeProviderCap.toString()],
    ["router", checkoutValues.router, values.router],
    ["checkout marketplace", checkoutValues.marketplace, manifest.intent.marketplace],
    ["checkout FAME", checkoutValues.fame, values.fame],
    ["USDC", checkoutValues.usdc, values.usdc],
    ["WETH", checkoutValues.weth, values.weth],
  ]) {
    assertEqual(`pinned ${label}`, expected, actual);
  }

  const [marketArtifact, checkoutArtifact] = await Promise.all([
    artifact("out/UniversalPoolArtMarketplace.sol/UniversalPoolArtMarketplace.json"),
    artifact("out/FameMarketplaceCheckout.sol/FameMarketplaceCheckout.json"),
  ]);
  for (const [label, compiler] of [
    ["marketplace", artifactCompiler(marketArtifact)],
    ["checkout", artifactCompiler(checkoutArtifact)],
  ]) {
    assertEqual(`${label} compiler`, SOLC_VERSION, compiler.solcVersion);
    assertEqual(`${label} EVM version`, "cancun", compiler.evmVersion);
    assertEqual(`${label} optimizer`, true, compiler.optimizerEnabled);
    assertEqual(`${label} optimizer runs`, 200, compiler.optimizerRuns);
    assertEqual(`${label} via IR`, false, compiler.viaIr);
  }

  const marketCreationBytecode = bytecodeObject(marketArtifact, "bytecode");
  const checkoutCreationBytecode = bytecodeObject(checkoutArtifact, "bytecode");
  const marketArgs = [
    values.fame,
    values.creatorMagic,
    values.communityFee,
    values.providerFee,
    values.feeRecipient,
    values.owner,
    values.activeProviderCap,
  ];
  const checkoutArgs = [values.router, manifest.intent.marketplace, values.fame, values.usdc, values.weth];
  const marketInput = encodeDeployData({
    abi: marketArtifact.abi,
    bytecode: marketCreationBytecode,
    args: marketArgs,
  });
  const checkoutInput = encodeDeployData({
    abi: checkoutArtifact.abi,
    bytecode: checkoutCreationBytecode,
    args: checkoutArgs,
  });
  const authorizationInput = encodeFunctionData({
    abi: MARKET_ABI,
    functionName: "setAuthorizedCheckout",
    args: [manifest.intent.checkout],
  });
  const marketRuntime = expectedRuntimeBytecode(marketArtifact, [
    values.fame,
    values.mirror,
    values.creatorMagic,
    values.activeProviderCap,
  ]);
  const checkoutRuntime = expectedRuntimeBytecode(checkoutArtifact, checkoutArgs);
  for (const [label, expected, actual] of [
    ["market ABI", manifest.artifacts.marketplace.abiHash, hashJson(marketArtifact.abi)],
    ["market creation bytecode", manifest.artifacts.marketplace.creationBytecodeHash, keccak256(marketCreationBytecode)],
    ["market runtime template", manifest.artifacts.marketplace.runtimeTemplateHash, keccak256(bytecodeObject(marketArtifact, "deployedBytecode"))],
    ["market expected runtime", manifest.artifacts.marketplace.expectedRuntimeCodeHash, keccak256(marketRuntime)],
    ["checkout ABI", manifest.artifacts.checkout.abiHash, hashJson(checkoutArtifact.abi)],
    ["checkout creation bytecode", manifest.artifacts.checkout.creationBytecodeHash, keccak256(checkoutCreationBytecode)],
    ["checkout runtime template", manifest.artifacts.checkout.runtimeTemplateHash, keccak256(bytecodeObject(checkoutArtifact, "deployedBytecode"))],
    ["checkout expected runtime", manifest.artifacts.checkout.expectedRuntimeCodeHash, keccak256(checkoutRuntime)],
    ["market constructor input", manifest.inputs.marketplaceConstructor.encodedHash, keccak256(marketInput)],
    ["checkout constructor input", manifest.inputs.checkoutConstructor.encodedHash, keccak256(checkoutInput)],
    ["authorization target", manifest.inputs.authorization.target, manifest.intent.marketplace],
    ["authorization checkout", manifest.inputs.authorization.checkout, manifest.intent.checkout],
    ["authorization input", manifest.inputs.authorization.calldataHash, keccak256(authorizationInput)],
    ["market constructor", manifest.steps[0].transactionInputHash, keccak256(marketInput)],
    ["checkout constructor", manifest.steps[1].transactionInputHash, keccak256(checkoutInput)],
    ["authorization calldata", manifest.steps[2].transactionInputHash, keccak256(authorizationInput)],
  ]) {
    assertEqual(`pinned ${label}`, expected, actual);
  }
  assertEqual("market transaction input", manifest.steps[0].transactionInput, marketInput);
  assertEqual("checkout transaction input", manifest.steps[1].transactionInput, checkoutInput);
  assertEqual("authorization transaction input", manifest.steps[2].transactionInput, authorizationInput);
}

async function scanCanonicalTransaction(client, transactionIntent, fromBlock, toBlock) {
  for (let batchStart = fromBlock; batchStart <= toBlock; batchStart += RECONCILIATION_BLOCK_BATCH_SIZE) {
    const batchEnd =
      batchStart + RECONCILIATION_BLOCK_BATCH_SIZE - 1n < toBlock
        ? batchStart + RECONCILIATION_BLOCK_BATCH_SIZE - 1n
        : toBlock;
    const blockNumbers = [];
    for (let blockNumber = batchStart; blockNumber <= batchEnd; blockNumber += 1n) {
      blockNumbers.push(blockNumber);
    }
    const blocks = await Promise.all(
      blockNumbers.map((blockNumber) => client.getBlock({ blockNumber, includeTransactions: true })),
    );
    for (const block of blocks) {
      const transaction = block.transactions.find(
        (candidate) =>
          typeof candidate !== "string" &&
          normalize(candidate.from) === normalize(transactionIntent.sender) &&
          BigInt(candidate.nonce) === BigInt(transactionIntent.nonce),
      );
      if (transaction && typeof transaction !== "string") {
        const receipt = await client.getTransactionReceipt({ hash: transaction.hash });
        return { transaction, receipt };
      }
    }
  }
  return null;
}

async function nonceConsumptionBlock(client, transactionIntent, fromBlock, head) {
  const nonce = BigInt(transactionIntent.nonce);
  const countAtStart = await client.getTransactionCount({
    address: transactionIntent.sender,
    blockNumber: fromBlock,
  });
  if (BigInt(countAtStart) > nonce) return fromBlock;
  let low = fromBlock + 1n;
  let high = head;
  while (low < high) {
    const middle = low + (high - low) / 2n;
    const count = await client.getTransactionCount({
      address: transactionIntent.sender,
      blockNumber: middle,
    });
    if (BigInt(count) > nonce) high = middle;
    else low = middle + 1n;
  }
  return low;
}

export async function findCanonicalTransaction(
  client,
  manifest,
  transactionIntent,
  additionalHashes = [],
) {
  const knownHashes = [
    ...additionalHashes,
    transactionIntent.submittedHash,
    transactionIntent.lastError?.transactionHash,
    manifest.lastError?.stepId === transactionIntent.id
      ? manifest.lastError.transactionHash
      : null,
    ...transactionIntent.replacementHistory.flatMap((entry) => [entry.previousHash, entry.replacementHash]),
  ].filter(Boolean);
  for (const hash of [...new Set(knownHashes)]) {
    try {
      const receipt = await client.getTransactionReceipt({ hash });
      const transaction = await client.getTransaction({ hash: receipt.transactionHash });
      return { transaction, receipt };
    } catch (error) {
      if (!isReceiptLookupMiss(error)) throw error;
      // A missing known hash is uncertainty, not evidence that the nonce is free.
    }
  }

  if (transactionIntent.nonce === null) return null;
  const latestNonce = await client.getTransactionCount({ address: transactionIntent.sender, blockTag: "latest" });
  if (BigInt(latestNonce) <= BigInt(transactionIntent.nonce)) return null;
  const head = await client.getBlockNumber();
  const fromBlock = BigInt(
    transactionIntent.submittedAtBlock ?? transactionIntent.preparedAtBlock ?? manifest.chain.preparedAtBlock,
  );
  if (head < fromBlock) fail(`${transactionIntent.id} recovery block is ahead of the canonical head`);
  let scanFrom = fromBlock;
  let scanTo = head;
  if (head - fromBlock > MAX_RECONCILIATION_BLOCKS) {
    scanFrom = await nonceConsumptionBlock(client, transactionIntent, fromBlock, head);
    scanTo = scanFrom;
  }
  const canonical = await scanCanonicalTransaction(client, transactionIntent, scanFrom, scanTo);
  if (canonical) return canonical;
  fail(`${transactionIntent.id} nonce was consumed but no canonical transaction was found`);
}

function observedTransaction(transaction) {
  return {
    hash: transaction.hash,
    from: transaction.from,
    nonce: transaction.nonce.toString(),
    to: transaction.to ?? null,
    transactionInputHash: keccak256(transaction.input),
  };
}

function observedReceipt(receipt) {
  return {
    transactionHash: receipt.transactionHash,
    status: receipt.status,
    blockNumber: receipt.blockNumber.toString(),
    blockHash: receipt.blockHash,
    contractAddress: receipt.contractAddress ?? null,
    gasUsed: receipt.gasUsed.toString(),
  };
}

async function verifyStepResult(client, manifest, step, receipt) {
  const blockNumber = receipt.blockNumber;
  if (step.id === "deploy-marketplace") {
    assertEqual("marketplace receipt address", manifest.intent.marketplace, receipt.contractAddress);
    const inputs = manifest.inputs.marketplaceConstructor.values;
    const [
      code,
      fame,
      mirror,
      creatorMagic,
      communityFee,
      providerFee,
      feeRecipient,
      owner,
      activeProviderCap,
      paused,
      authorizedCheckout,
    ] = await Promise.all([
      requireCode(client, "marketplace", manifest.intent.marketplace, blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "fame", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "mirror", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "creatorMagic", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "communityFee", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "providerFee", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "feeRecipient", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "owner", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "activeProviderCap", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "paused", blockNumber),
      readAt(client, manifest.intent.marketplace, MARKET_ABI, "authorizedCheckout", blockNumber),
    ]);
    const checks = {
      runtimeCodeHash: hashCode(code),
      fame,
      mirror,
      creatorMagic,
      communityFee: communityFee.toString(),
      providerFee: providerFee.toString(),
      feeRecipient,
      owner,
      activeProviderCap: activeProviderCap.toString(),
      paused,
      authorizedCheckout,
    };
    assertEqual("marketplace runtime", manifest.artifacts.marketplace.expectedRuntimeCodeHash, checks.runtimeCodeHash);
    assertEqual("marketplace FAME", inputs.fame, checks.fame);
    assertEqual("marketplace mirror", manifest.inputs.canonicalDependencies.mirror, checks.mirror);
    assertEqual("marketplace CreatorMagic", inputs.creatorMagic, checks.creatorMagic);
    assertEqual("marketplace community fee", inputs.communityFee, checks.communityFee);
    assertEqual("marketplace provider fee", inputs.providerFee, checks.providerFee);
    assertEqual("marketplace fee recipient", inputs.feeRecipient, checks.feeRecipient);
    assertEqual("marketplace owner", inputs.owner, checks.owner);
    assertEqual("marketplace provider cap", inputs.activeProviderCap, checks.activeProviderCap);
    assertEqual("marketplace paused", true, checks.paused);
    assertEqual("marketplace initial checkout", ZERO_ADDRESS, checks.authorizedCheckout);
    return { verified: true, verifiedAtBlock: blockNumber.toString(), checks };
  }
  if (step.id === "deploy-checkout") {
    assertEqual("checkout receipt address", manifest.intent.checkout, receipt.contractAddress);
    const inputs = manifest.inputs.checkoutConstructor.values;
    const [code, router, market, fame, usdc, weth, skipNFT] = await Promise.all([
      requireCode(client, "checkout", manifest.intent.checkout, blockNumber),
      readAt(client, manifest.intent.checkout, CHECKOUT_ABI, "router", blockNumber),
      readAt(client, manifest.intent.checkout, CHECKOUT_ABI, "market", blockNumber),
      readAt(client, manifest.intent.checkout, CHECKOUT_ABI, "fame", blockNumber),
      readAt(client, manifest.intent.checkout, CHECKOUT_ABI, "usdc", blockNumber),
      readAt(client, manifest.intent.checkout, CHECKOUT_ABI, "weth", blockNumber),
      client.readContract({
        address: inputs.fame,
        abi: FAME_ABI,
        functionName: "getSkipNFT",
        args: [manifest.intent.checkout],
        blockNumber,
      }),
    ]);
    const checks = {
      runtimeCodeHash: hashCode(code),
      router,
      market,
      fame,
      usdc,
      weth,
      skipNFT,
    };
    assertEqual("checkout runtime", manifest.artifacts.checkout.expectedRuntimeCodeHash, checks.runtimeCodeHash);
    for (const field of ["router", "market", "fame", "usdc", "weth"]) {
      assertEqual(`checkout ${field}`, inputs[field === "market" ? "marketplace" : field], checks[field]);
    }
    assertEqual("checkout skipNFT", true, checks.skipNFT);
    return { verified: true, verifiedAtBlock: blockNumber.toString(), checks };
  }
  const authorizedCheckout = await readAt(
    client,
    manifest.intent.marketplace,
    MARKET_ABI,
    "authorizedCheckout",
    blockNumber,
  );
  assertEqual("authorized checkout", manifest.intent.checkout, authorizedCheckout);
  return {
    verified: true,
    verifiedAtBlock: blockNumber.toString(),
    checks: { authorizedCheckout },
  };
}

async function observeDeployment(client, manifest) {
  const steps = {};
  for (const step of manifest.steps) {
    const canonical = await findCanonicalTransaction(client, manifest, step);
    if (!canonical) break;
    let result = { verified: false, checks: {} };
    if (canonical.receipt.status === "success") {
      try {
        result = await verifyStepResult(client, manifest, step, canonical.receipt);
      } catch (error) {
        result = {
          verified: false,
          checks: {},
          error: deploymentErrorDetails(error),
        };
      }
    }
    steps[step.id] = {
      transaction: observedTransaction(canonical.transaction),
      receipt: observedReceipt(canonical.receipt),
      result,
    };
    if (canonical.receipt.status !== "success" || !result.verified) break;
  }
  const [latestNonce, pendingNonce, marketCode, checkoutCode] = await Promise.all([
    client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "latest" }),
    client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "pending" }),
    client.getBytecode({ address: manifest.intent.marketplace }),
    client.getBytecode({ address: manifest.intent.checkout }),
  ]);
  const marketExists = Boolean(marketCode && marketCode !== "0x");
  const authorizedCheckout = marketExists
    ? await readAt(client, manifest.intent.marketplace, MARKET_ABI, "authorizedCheckout")
    : ZERO_ADDRESS;
  return {
    account: { latestNonce: latestNonce.toString(), pendingNonce: pendingNonce.toString() },
    predicted: {
      marketplaceCodeHash: hashCode(marketCode),
      checkoutCodeHash: hashCode(checkoutCode),
      authorizedCheckout,
    },
    steps,
  };
}

function mergeObservation(manifest, observation, classification) {
  const updated = structuredClone(manifest);
  for (const step of updated.steps) {
    const observed = observation.steps[step.id];
    if (!observed) continue;
    if (step.submittedHash && step.submittedHash !== observed.transaction.hash) {
      const alreadyRecorded = step.replacementHistory.some(
        (entry) => entry.replacementHash === observed.transaction.hash,
      );
      if (!alreadyRecorded) {
        step.replacementHistory.push({
          previousHash: step.submittedHash,
          replacementHash: observed.transaction.hash,
          reason: "canonical nonce replacement discovered during reconciliation",
        });
      }
    }
    step.submittedHash = observed.transaction.hash;
    step.submittedAtBlock ??= observed.receipt.blockNumber;
    step.receipt = observed.receipt;
    step.observedResult = observed.result;
  }
  updated.status =
    classification.kind === "complete"
      ? ["activated", "handed-off"].includes(manifest.status)
        ? manifest.status
        : "deployed"
      : classification.kind === "uncertain"
        ? "needs-reconciliation"
        : classification.confirmedPrefix === 0
          ? "prepared"
          : "in-progress";
  updated.lastReconciliation = {
    observedAt: new Date().toISOString(),
    classification,
    account: observation.account,
  };
  return updated;
}

export async function reconcile(path, injectedClient) {
  const manifest = await readManifest(path);
  const client = injectedClient ?? makePublicClient(manifest.intent.deploymentMode);
  assertEqual("chain id", BASE_CHAIN_ID, await client.getChainId());
  const observation = await observeDeployment(client, manifest);
  let classification;
  try {
    classification = classifyDeployment(manifest, observation);
  } catch (error) {
    const failed = structuredClone(manifest);
    failed.status = "needs-reconciliation";
    failed.lastReconciliation = {
      observedAt: new Date().toISOString(),
      classification: { kind: "no-go", reason: deploymentErrorMessage(error) },
      observation,
    };
    await writeManifestAtomic(path, failed);
    throw error;
  }
  const updated = mergeObservation(manifest, observation, classification);
  await writeManifestAtomic(path, updated);
  return { manifest: updated, classification };
}

export async function advance(path, injectedClients = {}) {
  const preparedManifest = await readManifest(path);
  const publicClient =
    injectedClients.publicClient ?? makePublicClient(preparedManifest.intent.deploymentMode);
  const { manifest, classification } = await reconcile(path, publicClient);
  if (classification.kind === "complete") fail("deployment is already complete; no transaction was submitted");
  if (classification.kind !== "ready") fail(`${classification.reason}; reconcile before choosing recovery`);
  await assertPinnedDeploymentContext(publicClient, manifest, path);
  const { account, accountAddress, client: walletClient } =
    injectedClients.wallet ?? makeWalletClient(manifest);
  assertEqual("deployment signer", manifest.intent.deployer, accountAddress);
  const step = manifest.steps[classification.confirmedPrefix];
  let updated = manifest;
  let transactionHash;
  const submittedAtBlock = await publicClient.getBlockNumber();
  try {
    transactionHash = await walletClient.sendTransaction({
      account,
      ...(step.target ? { to: step.target } : {}),
      data: step.transactionInput,
      nonce: Number(step.nonce),
      value: 0n,
    });
    updated = recordSubmission(updated, step.id, transactionHash, submittedAtBlock.toString());
    await writeManifestAtomic(path, updated);
    await publicClient.waitForTransactionReceipt({
      hash: transactionHash,
      onReplaced: async ({ reason, transaction }) => {
        updated = applyReplacement(
          updated,
          step.id,
          {
            hash: transaction.hash,
            from: transaction.from,
            nonce: transaction.nonce.toString(),
            to: transaction.to ?? null,
            transactionInputHash: keccak256(transaction.input),
          },
          reason,
        );
        await writeManifestAtomic(path, updated);
      },
    });
  } catch (error) {
    updated.status = "needs-reconciliation";
    updated.lastError = {
      stepId: step.id,
      transactionHash: transactionHash ?? null,
      observedAt: new Date().toISOString(),
      ...deploymentErrorDetails(error),
    };
    await writeManifestAtomic(path, updated);
    throw error;
  }
  const result = await reconcile(path, publicClient);
  console.log(`${step.id}: ${result.classification.kind}`);
}

async function assertReplacementEligible(client, sender, transaction) {
  try {
    const pending = await client.getTransaction({ hash: transaction.submittedHash });
    assertEqual(`${transaction.id} pending sender`, sender, pending.from);
    assertSamePayload(transaction, observedTransaction(pending));
    return;
  } catch (error) {
    if (!isTransactionLookupMiss(error)) throw error;
  }
  const [latestNonce, pendingNonce] = await Promise.all([
    client.getTransactionCount({ address: sender, blockTag: "latest" }),
    client.getTransactionCount({ address: sender, blockTag: "pending" }),
  ]);
  assertEqual(`${transaction.id} dropped latest nonce`, transaction.nonce, latestNonce.toString());
  assertEqual(`${transaction.id} dropped pending nonce`, transaction.nonce, pendingNonce.toString());
}

export async function replace(path, stepId, injectedClients = {}) {
  const preparedManifest = await readManifest(path);
  const publicClient =
    injectedClients.publicClient ?? makePublicClient(preparedManifest.intent.deploymentMode);
  const { manifest, classification } = await reconcile(path, publicClient);
  if (classification.kind !== "uncertain") {
    fail("replacement requires an uncertain submitted deployment step");
  }
  const step = manifest.steps[classification.confirmedPrefix];
  if (!step || step.id !== stepId || !step.submittedHash) {
    fail(`replacement must name the uncertain step ${step?.id ?? "none"}`);
  }
  await assertPinnedDeploymentContext(publicClient, manifest, path);
  await assertReplacementEligible(publicClient, manifest.intent.deployer, step);
  const { account, accountAddress, client } = injectedClients.wallet ?? makeWalletClient(manifest);
  assertEqual("replacement signer", manifest.intent.deployer, accountAddress);
  let updated = manifest;
  let hash;
  try {
    hash = await client.sendTransaction({
      account,
      ...(step.target ? { to: step.target } : {}),
      data: step.transactionInput,
      nonce: Number(step.nonce),
      value: 0n,
    });
    updated = applyReplacement(
      updated,
      step.id,
      {
        hash,
        from: manifest.intent.deployer,
        nonce: step.nonce,
        to: step.target,
        transactionInputHash: step.transactionInputHash,
      },
      "operator-authorized exact-payload replacement",
    );
    await writeManifestAtomic(path, updated);
    await publicClient.waitForTransactionReceipt({
      hash,
      onReplaced: async ({ reason, transaction }) => {
        updated = applyReplacement(updated, step.id, observedTransaction(transaction), reason);
        await writeManifestAtomic(path, updated);
      },
    });
  } catch (error) {
    updated.status = "needs-reconciliation";
    updated.lastError = {
      stepId: step.id,
      transactionHash: hash ?? null,
      observedAt: new Date().toISOString(),
      ...deploymentErrorDetails(error),
    };
    await writeManifestAtomic(path, updated);
    throw error;
  }
  const result = await reconcile(path, publicClient);
  console.log(`${step.id}: ${result.classification.kind}`);
}

async function currentMarketState(client, manifest, blockNumber) {
  const [owner, paused, authorizedCheckout] = await Promise.all([
    readAt(client, manifest.intent.marketplace, MARKET_ABI, "owner", blockNumber),
    readAt(client, manifest.intent.marketplace, MARKET_ABI, "paused", blockNumber),
    readAt(client, manifest.intent.marketplace, MARKET_ABI, "authorizedCheckout", blockNumber),
  ]);
  return { owner, paused, authorizedCheckout };
}

export async function prepareOperation(path, kind, injectedClient) {
  const preparedManifest = await readManifest(path);
  const client = injectedClient ?? makePublicClient(preparedManifest.intent.deploymentMode);
  const { manifest, classification } = await reconcile(path, client);
  if (classification.kind !== "complete") fail("lifecycle operations require a fully authorized deployment");
  const state = await currentMarketState(client, manifest);
  assertEqual("authorized checkout", manifest.intent.checkout, state.authorizedCheckout);
  let operation;
  if (kind === "deployer-activation") {
    assertEqual("activation owner", manifest.intent.deployer, state.owner);
    assertEqual("activation paused state", true, state.paused);
    const [latestNonce, pendingNonce] = await Promise.all([
      client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "latest" }),
      client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "pending" }),
    ]);
    assertEqual("activation nonce", latestNonce, pendingNonce);
    operation = directOperation(
      manifest,
      kind,
      manifest.intent.deployer,
      latestNonce,
      encodeFunctionData({ abi: MARKET_ABI, functionName: "unpause" }),
      { owner: manifest.intent.deployer, paused: false, eventAccount: manifest.intent.deployer },
    );
  } else if (kind === "ownership-handoff") {
    assertEqual("handoff owner", manifest.intent.deployer, state.owner);
    assertEqual("handoff paused state", true, state.paused);
    await requireCode(client, "Society Safe", SOCIETY_SAFE);
    const [latestNonce, pendingNonce] = await Promise.all([
      client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "latest" }),
      client.getTransactionCount({ address: manifest.intent.deployer, blockTag: "pending" }),
    ]);
    assertEqual("handoff nonce", latestNonce, pendingNonce);
    operation = directOperation(
      manifest,
      kind,
      manifest.intent.deployer,
      latestNonce,
      encodeFunctionData({ abi: MARKET_ABI, functionName: "transferOwnership", args: [SOCIETY_SAFE] }),
      { owner: SOCIETY_SAFE, paused: true, safeHasCode: true },
    );
  } else if (kind === "safe-activation") {
    assertEqual("Safe activation owner", SOCIETY_SAFE, state.owner);
    assertEqual("Safe activation paused state", true, state.paused);
    const input = encodeFunctionData({ abi: MARKET_ABI, functionName: "unpause" });
    operation = {
      id: `safe-activation-${manifest.operations.length + 1}`,
      kind,
      authority: "society-safe",
      sender: SOCIETY_SAFE,
      nonce: null,
      target: manifest.intent.marketplace,
      transactionInput: input,
      transactionInputHash: keccak256(input),
      expectedResult: { owner: SOCIETY_SAFE, paused: false, eventAccount: SOCIETY_SAFE },
    };
  } else {
    fail(`unsupported lifecycle operation: ${kind}`);
  }
  operation.preparedAtBlock = (await client.getBlockNumber()).toString();
  const updated = prepareLifecycleOperation(manifest, operation);
  await writeManifestAtomic(path, updated);
  console.log(`Prepared operation ${operation.id}`);
  if (kind === "safe-activation") {
    console.log(`Safe inner call target: ${operation.target}`);
    console.log(`Safe inner call data: ${operation.transactionInput}`);
  }
}

function directOperation(manifest, kind, sender, nonce, input, expectedResult) {
  return {
    id: `${kind}-${manifest.operations.length + 1}`,
    kind,
    authority: "deployer",
    sender,
    nonce: nonce.toString(),
    target: manifest.intent.marketplace,
    transactionInput: input,
    transactionInputHash: keccak256(input),
    expectedResult,
  };
}

function lifecycleOperation(manifest, id) {
  const operation = manifest.operations.find((candidate) => candidate.id === id);
  if (!operation) fail(`unknown lifecycle operation: ${id}`);
  return operation;
}

function safeExecutionEvidence(receipt) {
  const evidence = [];
  for (const log of receipt.logs) {
    if (
      normalize(log.address) !== SOCIETY_SAFE ||
      !SAFE_EXECUTION_TOPICS.has(log.topics[0]?.toLowerCase())
    ) {
      continue;
    }
    const decoded = decodeEventLog({
      abi: SAFE_EXECUTION_ABI,
      data: log.data,
      topics: log.topics,
      strict: true,
    });
    evidence.push({ eventName: decoded.eventName, safeTransactionHash: decoded.args.txHash });
  }
  if (evidence.length === 0) fail("Safe receipt is missing ExecutionSuccess or ExecutionFailure evidence");
  if (evidence.length !== 1) fail("Safe receipt contains ambiguous execution evidence");
  return evidence[0];
}

export async function advanceOperation(path, id, replaceSubmitted = false, injectedClients = {}) {
  let manifest = await readManifest(path);
  const publicClient =
    injectedClients.publicClient ?? makePublicClient(manifest.intent.deploymentMode);
  const operation = lifecycleOperation(manifest, id);
  if (operation.authority !== "deployer") {
    fail("Safe operations must be executed through Safe governance and reconciled by hash");
  }
  if (operation.receipt) fail(`${id} is already confirmed`);
  if (replaceSubmitted && !operation.submittedHash) fail(`${id} has no submitted transaction to replace`);
  if (!replaceSubmitted && operation.submittedHash) fail(`${id} was already submitted`);
  await assertPinnedDeploymentContext(publicClient, manifest, path);
  if (replaceSubmitted) {
    await assertReplacementEligible(publicClient, operation.sender, operation);
  } else {
    const [latestNonce, pendingNonce] = await Promise.all([
      publicClient.getTransactionCount({ address: operation.sender, blockTag: "latest" }),
      publicClient.getTransactionCount({ address: operation.sender, blockTag: "pending" }),
    ]);
    assertEqual(`${id} latest nonce`, operation.nonce, latestNonce.toString());
    assertEqual(`${id} pending nonce`, operation.nonce, pendingNonce.toString());
  }
  const marketCode = await requireCode(publicClient, "marketplace", manifest.intent.marketplace);
  assertEqual(
    `${id} marketplace runtime`,
    manifest.artifacts.marketplace.expectedRuntimeCodeHash,
    hashCode(marketCode),
  );
  const state = await currentMarketState(publicClient, manifest);
  assertEqual(`${id} current owner`, manifest.intent.deployer, state.owner);
  assertEqual(`${id} current paused state`, true, state.paused);
  assertEqual(`${id} authorized checkout`, manifest.intent.checkout, state.authorizedCheckout);
  if (operation.kind === "ownership-handoff") {
    await requireCode(publicClient, "Society Safe", SOCIETY_SAFE);
  }
  const { account, accountAddress, client } = injectedClients.wallet ?? makeWalletClient(manifest);
  assertEqual(`${id} signer`, operation.sender, accountAddress);
  let hash;
  const submittedAtBlock =
    operation.submittedAtBlock ?? (await publicClient.getBlockNumber()).toString();
  try {
    hash = await client.sendTransaction({
      account,
      to: operation.target,
      data: operation.transactionInput,
      nonce: Number(operation.nonce),
      value: 0n,
    });
    if (replaceSubmitted) {
      operation.replacementHistory.push({
        previousHash: operation.submittedHash,
        replacementHash: hash,
        reason: "operator-authorized exact-payload replacement",
      });
    }
    operation.submittedHash = hash;
    operation.submittedAtBlock ??= submittedAtBlock;
    await writeManifestAtomic(path, manifest);
    await publicClient.waitForTransactionReceipt({
      hash,
      onReplaced: async ({ reason, transaction }) => {
        if (
          normalize(transaction.from) !== normalize(operation.sender) ||
          BigInt(transaction.nonce) !== BigInt(operation.nonce) ||
          normalize(transaction.to) !== normalize(operation.target) ||
          keccak256(transaction.input) !== operation.transactionInputHash
        ) {
          fail(`${id} replacement changed the pinned payload`);
        }
        operation.replacementHistory.push({
          previousHash: operation.submittedHash,
          replacementHash: transaction.hash,
          reason,
        });
        operation.submittedHash = transaction.hash;
        await writeManifestAtomic(path, manifest);
      },
    });
  } catch (error) {
    manifest.status = "needs-reconciliation";
    operation.lastError = {
      transactionHash: hash ?? null,
      observedAt: new Date().toISOString(),
      ...deploymentErrorDetails(error),
    };
    await writeManifestAtomic(path, manifest);
    throw error;
  }
  await reconcileOperation(path, id, operation.submittedHash);
}

export async function reconcileOperation(
  path,
  id,
  executionHash,
  safeTransactionHash,
  injectedClient,
) {
  const manifest = await readManifest(path);
  const client = injectedClient ?? makePublicClient(manifest.intent.deploymentMode);
  const operation = lifecycleOperation(manifest, id);
  let canonical;
  let reviewedSafeTransactionHash = null;
  if (operation.authority === "society-safe") {
    if (!executionHash) fail(`${id} requires the canonical outer execution transaction hash`);
    reviewedSafeTransactionHash = safeTransactionHash ?? operation.safeTransactionHash;
    if (!reviewedSafeTransactionHash || !/^0x[0-9a-fA-F]{64}$/.test(reviewedSafeTransactionHash)) {
      fail(`${id} requires the reviewed Safe transaction hash`);
    }
    const receipt = await client.getTransactionReceipt({ hash: executionHash });
    assertEqual(`${id} outer execution hash`, executionHash, receipt.transactionHash);
    const transaction = await client.getTransaction({ hash: receipt.transactionHash });
    canonical = { transaction, receipt };
  } else {
    canonical = await findCanonicalTransaction(
      client,
      manifest,
      operation,
      executionHash ? [executionHash] : [],
    );
    if (!canonical) fail(`${id} has no canonical receipt; the operation remains uncertain`);
  }
  const { transaction, receipt } = canonical;
  const observation = {
    transaction: observedTransaction(transaction),
    receipt: observedReceipt(receipt),
  };
  let decodedSafeExecution = null;
  try {
    if (receipt.status !== "success") fail(`${id} execution reverted`);
    if (operation.authority === "deployer") {
      assertSamePayload(operation, observation.transaction);
      assertEqual(`${id} canonical sender`, operation.sender, observation.transaction.from);
    } else {
      assertEqual(`${id} outer execution target`, SOCIETY_SAFE, observation.transaction.to);
      decodedSafeExecution = safeExecutionEvidence(receipt);
      assertEqual(
        `${id} reviewed Safe transaction hash`,
        reviewedSafeTransactionHash,
        decodedSafeExecution.safeTransactionHash,
      );
      if (decodedSafeExecution.eventName === "ExecutionFailure") {
        fail(`Safe ExecutionFailure was emitted for ${decodedSafeExecution.safeTransactionHash}`);
      }
    }
    const state = await currentMarketState(client, manifest, receipt.blockNumber);
    const marketCode = await requireCode(client, "marketplace", manifest.intent.marketplace, receipt.blockNumber);
    assertEqual(
      `${id} marketplace runtime`,
      manifest.artifacts.marketplace.expectedRuntimeCodeHash,
      hashCode(marketCode),
    );
    assertEqual(`${id} owner`, operation.expectedResult.owner, state.owner);
    assertEqual(`${id} paused`, operation.expectedResult.paused, state.paused);
    assertEqual(`${id} authorized checkout`, manifest.intent.checkout, state.authorizedCheckout);
    if (operation.expectedResult.safeHasCode) {
      await requireCode(client, "Society Safe", SOCIETY_SAFE, receipt.blockNumber);
    }
    const eventName = operation.kind === "ownership-handoff" ? "OwnershipTransferred" : "MarketUnpaused";
    const eventAccount = operation.kind === "ownership-handoff" ? SOCIETY_SAFE : operation.expectedResult.eventAccount;
    const eventTopic = keccak256(
      stringToHex(
        operation.kind === "ownership-handoff"
          ? "OwnershipTransferred(address,address)"
          : "MarketUnpaused(address)",
      ),
    );
    const indexedAccount = `0x${eventAccount.slice(2).toLowerCase().padStart(64, "0")}`;
    const matchingLog = receipt.logs.some(
      (log) =>
        normalize(log.address) === normalize(manifest.intent.marketplace) &&
        log.topics[0] === eventTopic &&
        log.topics.at(-1)?.toLowerCase() === indexedAccount,
    );
    if (!matchingLog) fail(`${id} receipt is missing the expected ${eventName} event`);
    const updated = recordCanonicalOperation(
      manifest,
      id,
      observation,
      {
        verified: true,
        verifiedAtBlock: receipt.blockNumber.toString(),
        checks: { ...state, runtimeCodeHash: hashCode(marketCode) },
      },
      operation.authority === "society-safe"
        ? {
            eventName: decodedSafeExecution.eventName,
            reviewedHash: reviewedSafeTransactionHash,
            emittedHash: decodedSafeExecution.safeTransactionHash,
          }
        : null,
    );
    await writeManifestAtomic(path, updated);
    console.log(`${id}: confirmed`);
  } catch (error) {
    const failed = recordCanonicalOperationFailure(
      manifest,
      id,
      observation,
      reviewedSafeTransactionHash,
      deploymentErrorMessage(error),
    );
    await writeManifestAtomic(path, failed);
    throw error;
  }
}

function usage() {
  console.log(`Usage:
  base-universal-pool-art-marketplace prepare [manifest]
  base-universal-pool-art-marketplace status [manifest]
  base-universal-pool-art-marketplace reconcile [manifest]
  base-universal-pool-art-marketplace advance [manifest]
  base-universal-pool-art-marketplace replace <deployment-step-id>
  base-universal-pool-art-marketplace replace <manifest> <deployment-step-id>
  base-universal-pool-art-marketplace prepare-operation <deployer-activation|ownership-handoff|safe-activation>
  base-universal-pool-art-marketplace prepare-operation <manifest> <deployer-activation|ownership-handoff|safe-activation>
  base-universal-pool-art-marketplace advance-operation <operation-id>
  base-universal-pool-art-marketplace advance-operation <manifest> <operation-id>
  base-universal-pool-art-marketplace replace-operation <operation-id>
  base-universal-pool-art-marketplace replace-operation <manifest> <operation-id>
  base-universal-pool-art-marketplace reconcile-operation <operation-id>
  base-universal-pool-art-marketplace reconcile-operation <manifest> <operation-id> [execution-hash] [safe-transaction-hash]`);
}

export async function main(argv = process.argv.slice(2)) {
  loadEnv({ path: resolve("config/fame-public.env"), override: false, quiet: true });
  const [command, ...postCommandArguments] = argv;
  if (!command) {
    usage();
    return;
  }
  const parsed = parseCommandArguments(command, postCommandArguments);
  const path = resolve(parsed.manifestPath);
  const args = parsed.arguments;
  if (command === "prepare") return prepare(path);
  if (command === "status") {
    const manifest = await readManifest(path);
    console.log(JSON.stringify({ status: manifest.status, lastReconciliation: manifest.lastReconciliation }, null, 2));
    return;
  }
  if (command === "reconcile") {
    const result = await reconcile(path);
    console.log(JSON.stringify(result.classification, null, 2));
    return;
  }
  if (command === "advance") return advance(path);
  if (command === "replace") return replace(path, args[0]);
  if (command === "prepare-operation") return prepareOperation(path, args[0]);
  if (command === "advance-operation") return advanceOperation(path, args[0]);
  if (command === "replace-operation") return advanceOperation(path, args[0], true);
  if (command === "reconcile-operation") return reconcileOperation(path, args[0], args[1], args[2]);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(deploymentErrorMessage(error));
    process.exitCode = 1;
  });
}
