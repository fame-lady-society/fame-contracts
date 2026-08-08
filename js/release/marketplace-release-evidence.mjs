import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { encodeDeployData, keccak256, toHex } from "viem";

import { writeJsonAtomic } from "../lib/atomic-json.mjs";
import { canonicalJson } from "../lib/canonical-json.mjs";

export { canonicalJson } from "../lib/canonical-json.mjs";

export const PROFILE = "universal_marketplace";
export const SOLC_VERSION = "0.8.36";
export const EVM_VERSION = "cancun";
export const OPTIMIZER_RUNS = 200;
export const VIA_IR = false;
export const RUNTIME_LIMIT_BYTES = 24_576;
export const INITCODE_LIMIT_BYTES = 49_152;

const REPOSITORY_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const SIZE_EQUIVALENT_ADDRESS = "0x1111111111111111111111111111111111111111";

export const RELEASE_TARGETS = Object.freeze([
  Object.freeze({
    name: "UniversalPoolArtMarketplace",
    artifact: "out/UniversalPoolArtMarketplace.sol/UniversalPoolArtMarketplace.json",
    constructorArgs: Object.freeze([
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
      1n,
      1n,
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
      1n,
    ]),
  }),
  Object.freeze({
    name: "FameMarketplaceCheckout",
    artifact: "out/FameMarketplaceCheckout.sol/FameMarketplaceCheckout.json",
    constructorArgs: Object.freeze([
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
      SIZE_EQUIVALENT_ADDRESS,
    ]),
  }),
]);

function canonicalHash(value) {
  if (value === undefined) throw new Error("artifact is missing required compiler output");
  return keccak256(toHex(canonicalJson(value)));
}

function bytecodeMetrics(label, bytecode, limit) {
  if (typeof bytecode !== "string" || !/^0x(?:[0-9a-fA-F]{2})*$/.test(bytecode)) {
    throw new Error(`${label} bytecode is not a complete hex string`);
  }

  const sizeBytes = (bytecode.length - 2) / 2;
  return {
    hash: keccak256(bytecode),
    sizeBytes,
    limitBytes: limit,
    headroomBytes: limit - sizeBytes,
  };
}

function assertReleaseProfile(name, artifact, expectedSolcVersion) {
  const compiler = artifact.metadata?.compiler?.version;
  const settings = artifact.metadata?.settings;
  const actualSolc = compiler?.split("+")[0];
  const actualViaIr = settings?.viaIR ?? false;

  if (actualSolc !== expectedSolcVersion) {
    throw new Error(`${name} was built with Solidity ${actualSolc ?? "unknown"}; expected ${expectedSolcVersion}`);
  }
  if (settings?.evmVersion !== EVM_VERSION) {
    throw new Error(`${name} EVM target is ${settings?.evmVersion ?? "unknown"}; expected ${EVM_VERSION}`);
  }
  if (settings?.optimizer?.enabled !== true || settings.optimizer.runs !== OPTIMIZER_RUNS) {
    throw new Error(`${name} optimizer settings do not match enabled/${OPTIMIZER_RUNS}`);
  }
  if (actualViaIr !== VIA_IR) {
    throw new Error(`${name} viaIR is ${actualViaIr}; expected ${VIA_IR}`);
  }
}

export function inspectReleaseArtifact(
  name,
  artifact,
  artifactPath = undefined,
  expectedSolcVersion = SOLC_VERSION,
  constructorArgs = [],
) {
  assertReleaseProfile(name, artifact, expectedSolcVersion);

  const creationBytecode = bytecodeMetrics(
    `${name} creation`,
    artifact.bytecode?.object,
    INITCODE_LIMIT_BYTES,
  );
  const initcode = bytecodeMetrics(
    `${name} initcode`,
    encodeDeployData({
      abi: artifact.abi,
      bytecode: artifact.bytecode?.object,
      args: constructorArgs,
    }),
    INITCODE_LIMIT_BYTES,
  );
  const runtime = bytecodeMetrics(
    `${name} runtime`,
    artifact.deployedBytecode?.object,
    RUNTIME_LIMIT_BYTES,
  );

  return {
    artifact: artifactPath,
    compilerVersion: artifact.metadata.compiler.version,
    abiHash: canonicalHash(artifact.abi),
    storageLayoutHash: canonicalHash(artifact.storageLayout),
    creationBytecodeHash: creationBytecode.hash,
    runtimeBytecodeHash: runtime.hash,
    creationBytecodeSizeBytes: creationBytecode.sizeBytes,
    constructorArgsSizeBytes: initcode.sizeBytes - creationBytecode.sizeBytes,
    initcodeSizeBytes: initcode.sizeBytes,
    initcodeLimitBytes: initcode.limitBytes,
    initcodeHeadroomBytes: initcode.headroomBytes,
    runtimeSizeBytes: runtime.sizeBytes,
    runtimeLimitBytes: runtime.limitBytes,
    runtimeHeadroomBytes: runtime.headroomBytes,
  };
}

export function assertReleaseSizes(contracts) {
  for (const [name, contract] of Object.entries(contracts)) {
    if (contract.runtimeHeadroomBytes < 0) {
      throw new Error(
        `${name} runtime is ${contract.runtimeSizeBytes} bytes, exceeding EIP-170 by ${-contract.runtimeHeadroomBytes} bytes`,
      );
    }
    if (contract.initcodeHeadroomBytes < 0) {
      throw new Error(
        `${name} initcode is ${contract.initcodeSizeBytes} bytes, exceeding EIP-3860 by ${-contract.initcodeHeadroomBytes} bytes`,
      );
    }
  }
}

