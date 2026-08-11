import { keccak256, TransactionNotFoundError, TransactionReceiptNotFoundError } from "viem";

import { writeJsonAtomic } from "../lib/atomic-json.mjs";

export const BASE_CHAIN_ID = 8453;
export const SOCIETY_SAFE = "0xc952c53d8b63919e372caa2e6fee605ee24e4d3d";
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const DEPLOYMENT_STEP_IDS = [
  "deploy-marketplace",
  "deploy-checkout",
  "authorize-checkout",
];
const SECRET_KEY_PATTERN = /private.?key|mnemonic|rpc.?url|raw.?signed/i;
const SECRET_VALUE_PATTERN = /\b(?:https?|wss?):\/\//i;
const ADDRESS_PATTERN = /^0x[0-9a-fA-F]{40}$/;
const HASH_PATTERN = /^0x[0-9a-fA-F]{64}$/;
const HEX_DATA_PATTERN = /^0x(?:[0-9a-fA-F]{2})*$/;
const DECIMAL_PATTERN = /^(0|[1-9][0-9]*)$/;
const MANIFEST_STATUSES = new Set([
  "prepared",
  "in-progress",
  "needs-reconciliation",
  "deployed",
  "activated",
  "handed-off",
]);

export class DeploymentNoGoError extends Error {
  constructor(message) {
    super(message);
    this.name = "DeploymentNoGoError";
  }
}

function normalizedAddress(value) {
  return value == null ? null : value.toLowerCase();
}

function clone(value) {
  return structuredClone(value);
}

function findStep(manifest, stepId) {
  const step = manifest.steps.find((candidate) => candidate.id === stepId);
  if (!step) throw new DeploymentNoGoError(`unknown deployment step: ${stepId}`);
  return step;
}

function findOperation(manifest, operationId) {
  const operation = manifest.operations.find((candidate) => candidate.id === operationId);
  if (!operation) throw new DeploymentNoGoError(`unknown lifecycle operation: ${operationId}`);
  return operation;
}

function assertAddress(label, value) {
  if (typeof value !== "string" || !ADDRESS_PATTERN.test(value)) {
    throw new DeploymentNoGoError(`${label} must be an address`);
  }
}

function assertHash(label, value, nullable = false) {
  if (nullable && value === null) return;
  if (typeof value !== "string" || !HASH_PATTERN.test(value)) {
    throw new DeploymentNoGoError(`${label} must be a bytes32 hash`);
  }
}

function assertDecimal(label, value, nullable = false) {
  if (nullable && value === null) return;
  if (typeof value !== "string" || !DECIMAL_PATTERN.test(value)) {
    throw new DeploymentNoGoError(`${label} must be an unsigned decimal string`);
  }
}

function assertHexData(label, value) {
  if (typeof value !== "string" || !HEX_DATA_PATTERN.test(value)) {
    throw new DeploymentNoGoError(`${label} must be even-length hex data`);
  }
}

function assertReceipt(label, receipt, expectedHash) {
  if (receipt === null) return;
  if (!receipt || typeof receipt !== "object") {
    throw new DeploymentNoGoError(`${label} receipt must be an object or null`);
  }
  assertHash(`${label} receipt transaction hash`, receipt.transactionHash);
  if (expectedHash && receipt.transactionHash.toLowerCase() !== expectedHash.toLowerCase()) {
    throw new DeploymentNoGoError(`${label} receipt transaction hash mismatch`);
  }
  if (!["success", "reverted"].includes(receipt.status)) {
    throw new DeploymentNoGoError(`${label} receipt status is invalid`);
  }
  assertDecimal(`${label} receipt block number`, receipt.blockNumber);
  assertHash(`${label} receipt block hash`, receipt.blockHash);
  if (receipt.contractAddress !== null) assertAddress(`${label} receipt contract address`, receipt.contractAddress);
  assertDecimal(`${label} receipt gas used`, receipt.gasUsed);
}