export function compareEvidence(current, baseline) {
  const contracts = {};
  for (const [name, contract] of Object.entries(current.contracts)) {
    const previous = baseline.contracts?.[name];
    if (!previous) throw new Error(`baseline is missing ${name}`);
    contracts[name] = {
      abiChanged: contract.abiHash !== previous.abiHash,
      storageLayoutChanged: contract.storageLayoutHash !== previous.storageLayoutHash,
      creationBytecodeChanged: contract.creationBytecodeHash !== previous.creationBytecodeHash,
      runtimeBytecodeChanged: contract.runtimeBytecodeHash !== previous.runtimeBytecodeHash,
      initcodeSizeDeltaBytes: contract.initcodeSizeBytes - previous.initcodeSizeBytes,
      runtimeSizeDeltaBytes: contract.runtimeSizeBytes - previous.runtimeSizeBytes,
    };
  }
  return {
    baselineSolcVersion: baseline.toolchain?.solcVersion ?? "unknown",
    contracts,
  };
}

export async function buildReleaseEvidence({
  root = REPOSITORY_ROOT,
  targets = RELEASE_TARGETS,
  sourceCommit,
  forgeVersion,
  workingTreeClean,
  baseline,
  gasEvidence,
  solcVersion = SOLC_VERSION,
} = {}) {
  const contracts = {};
  for (const target of targets) {
    const artifactPath = resolve(root, target.artifact);
    const artifact = JSON.parse(await readFile(artifactPath, "utf8"));
    contracts[target.name] = inspectReleaseArtifact(
      target.name,
      artifact,
      target.artifact,
      solcVersion,
      target.constructorArgs,
    );
  }
  assertReleaseSizes(contracts);
  const compilerVersions = new Set(Object.values(contracts).map((contract) => contract.compilerVersion));
  if (compilerVersions.size !== 1) throw new Error("release targets were built with different compiler binaries");

  const evidence = {
    schemaVersion: 1,
    kind: "base-universal-pool-art-marketplace-release-evidence",
    sourceCommit,
    workingTreeClean,
    toolchain: {
      forgeVersion,
      solcVersion,
      solcLongVersion: compilerVersions.values().next().value,
      foundryProfile: PROFILE,
      evmVersion: EVM_VERSION,
      optimizer: true,
      optimizerRuns: OPTIMIZER_RUNS,
      viaIr: VIA_IR,
      storageLayoutOutput: true,
    },
    contracts,
  };
  if (gasEvidence !== undefined) evidence.gasEvidence = gasEvidence;
  if (baseline !== undefined) evidence.baselineComparison = compareEvidence(evidence, baseline);
  return evidence;
}

export async function writeJsonAtomically(path, value) {
  const target = resolve(path);
  await writeJsonAtomic(target, value);
  const written = JSON.parse(await readFile(target, "utf8"));
  if (canonicalJson(written) !== canonicalJson(value)) throw new Error(`evidence verification failed for ${target}`);
}

function commandOutput(command, args, root) {
  return execFileSync(command, args, { cwd: root, encoding: "utf8" }).trim();
}

function readArgument(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  if (!args[index + 1]) throw new Error(`${name} requires a value`);
  return args[index + 1];
}

async function runCli(args) {
  const command = args[0] ?? "check";
  if (process.env.FOUNDRY_PROFILE !== PROFILE) {
    throw new Error(`FOUNDRY_PROFILE must be exactly ${PROFILE}`);
  }

  const baselinePath = readArgument(args, "--baseline");
  const gasEvidencePath = readArgument(args, "--gas-evidence");
  const solcVersion = command === "write-baseline" ? "0.8.28" : SOLC_VERSION;
  const evidence = await buildReleaseEvidence({
    sourceCommit: commandOutput("git", ["rev-parse", "HEAD"], REPOSITORY_ROOT),
    forgeVersion: commandOutput("forge", ["--version"], REPOSITORY_ROOT).split("\n")[0],
    workingTreeClean: commandOutput("git", ["status", "--porcelain"], REPOSITORY_ROOT) === "",
    baseline: baselinePath ? JSON.parse(await readFile(resolve(baselinePath), "utf8")) : undefined,
    gasEvidence: gasEvidencePath ? JSON.parse(await readFile(resolve(gasEvidencePath), "utf8")) : undefined,
    solcVersion,
  });

  for (const [name, contract] of Object.entries(evidence.contracts)) {
    console.log(
      `${name}: runtime ${contract.runtimeSizeBytes}/${contract.runtimeLimitBytes} bytes (${contract.runtimeHeadroomBytes} headroom); ` +
        `initcode ${contract.initcodeSizeBytes}/${contract.initcodeLimitBytes} bytes (${contract.initcodeHeadroomBytes} headroom)`,
    );
  }

  if (command === "check") return;
  if (command !== "write" && command !== "write-baseline") throw new Error(`unknown command: ${command}`);
  const output = readArgument(args, "--output");
  if (!output) throw new Error("write requires --output");
  await writeJsonAtomically(resolve(output), evidence);
  console.log(`Wrote ${output}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