function assertReplacementHistory(label, history, submittedHash) {
  if (!Array.isArray(history)) throw new DeploymentNoGoError(`${label} replacement history must be an array`);
  let previousReplacement = null;
  for (const entry of history) {
    assertHash(`${label} replacement previous hash`, entry.previousHash);
    assertHash(`${label} replacement hash`, entry.replacementHash);
    if (typeof entry.reason !== "string" || entry.reason.length === 0) {
      throw new DeploymentNoGoError(`${label} replacement reason is required`);
    }
    if (previousReplacement && entry.previousHash.toLowerCase() !== previousReplacement.toLowerCase()) {
      throw new DeploymentNoGoError(`${label} replacement history is not contiguous`);
    }
    previousReplacement = entry.replacementHash;
  }
  if (previousReplacement && previousReplacement.toLowerCase() !== submittedHash?.toLowerCase()) {
    throw new DeploymentNoGoError(`${label} replacement history does not end at the submitted hash`);
  }
}

function assertTransactionState(label, transaction) {
  assertHash(`${label} input hash`, transaction.transactionInputHash);
  assertHexData(`${label} input`, transaction.transactionInput);
  if (keccak256(transaction.transactionInput) !== transaction.transactionInputHash) {
    throw new DeploymentNoGoError(`${label} calldata hash drift`);
  }
  assertHash(`${label} submitted hash`, transaction.submittedHash, true);
  assertDecimal(`${label} submitted block`, transaction.submittedAtBlock, true);
  if (Boolean(transaction.submittedHash) !== Boolean(transaction.submittedAtBlock)) {
    throw new DeploymentNoGoError(`${label} submitted hash and block must be recorded together`);
  }
  assertReplacementHistory(label, transaction.replacementHistory, transaction.submittedHash);
  assertReceipt(label, transaction.receipt, transaction.submittedHash);
  if (transaction.receipt && transaction.observedResult?.verified !== true) {
    throw new DeploymentNoGoError(`${label} confirmed receipt requires a verified result`);
  }
  if (!transaction.receipt && transaction.observedResult !== null) {
    throw new DeploymentNoGoError(`${label} cannot record a result without a receipt`);
  }
}

export function isReceiptLookupMiss(error) {
  return error instanceof TransactionReceiptNotFoundError;
}

export function isTransactionLookupMiss(error) {
  return error instanceof TransactionNotFoundError;
}

function assertNoSecrets(value, path = "manifest") {
  if (typeof value === "string") {
    const secretLine = value.split("\n").some((line) => {
      if (/\b(?:Request body|Authorization):/i.test(line)) {
        return !/\b(?:Request body|Authorization):\s*\[redacted\]\s*$/i.test(line);
      }
      const bearer = line.match(/\bBearer\s+([^\s,;]+)/i);
      if (bearer && bearer[1] !== "[redacted]") return true;
      const credential = line.match(
        /\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|secret|private[_-]?key|mnemonic|raw[_-]?signed(?:[_-]?transaction)?)\b["']?\s*[:=]\s*([^\s&,;]+)/i,
      );
      return Boolean(credential && credential[1] !== "[redacted]");
    });
    if (SECRET_VALUE_PATTERN.test(value) || secretLine) {
      throw new DeploymentNoGoError(`secret-bearing manifest value is forbidden: ${path}`);
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoSecrets(entry, `${path}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, entry] of Object.entries(value)) {
    if (SECRET_KEY_PATTERN.test(key)) {
      throw new DeploymentNoGoError(`secret-bearing manifest field is forbidden: ${path}.${key}`);
    }
    assertNoSecrets(entry, `${path}.${key}`);
  }
}

function assertLifecycleOperation(manifest, operation) {
  if (typeof operation.id !== "string" || operation.id.length === 0) {
    throw new DeploymentNoGoError("lifecycle operation id is required");
  }
  assertAddress(`${operation.id} sender`, operation.sender);
  assertAddress(`${operation.id} target`, operation.target);
  if (normalizedAddress(operation.target) !== normalizedAddress(manifest.intent.marketplace)) {
    throw new DeploymentNoGoError(`${operation.id} must target the pinned marketplace`);
  }
  if (operation.kind === "deployer-activation") {
    if (
      operation.authority !== "deployer" ||
      normalizedAddress(operation.sender) !== normalizedAddress(manifest.intent.deployer) ||
      normalizedAddress(operation.expectedResult?.owner) !== normalizedAddress(manifest.intent.deployer) ||
      operation.expectedResult?.paused !== false ||
      normalizedAddress(operation.expectedResult?.eventAccount) !== normalizedAddress(manifest.intent.deployer)
    ) {
      throw new DeploymentNoGoError("deployer activation must bind the deployer event and final state");
    }
    assertDecimal(`${operation.id} nonce`, operation.nonce);
    assertAddress(`${operation.id} expected owner`, operation.expectedResult.owner);
    assertAddress(`${operation.id} expected event account`, operation.expectedResult.eventAccount);
    return;
  }
  if (operation.kind === "ownership-handoff") {
    if (
      operation.authority !== "deployer" ||
      normalizedAddress(operation.sender) !== normalizedAddress(manifest.intent.deployer) ||
      normalizedAddress(operation.expectedResult?.owner) !== SOCIETY_SAFE ||
      operation.expectedResult?.paused !== true ||
      operation.expectedResult?.safeHasCode !== true
    ) {
      throw new DeploymentNoGoError("ownership handoff must pin the deployed Society Safe while paused");
    }
    assertDecimal(`${operation.id} nonce`, operation.nonce);
    assertAddress(`${operation.id} expected owner`, operation.expectedResult.owner);
    return;
  }
  if (operation.kind === "safe-activation") {
    if (
      operation.authority !== "society-safe" ||
      normalizedAddress(operation.sender) !== SOCIETY_SAFE ||
      normalizedAddress(operation.expectedResult?.owner) !== SOCIETY_SAFE ||
      operation.expectedResult?.paused !== false ||
      normalizedAddress(operation.expectedResult?.eventAccount) !== SOCIETY_SAFE
    ) {
      throw new DeploymentNoGoError("Safe activation must bind the Society Safe event and final state");
    }
    if (operation.nonce !== null) throw new DeploymentNoGoError("Safe activation must not pin an outer nonce");
    assertAddress(`${operation.id} expected owner`, operation.expectedResult.owner);
    assertAddress(`${operation.id} expected event account`, operation.expectedResult.eventAccount);
    return;
  }
  throw new DeploymentNoGoError(`unsupported lifecycle operation: ${operation.kind}`);
}

export function assertManifest(manifest) {
  if (!manifest || typeof manifest !== "object") {
    throw new DeploymentNoGoError("deployment manifest must be an object");
  }
  if (manifest.schemaVersion !== 1) {
    throw new DeploymentNoGoError(`unsupported deployment manifest schema: ${manifest.schemaVersion}`);
  }
  if (manifest.kind !== "base-universal-pool-art-marketplace") {
    throw new DeploymentNoGoError(`unexpected deployment manifest kind: ${manifest.kind}`);
  }
  if (!MANIFEST_STATUSES.has(manifest.status)) {
    throw new DeploymentNoGoError(`invalid deployment manifest status: ${manifest.status}`);
  }
  if (manifest.chain?.chainId !== BASE_CHAIN_ID) {
    throw new DeploymentNoGoError(`deployment manifest must target Base chain ${BASE_CHAIN_ID}`);
  }
  assertDecimal("prepared block", manifest.chain.preparedAtBlock);
  assertHash("prepared block hash", manifest.chain.preparedAtBlockHash);
  if (!["production", "fork-rehearsal"].includes(manifest.intent?.deploymentMode)) {
    throw new DeploymentNoGoError("deployment manifest must pin production or fork-rehearsal mode");
  }
  assertAddress("deployer", manifest.intent.deployer);
  assertAddress("marketplace", manifest.intent.marketplace);
  assertAddress("checkout", manifest.intent.checkout);
  assertDecimal("starting nonce", manifest.intent.startingNonce);
  if (manifest.intent.foundryProfile !== "universal_marketplace") {
    throw new DeploymentNoGoError("deployment manifest must pin the universal_marketplace profile");
  }
  if (manifest.intent.solcVersion !== "0.8.36") {
    throw new DeploymentNoGoError("deployment manifest compiler mismatch");
  }
  if (manifest.intent.evmVersion !== "cancun" || manifest.intent.optimizerRuns !== 200 || manifest.intent.viaIr !== false) {
    throw new DeploymentNoGoError("deployment manifest compiler settings mismatch");
  }
  for (const [label, artifact] of [
    ["marketplace", manifest.artifacts?.marketplace],
    ["checkout", manifest.artifacts?.checkout],
  ]) {
    for (const field of ["abiHash", "creationBytecodeHash", "runtimeTemplateHash", "expectedRuntimeCodeHash"]) {
      assertHash(`${label} ${field}`, artifact?.[field]);
    }
  }
  const dependencies = manifest.inputs?.canonicalDependencies;
  assertAddress("canonical Society mirror", dependencies?.mirror);
  assertAddress("canonical child renderer", dependencies?.childRenderer);
  const marketplaceInputs = manifest.inputs?.marketplaceConstructor;
  const checkoutInputs = manifest.inputs?.checkoutConstructor;
  const authorization = manifest.inputs?.authorization;
  assertHash("marketplace constructor encoded hash", marketplaceInputs?.encodedHash);
  assertHash("checkout constructor encoded hash", checkoutInputs?.encodedHash);
  assertHash("authorization calldata hash", authorization?.calldataHash);
  assertAddress("authorization target", authorization?.target);
  assertAddress("authorization checkout", authorization?.checkout);
  for (const field of ["fame", "creatorMagic", "feeRecipient", "owner"]) {
    assertAddress(`marketplace constructor ${field}`, marketplaceInputs?.values?.[field]);
  }
  for (const field of ["communityFee", "providerFee", "activeProviderCap"]) {
    assertDecimal(`marketplace constructor ${field}`, marketplaceInputs?.values?.[field]);
  }
  for (const field of ["router", "marketplace", "fame", "usdc", "weth"]) {
    assertAddress(`checkout constructor ${field}`, checkoutInputs?.values?.[field]);
  }
  if (
    normalizedAddress(authorization.target) !== normalizedAddress(manifest.intent.marketplace) ||
    normalizedAddress(authorization.checkout) !== normalizedAddress(manifest.intent.checkout) ||
    normalizedAddress(marketplaceInputs.values.owner) !== normalizedAddress(manifest.intent.deployer) ||
    normalizedAddress(marketplaceInputs.values.fame) !== normalizedAddress(checkoutInputs.values.fame) ||
    normalizedAddress(checkoutInputs.values.marketplace) !== normalizedAddress(manifest.intent.marketplace)
  ) {
    throw new DeploymentNoGoError("constructor or authorization inputs do not match the pinned stack");
  }
  if (!Array.isArray(manifest.steps) || manifest.steps.length !== DEPLOYMENT_STEP_IDS.length) {
    throw new DeploymentNoGoError("deployment manifest must contain exactly three deployment steps");
  }
  for (let index = 0; index < DEPLOYMENT_STEP_IDS.length; index += 1) {
    const step = manifest.steps[index];
    if (step.id !== DEPLOYMENT_STEP_IDS[index]) {
      throw new DeploymentNoGoError(`deployment step ${index} must be ${DEPLOYMENT_STEP_IDS[index]}`);
    }
    if (step.purpose !== step.id) throw new DeploymentNoGoError(`purpose mismatch for ${step.id}`);
    assertAddress(`${step.id} sender`, step.sender);
    assertDecimal(`${step.id} nonce`, step.nonce);
    const expectedNonce = BigInt(manifest.intent.startingNonce) + BigInt(index);
    if (BigInt(step.nonce) !== expectedNonce) {
      throw new DeploymentNoGoError(`nonce mismatch for ${step.id}`);
    }
    if (normalizedAddress(step.sender) !== normalizedAddress(manifest.intent.deployer)) {
      throw new DeploymentNoGoError(`sender mismatch for ${step.id}`);
    }
    if (step.predictedAddress !== null) assertAddress(`${step.id} predicted address`, step.predictedAddress);
    if (step.target !== null) assertAddress(`${step.id} target`, step.target);
    assertTransactionState(step.id, step);
  }
  if (normalizedAddress(manifest.steps[0].predictedAddress) !== normalizedAddress(manifest.intent.marketplace)) {
    throw new DeploymentNoGoError("marketplace predicted address mismatch");
  }
  if (normalizedAddress(manifest.steps[1].predictedAddress) !== normalizedAddress(manifest.intent.checkout)) {
    throw new DeploymentNoGoError("checkout predicted address mismatch");
  }
  if (manifest.steps[0].target !== null || manifest.steps[1].target !== null) {
    throw new DeploymentNoGoError("contract creation steps must not pin a target");
  }
  if (normalizedAddress(manifest.steps[2].target) !== normalizedAddress(manifest.intent.marketplace)) {
    throw new DeploymentNoGoError("authorization target mismatch");
  }
  if (manifest.steps[2].predictedAddress !== null) {
    throw new DeploymentNoGoError("authorization step must not predict a contract address");
  }
  let unconfirmedPrefixSeen = false;
  for (let index = 0; index < manifest.steps.length; index += 1) {
    const step = manifest.steps[index];
    if (!step.receipt) {
      unconfirmedPrefixSeen = true;
    } else {
      if (unconfirmedPrefixSeen) {
        throw new DeploymentNoGoError(`${step.id} receipt is outside the confirmed deployment prefix`);
      }
      const expectedContractAddress = index === 0 ? manifest.intent.marketplace : index === 1 ? manifest.intent.checkout : null;
      if (normalizedAddress(step.receipt.contractAddress) !== normalizedAddress(expectedContractAddress)) {
        throw new DeploymentNoGoError(`${step.id} receipt contract address mismatch`);
      }
    }
    if (index > 0 && step.submittedHash && !manifest.steps[index - 1].receipt) {
      throw new DeploymentNoGoError(`${step.id} was submitted before its confirmed prefix`);
    }
  }
  if (["deployed", "activated", "handed-off"].includes(manifest.status) && manifest.steps.some((step) => !step.receipt)) {
    throw new DeploymentNoGoError(`${manifest.status} status requires a fully confirmed deployment`);
  }
  if (manifest.status === "prepared" && manifest.steps.some((step) => step.submittedHash)) {
    throw new DeploymentNoGoError("prepared status cannot contain a submitted transaction");
  }
  if (
    marketplaceInputs.encodedHash !== manifest.steps[0].transactionInputHash ||
    checkoutInputs.encodedHash !== manifest.steps[1].transactionInputHash ||
    authorization.calldataHash !== manifest.steps[2].transactionInputHash
  ) {
    throw new DeploymentNoGoError("pinned input hashes do not match deployment steps");
  }
  if (!Array.isArray(manifest.operations)) {
    throw new DeploymentNoGoError("deployment manifest operations must be an array");
  }
  const operationIds = new Set();
  for (const operation of manifest.operations) {
    if (!operation.id || operationIds.has(operation.id)) {
      throw new DeploymentNoGoError(`duplicate lifecycle operation: ${operation.id}`);
    }
    operationIds.add(operation.id);
    assertLifecycleOperation(manifest, operation);
    assertDecimal(`${operation.id} prepared block`, operation.preparedAtBlock);
    assertTransactionState(operation.id, operation);
    assertHash(`${operation.id} execution transaction hash`, operation.executionTransactionHash, true);
    assertHash(`${operation.id} Safe transaction hash`, operation.safeTransactionHash, true);
    if (operation.receipt) {
      if (operation.executionTransactionHash !== operation.receipt.transactionHash) {
        throw new DeploymentNoGoError(`${operation.id} execution transaction hash mismatch`);
      }
      if (operation.authority === "society-safe" && operation.safeTransactionHash === null) {
        throw new DeploymentNoGoError(`${operation.id} confirmed Safe operation requires a Safe transaction hash`);
      }
    } else if (operation.executionTransactionHash !== null || operation.safeTransactionHash !== null) {
      throw new DeploymentNoGoError(`${operation.id} unconfirmed operation cannot record execution hashes`);
    }
    if (operation.canonicalObservation) {
      const canonical = operation.canonicalObservation;
      assertHash(`${operation.id} canonical execution hash`, canonical.executionTransactionHash);
      assertHash(`${operation.id} canonical transaction hash`, canonical.transaction?.hash);
      assertAddress(`${operation.id} canonical sender`, canonical.transaction?.from);
      assertDecimal(`${operation.id} canonical nonce`, canonical.transaction?.nonce);
      if (canonical.transaction?.to !== null) {
        assertAddress(`${operation.id} canonical target`, canonical.transaction?.to);
      }
      assertHash(`${operation.id} canonical input hash`, canonical.transaction?.transactionInputHash);
      assertReceipt(operation.id, canonical.receipt, canonical.executionTransactionHash);
      if (canonical.transaction.hash.toLowerCase() !== canonical.executionTransactionHash.toLowerCase()) {
        throw new DeploymentNoGoError(`${operation.id} canonical execution hash mismatch`);
      }
      if (operation.authority === "society-safe") {
        assertHash(`${operation.id} canonical Safe transaction hash`, canonical.safeTransactionHash);
      } else if (canonical.safeTransactionHash !== null) {
        throw new DeploymentNoGoError(`${operation.id} direct canonical observation cannot record a Safe hash`);
      }
      if (manifest.status !== "needs-reconciliation") {
        throw new DeploymentNoGoError(`${operation.id} conflicting canonical observation requires no-go status`);
      }
    }
  }
  assertNoSecrets(manifest);
  return manifest;
}

export function assertSamePayload(step, transaction) {
  const expectedTarget = normalizedAddress(step.target);
  const actualTarget = normalizedAddress(transaction.to);
  if (step.sender && normalizedAddress(transaction.from) !== normalizedAddress(step.sender)) {
    throw new DeploymentNoGoError(`sender mismatch for ${step.id}`);
  }
  if (BigInt(transaction.nonce) !== BigInt(step.nonce)) {
    throw new DeploymentNoGoError(`nonce mismatch for ${step.id}`);
  }
  if (expectedTarget !== actualTarget) {
    throw new DeploymentNoGoError(`target mismatch for ${step.id}`);
  }
  if (transaction.transactionInputHash !== step.transactionInputHash) {
    throw new DeploymentNoGoError(`transaction input mismatch for ${step.id}`);
  }
}

function assertObservedTransaction(manifest, step, transaction) {
  if (normalizedAddress(transaction.from) !== normalizedAddress(manifest.intent.deployer)) {
    throw new DeploymentNoGoError(`sender mismatch for ${step.id}`);
  }
  assertSamePayload(step, transaction);
}

function assertPredictedState(manifest, observation, prefix) {
  const predicted = observation.predicted ?? {};
  const expectedMarketplaceHash = manifest.artifacts?.marketplace?.expectedRuntimeCodeHash;
  const expectedCheckoutHash = manifest.artifacts?.checkout?.expectedRuntimeCodeHash;

  if (prefix === 0 && predicted.marketplaceCodeHash !== null) {
    throw new DeploymentNoGoError("unexpected code at the predicted marketplace address");
  }
  if (prefix >= 1 && !predicted.marketplaceCodeHash) {
    throw new DeploymentNoGoError("confirmed marketplace deployment has no code");
  }
  if (expectedMarketplaceHash && prefix >= 1 && predicted.marketplaceCodeHash !== expectedMarketplaceHash) {
    throw new DeploymentNoGoError("marketplace runtime code hash mismatch");
  }
  if (prefix < 2 && predicted.checkoutCodeHash !== null) {
    throw new DeploymentNoGoError("unexpected code at the predicted checkout address");
  }
  if (prefix >= 2 && !predicted.checkoutCodeHash) {
    throw new DeploymentNoGoError("confirmed checkout deployment has no code");
  }
  if (expectedCheckoutHash && prefix >= 2 && predicted.checkoutCodeHash !== expectedCheckoutHash) {
    throw new DeploymentNoGoError("checkout runtime code hash mismatch");
  }

  const actualCheckout = normalizedAddress(predicted.authorizedCheckout);
  const expectedCheckout = prefix >= 3 ? normalizedAddress(manifest.intent.checkout) : ZERO_ADDRESS;
  if (actualCheckout !== expectedCheckout) {
    throw new DeploymentNoGoError("marketplace checkout authorization state mismatch");
  }
}

export function classifyDeployment(manifest, observation) {
  assertManifest(manifest);
  let confirmedPrefix = 0;
  let uncertain = null;

  for (const step of manifest.steps) {
    const observed = observation.steps?.[step.id];
    if (!observed?.transaction) {
      if (step.submittedHash) uncertain = "submitted transaction has no canonical receipt";
      break;
    }
    assertObservedTransaction(manifest, step, observed.transaction);

    if (!observed.receipt) {
      uncertain = "submitted transaction has no canonical receipt";
      break;
    }
    if (observed.receipt.status === "reverted") {
      throw new DeploymentNoGoError(`${step.id} reverted and consumed its pinned nonce`);
    }
    if (observed.receipt.status !== "success") {
      throw new DeploymentNoGoError(`${step.id} has an unknown receipt status`);
    }
    if (observed.result?.verified !== true) {
      throw new DeploymentNoGoError(`${step.id} canonical result did not match the manifest`);
    }
    confirmedPrefix += 1;
  }

  const laterObservedStep = manifest.steps
    .slice(confirmedPrefix + (uncertain ? 1 : 0))
    .find((step) => observation.steps?.[step.id]?.transaction);
  if (laterObservedStep) {
    throw new DeploymentNoGoError(`non-contiguous deployment result at ${laterObservedStep.id}`);
  }

  assertPredictedState(manifest, observation, confirmedPrefix);

  if (uncertain) {
    return {
      kind: "uncertain",
      confirmedPrefix,
      nextStepId: null,
      reason: uncertain,
    };
  }

  if (confirmedPrefix === manifest.steps.length) {
    return { kind: "complete", confirmedPrefix, nextStepId: null };
  }

  const expectedNonce = BigInt(manifest.intent.startingNonce) + BigInt(confirmedPrefix);
  if (
    BigInt(observation.account.latestNonce) !== expectedNonce ||
    BigInt(observation.account.pendingNonce) !== expectedNonce
  ) {
    throw new DeploymentNoGoError(
      `deployer nonce mismatch at prefix ${confirmedPrefix}: expected ${expectedNonce}`,
    );
  }

  return {
    kind: "ready",
    confirmedPrefix,
    nextStepId: manifest.steps[confirmedPrefix].id,
  };
}

export function recordSubmission(manifest, stepId, transactionHash, submittedAtBlock) {
  assertManifest(manifest);
  const updated = clone(manifest);
  const step = findStep(updated, stepId);
  if (step.receipt) throw new DeploymentNoGoError(`${stepId} is already confirmed`);
  if (step.submittedHash) throw new DeploymentNoGoError(`${stepId} already has a submitted transaction`);
  step.submittedHash = transactionHash;
  step.submittedAtBlock = String(submittedAtBlock);
  updated.status = "in-progress";
  return assertManifest(updated);
}

export function applyReplacement(manifest, stepId, replacementTransaction, reason) {
  assertManifest(manifest);
  const updated = clone(manifest);
  const step = findStep(updated, stepId);
  if (!step.submittedHash) {
    throw new DeploymentNoGoError(`${stepId} has no submitted transaction to replace`);
  }
  if (normalizedAddress(replacementTransaction.from) !== normalizedAddress(updated.intent.deployer)) {
    throw new DeploymentNoGoError(`sender mismatch for ${step.id}`);
  }
  assertSamePayload(step, replacementTransaction);
  step.replacementHistory.push({
    previousHash: step.submittedHash,
    replacementHash: replacementTransaction.hash,
    reason,
  });
  step.submittedHash = replacementTransaction.hash;
  updated.status = "in-progress";
  return assertManifest(updated);
}

export function prepareLifecycleOperation(manifest, operation) {
  assertManifest(manifest);
  const updated = clone(manifest);
  if (updated.operations.some((candidate) => candidate.id === operation.id)) {
    throw new DeploymentNoGoError(`duplicate lifecycle operation: ${operation.id}`);
  }
  assertLifecycleOperation(updated, operation);
  updated.operations.push({
    ...clone(operation),
    preparedAtBlock: String(operation.preparedAtBlock ?? manifest.chain.preparedAtBlock),
    submittedHash: null,
    submittedAtBlock: null,
    executionTransactionHash: null,
    safeTransactionHash: null,
    replacementHistory: [],
    receipt: null,
    observedResult: null,
    canonicalObservation: null,
  });
  return assertManifest(updated);
}

export function recordCanonicalOperation(
  manifest,
  operationId,
  observation,
  observedResult,
  safeExecution = null,
) {
  assertManifest(manifest);
  const updated = clone(manifest);
  const operation = findOperation(updated, operationId);
  const { transaction, receipt } = observation;
  assertHash(`${operationId} canonical transaction hash`, transaction?.hash);
  assertAddress(`${operationId} canonical sender`, transaction?.from);
  assertDecimal(`${operationId} canonical nonce`, transaction?.nonce);
  if (transaction.to !== null) assertAddress(`${operationId} canonical target`, transaction?.to);
  assertHash(`${operationId} canonical input hash`, transaction?.transactionInputHash);
  assertReceipt(operationId, receipt, transaction.hash);
  if (receipt.status !== "success") throw new DeploymentNoGoError(`${operationId} execution reverted`);
  if (observedResult?.verified !== true) {
    throw new DeploymentNoGoError(`${operationId} canonical result did not match the manifest`);
  }

  let safeTransactionHash = null;
  if (operation.authority === "deployer") {
    assertSamePayload(operation, transaction);
    if (normalizedAddress(transaction.from) !== normalizedAddress(operation.sender)) {
      throw new DeploymentNoGoError(`sender mismatch for ${operation.id}`);
    }
    if (safeExecution !== null) {
      throw new DeploymentNoGoError(`${operationId} direct operation cannot record a Safe transaction hash`);
    }
  } else {
    if (normalizedAddress(transaction.to) !== SOCIETY_SAFE) {
      throw new DeploymentNoGoError(`${operationId} outer transaction must target the Society Safe`);
    }
    if (!safeExecution || typeof safeExecution !== "object") {
      throw new DeploymentNoGoError(`${operationId} requires decoded Safe execution evidence`);
    }
    assertHash(`${operationId} reviewed Safe transaction hash`, safeExecution.reviewedHash);
    assertHash(`${operationId} emitted Safe transaction hash`, safeExecution.emittedHash);
    if (safeExecution.reviewedHash.toLowerCase() !== safeExecution.emittedHash.toLowerCase()) {
      throw new DeploymentNoGoError(`${operationId} reviewed Safe transaction hash mismatch`);
    }
    if (safeExecution.eventName !== "ExecutionSuccess") {
      throw new DeploymentNoGoError(`${operationId} requires Safe ExecutionSuccess evidence`);
    }
    safeTransactionHash = safeExecution.reviewedHash;
  }

  if (operation.submittedHash && operation.submittedHash !== transaction.hash) {
    operation.replacementHistory.push({
      previousHash: operation.submittedHash,
      replacementHash: transaction.hash,
      reason: "canonical nonce replacement discovered during reconciliation",
    });
  }
  operation.submittedHash = transaction.hash;
  operation.submittedAtBlock ??= operation.preparedAtBlock;
  operation.executionTransactionHash = transaction.hash;
  operation.safeTransactionHash = safeTransactionHash;
  operation.receipt = clone(receipt);
  operation.observedResult = clone(observedResult);
  operation.canonicalObservation = null;
  updated.status = operation.kind === "ownership-handoff" ? "handed-off" : "activated";
  return assertManifest(updated);
}

export function recordCanonicalOperationFailure(
  manifest,
  operationId,
  observation,
  safeTransactionHash,
  errorMessage,
) {
  assertManifest(manifest);
  const updated = clone(manifest);
  const operation = findOperation(updated, operationId);
  const { transaction, receipt } = observation;
  assertHash(`${operationId} canonical transaction hash`, transaction?.hash);
  assertAddress(`${operationId} canonical sender`, transaction?.from);
  assertDecimal(`${operationId} canonical nonce`, transaction?.nonce);
  if (transaction.to !== null) assertAddress(`${operationId} canonical target`, transaction?.to);
  assertHash(`${operationId} canonical input hash`, transaction?.transactionInputHash);
  assertReceipt(operationId, receipt, transaction.hash);
  if (operation.authority === "society-safe") {
    assertHash(`${operationId} canonical Safe transaction hash`, safeTransactionHash);
  } else if (safeTransactionHash !== null) {
    throw new DeploymentNoGoError(`${operationId} direct operation cannot record a Safe transaction hash`);
  }
  if (typeof errorMessage !== "string" || errorMessage.length === 0) {
    throw new DeploymentNoGoError(`${operationId} canonical failure reason is required`);
  }
  updated.status = "needs-reconciliation";
  operation.canonicalObservation = {
    transaction: clone(transaction),
    receipt: clone(receipt),
    executionTransactionHash: transaction.hash,
    safeTransactionHash,
    observedAt: new Date().toISOString(),
    error: errorMessage,
  };
  return assertManifest(updated);
}

export async function writeManifestAtomic(path, manifest) {
  assertManifest(manifest);
  await writeJsonAtomic(path, manifest);
}
