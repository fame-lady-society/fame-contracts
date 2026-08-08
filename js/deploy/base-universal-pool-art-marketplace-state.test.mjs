import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { keccak256, TransactionNotFoundError, TransactionReceiptNotFoundError } from "viem";

import {
  DeploymentNoGoError,
  applyReplacement,
  classifyDeployment,
  isReceiptLookupMiss,
  isTransactionLookupMiss,
  prepareLifecycleOperation,
  recordCanonicalOperation,
  recordCanonicalOperationFailure,
  recordSubmission,
  writeManifestAtomic,
} from "./base-universal-pool-art-marketplace-state.mjs";

const DEPLOYER = "0x1111111111111111111111111111111111111111";
const MARKETPLACE = "0x2222222222222222222222222222222222222222";
const CHECKOUT = "0x3333333333333333333333333333333333333333";
const SAFE = "0xc952c53d8b63919e372caa2e6fee605ee24e4d3d";
const ZERO = "0x0000000000000000000000000000000000000000";

function step(id, nonce, target, predictedAddress, transactionInput) {
  return {
    id,
    purpose: id,
    sender: DEPLOYER,
    nonce: String(nonce),
    target,
    predictedAddress,
    transactionInputHash: keccak256(transactionInput),
    transactionInput,
    submittedHash: null,
    submittedAtBlock: null,
    replacementHistory: [],
    receipt: null,
    observedResult: null,
  };
}

function manifest() {
  const marketInput = "0x6001";
  const checkoutInput = "0x6002";
  const authorizationInput = "0x1234";
  return {
    schemaVersion: 1,
    kind: "base-universal-pool-art-marketplace",
    status: "prepared",
    chain: {
      chainId: 8453,
      preparedAtBlock: "100",
      preparedAtBlockHash: `0x${"a".repeat(64)}`,
    },
    intent: {
      deployer: DEPLOYER,
      deploymentMode: "production",
      startingNonce: "40",
      marketplace: MARKETPLACE,
      checkout: CHECKOUT,
      sourceCommit: "abc123",
      foundryProfile: "universal_marketplace",
      solcVersion: "0.8.36",
      evmVersion: "cancun",
      optimizerRuns: 200,
      viaIr: false,
    },
    artifacts: {
      marketplace: {
        abiHash: `0x${"1".repeat(64)}`,
        creationBytecodeHash: `0x${"2".repeat(64)}`,
        runtimeTemplateHash: `0x${"3".repeat(64)}`,
        expectedRuntimeCodeHash: `0x${"4".repeat(64)}`,
      },
      checkout: {
        abiHash: `0x${"2".repeat(64)}`,
        creationBytecodeHash: `0x${"3".repeat(64)}`,
        runtimeTemplateHash: `0x${"4".repeat(64)}`,
        expectedRuntimeCodeHash: `0x${"5".repeat(64)}`,
      },
    },
    inputs: {
      canonicalDependencies: {
        mirror: "0x4444444444444444444444444444444444444444",
        childRenderer: "0x5555555555555555555555555555555555555555",
      },
      marketplaceConstructor: {
        values: {
          fame: "0x6666666666666666666666666666666666666666",
          creatorMagic: "0x7777777777777777777777777777777777777777",
          communityFee: "1",
          providerFee: "2",
          feeRecipient: SAFE,
          owner: DEPLOYER,
          activeProviderCap: "88",
        },
        encodedHash: keccak256(marketInput),
      },
      checkoutConstructor: {
        values: {
          router: "0x8888888888888888888888888888888888888888",
          marketplace: MARKETPLACE,
          fame: "0x6666666666666666666666666666666666666666",
          usdc: "0x9999999999999999999999999999999999999999",
          weth: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        },
        encodedHash: keccak256(checkoutInput),
      },
      authorization: {
        target: MARKETPLACE,
        checkout: CHECKOUT,
        calldataHash: keccak256(authorizationInput),
      },
    },
    steps: [
      step("deploy-marketplace", 40, null, MARKETPLACE, marketInput),
      step("deploy-checkout", 41, null, CHECKOUT, checkoutInput),
      step("authorize-checkout", 42, MARKETPLACE, null, authorizationInput),
    ],
    operations: [],
  };
}

function confirmed(stepValue) {
  return {
    transaction: {
      hash: `0x${stepValue.nonce.padStart(64, "0")}`,
      from: DEPLOYER,
      nonce: stepValue.nonce,
      to: stepValue.target,
      transactionInputHash: stepValue.transactionInputHash,
    },
    receipt: {
      status: "success",
      blockNumber: String(100 + Number(stepValue.nonce)),
      blockHash: `0x${"b".repeat(64)}`,
    },
    result: { verified: true, checks: { exact: true } },
  };
}

function observation(prefix) {
  const value = manifest();
  const steps = {};
  for (let index = 0; index < prefix; index += 1) {
    steps[value.steps[index].id] = confirmed(value.steps[index]);
  }
  return {
    account: {
      latestNonce: String(40 + prefix),
      pendingNonce: String(40 + prefix),
    },
    predicted: {
      marketplaceCodeHash: prefix >= 1 ? `0x${"4".repeat(64)}` : null,
      checkoutCodeHash: prefix >= 2 ? `0x${"5".repeat(64)}` : null,
      authorizedCheckout: prefix >= 3 ? CHECKOUT : ZERO,
    },
    steps,
  };
}

function deployedManifest() {
  const value = manifest();
  for (let index = 0; index < value.steps.length; index += 1) {
    const stepValue = value.steps[index];
    const hash = `0x${String(index + 1).repeat(64)}`;
    stepValue.submittedHash = hash;
    stepValue.submittedAtBlock = String(101 + index);
    stepValue.receipt = {
      transactionHash: hash,
      status: "success",
      blockNumber: String(101 + index),
      blockHash: `0x${String(index + 4).repeat(64)}`,
      contractAddress: index === 0 ? MARKETPLACE : index === 1 ? CHECKOUT : null,
      gasUsed: "50000",
    };
    stepValue.observedResult = { verified: true, verifiedAtBlock: String(101 + index), checks: {} };
  }
  value.status = "deployed";
  return value;
}

test("the four valid prefixes select only the first unexecuted step", () => {
  const expected = [
    [0, "deploy-marketplace"],
    [1, "deploy-checkout"],
    [2, "authorize-checkout"],
  ];

  for (const [prefix, nextStepId] of expected) {
    assert.deepEqual(classifyDeployment(manifest(), observation(prefix)), {
      kind: "ready",
      confirmedPrefix: prefix,
      nextStepId,
    });
  }

  assert.deepEqual(classifyDeployment(manifest(), observation(3)), {
    kind: "complete",
    confirmedPrefix: 3,
    nextStepId: null,
  });
});

test("a completed deployment never produces another submission", () => {
  const result = classifyDeployment(manifest(), observation(3));
  assert.equal(result.kind, "complete");
  assert.equal(result.nextStepId, null);
});

test("an uncertain submitted transaction stops without advancing", () => {
  const value = recordSubmission(
    manifest(),
    "deploy-marketplace",
    `0x${"6".repeat(64)}`,
    "101",
  );
  const observed = observation(0);
  observed.account.pendingNonce = "41";

  assert.deepEqual(classifyDeployment(value, observed), {
    kind: "uncertain",
    confirmedPrefix: 0,
    nextStepId: null,
    reason: "submitted transaction has no canonical receipt",
  });
});

test("a reverted receipt cannot be mistaken for a successful prefix", () => {
  const value = manifest();
  const observed = observation(0);
  observed.account.latestNonce = "41";
  observed.account.pendingNonce = "41";
  observed.steps["deploy-marketplace"] = confirmed(value.steps[0]);
  observed.steps["deploy-marketplace"].receipt.status = "reverted";

  assert.throws(
    () => classifyDeployment(value, observed),
    (error) => error instanceof DeploymentNoGoError && /reverted/.test(error.message),
  );
});

test("nonce, payload, result, and predicted-address drift fail closed", () => {
  const cases = [
    (value) => {
      value.account.latestNonce = "41";
      value.account.pendingNonce = "41";
    },
    (value) => {
      value.steps["deploy-marketplace"] = confirmed(manifest().steps[0]);
      value.steps["deploy-marketplace"].transaction.transactionInputHash = `0x${"9".repeat(64)}`;
      value.account.latestNonce = "41";
      value.account.pendingNonce = "41";
    },
    (value) => {
      value.steps["deploy-marketplace"] = confirmed(manifest().steps[0]);
      value.steps["deploy-marketplace"].result.verified = false;
      value.account.latestNonce = "41";
      value.account.pendingNonce = "41";
    },
    (value) => {
      value.predicted.marketplaceCodeHash = `0x${"4".repeat(64)}`;
    },
    (value) => {
      value.steps["deploy-marketplace"] = confirmed(manifest().steps[0]);
      value.account.latestNonce = "41";
      value.account.pendingNonce = "41";
      value.predicted.marketplaceCodeHash = `0x${"9".repeat(64)}`;
    },
  ];

  for (const mutate of cases) {
    const observed = observation(0);
    mutate(observed);
    assert.throws(() => classifyDeployment(manifest(), observed), DeploymentNoGoError);
  }
});

test("manifest address and sender drift fails before recovery", () => {
  const wrongAddress = manifest();
  wrongAddress.steps[0].predictedAddress = CHECKOUT;
  assert.throws(() => classifyDeployment(wrongAddress, observation(0)), DeploymentNoGoError);

  const wrongSender = manifest();
  wrongSender.steps[1].sender = SAFE;
  assert.throws(() => classifyDeployment(wrongSender, observation(0)), DeploymentNoGoError);
});

test("manifest schema rejects malformed hashes, calldata drift, and impossible transaction state", () => {
  const cases = [
    (value) => {
      value.intent.deployer = "0x1234";
    },
    (value) => {
      value.status = "complete";
    },
    (value) => {
      value.artifacts.marketplace.abiHash = "0x1234";
    },
    (value) => {
      value.steps[0].transactionInput = "0x6003";
    },
    (value) => {
      value.steps[0].submittedHash = `0x${"6".repeat(64)}`;
    },
    (value) => {
      value.steps[1].purpose = "deploy-something-else";
    },
    (value) => {
      value.steps[0].submittedHash = `0x${"6".repeat(64)}`;
      value.steps[0].submittedAtBlock = "101";
      value.steps[0].receipt = {
        transactionHash: value.steps[0].submittedHash,
        status: "pending",
        blockNumber: "102",
        blockHash: `0x${"8".repeat(64)}`,
        contractAddress: MARKETPLACE,
        gasUsed: "50000",
      };
      value.steps[0].observedResult = { verified: true };
    },
    (value) => {
      value.inputs.checkoutConstructor.values.marketplace = SAFE;
    },
  ];
  for (const mutate of cases) {
    const value = manifest();
    mutate(value);
    assert.throws(() => classifyDeployment(value, observation(0)), DeploymentNoGoError);
  }

  const operationState = prepareLifecycleOperation(manifest(), {
    id: "deployer-activation",
    kind: "deployer-activation",
    authority: "deployer",
    sender: DEPLOYER,
    nonce: "43",
    target: MARKETPLACE,
    transactionInput: "0x01",
    transactionInputHash: keccak256("0x01"),
    expectedResult: { owner: DEPLOYER, paused: false, eventAccount: DEPLOYER },
  });
  operationState.operations[0].executionTransactionHash = `0x${"7".repeat(64)}`;
  assert.throws(() => classifyDeployment(operationState, observation(0)), DeploymentNoGoError);
});

test("same-payload replacements are recorded and changed payloads are rejected", () => {
  const value = recordSubmission(
    manifest(),
    "deploy-marketplace",
    `0x${"6".repeat(64)}`,
    "101",
  );
  const replacement = {
    hash: `0x${"7".repeat(64)}`,
    from: DEPLOYER,
    nonce: "40",
    to: null,
    transactionInputHash: value.steps[0].transactionInputHash,
  };
  const replaced = applyReplacement(value, "deploy-marketplace", replacement, "repriced");

  assert.equal(replaced.steps[0].submittedHash, replacement.hash);
  assert.deepEqual(replaced.steps[0].replacementHistory, [
    {
      previousHash: `0x${"6".repeat(64)}`,
      replacementHash: replacement.hash,
      reason: "repriced",
    },
  ]);

  assert.throws(
    () =>
      applyReplacement(
        value,
        "deploy-marketplace",
        { ...replacement, transactionInputHash: `0x${"8".repeat(64)}` },
        "replaced",
      ),
    DeploymentNoGoError,
  );
  assert.throws(
    () =>
      applyReplacement(
        value,
        "deploy-marketplace",
        { ...replacement, from: "0x9999999999999999999999999999999999999999" },
        "replaced",
      ),
    DeploymentNoGoError,
  );
});

test("manifest persistence is atomic and secret-free", async () => {
  const directory = await mkdtemp(join(tmpdir(), "fame-deployment-manifest-"));
  const path = join(directory, "manifest.json");
  const value = manifest();
  await writeManifestAtomic(path, value);

  const persisted = JSON.parse(await readFile(path, "utf8"));
  assert.deepEqual(persisted, value);
  assert.equal(JSON.stringify(persisted).includes("privateKey"), false);
  assert.equal(JSON.stringify(persisted).includes("rpcUrl"), false);

  value.lastError = {
    name: "HttpRequestError",
    code: "HTTP_503",
    message: "URL: https://rpc.example.invalid/path?api_key=SENTINEL_RPC_CREDENTIAL",
  };
  await assert.rejects(() => writeManifestAtomic(path, value), /secret-bearing manifest value/);
});

test("lifecycle operations pin direct handoff and Safe execution intent", () => {
  const value = manifest();
  const deployerActivation = prepareLifecycleOperation(value, {
    id: "deployer-activation",
    kind: "deployer-activation",
    authority: "deployer",
    sender: DEPLOYER,
    nonce: "43",
    target: MARKETPLACE,
    transactionInput: "0x01",
    transactionInputHash: keccak256("0x01"),
    expectedResult: { owner: DEPLOYER, paused: false, eventAccount: DEPLOYER },
  });
  const handoff = prepareLifecycleOperation(value, {
    id: "ownership-handoff",
    kind: "ownership-handoff",
    authority: "deployer",
    sender: DEPLOYER,
    nonce: "43",
    target: MARKETPLACE,
    transactionInput: "0x02",
    transactionInputHash: keccak256("0x02"),
    expectedResult: { owner: SAFE, paused: true, safeHasCode: true },
  });
  const safeActivation = prepareLifecycleOperation(handoff, {
    id: "safe-activation",
    kind: "safe-activation",
    authority: "society-safe",
    sender: SAFE,
    nonce: null,
    target: MARKETPLACE,
    transactionInput: "0x03",
    transactionInputHash: keccak256("0x03"),
    expectedResult: { owner: SAFE, paused: false, eventAccount: SAFE },
  });

  assert.equal(safeActivation.operations[0].expectedResult.owner, SAFE);
  assert.equal(safeActivation.operations[1].authority, "society-safe");
  assert.equal(safeActivation.operations[1].submittedHash, null);
  assert.equal(deployerActivation.operations[0].expectedResult.eventAccount, DEPLOYER);

  assert.throws(
    () =>
      prepareLifecycleOperation(value, {
        id: "unsafe-handoff",
        kind: "ownership-handoff",
        authority: "deployer",
        sender: DEPLOYER,
        nonce: "43",
        target: MARKETPLACE,
        transactionInput: "0x04",
        transactionInputHash: keccak256("0x04"),
        expectedResult: { owner: CHECKOUT, paused: false, safeHasCode: false },
      }),
    DeploymentNoGoError,
  );
  assert.throws(
    () =>
      prepareLifecycleOperation(value, {
        id: "unsafe-safe-activation",
        kind: "safe-activation",
        authority: "deployer",
        sender: DEPLOYER,
        nonce: "43",
        target: MARKETPLACE,
        transactionInput: "0x05",
        transactionInputHash: keccak256("0x05"),
        expectedResult: { owner: SAFE, paused: false, eventAccount: DEPLOYER },
      }),
    DeploymentNoGoError,
  );
});

test("only viem not-found lookup errors are suppressible", () => {
  assert.equal(isReceiptLookupMiss(new TransactionReceiptNotFoundError({ hash: `0x${"1".repeat(64)}` })), true);
  assert.equal(isReceiptLookupMiss(new Error("RPC transport failed")), false);
  assert.equal(isTransactionLookupMiss(new TransactionNotFoundError({ hash: `0x${"2".repeat(64)}` })), true);
  assert.equal(isTransactionLookupMiss(new Error("malformed RPC response")), false);
});

test("direct lifecycle canonical recovery records exact replacements and rejects conflicts", () => {
  let value = prepareLifecycleOperation(deployedManifest(), {
    id: "deployer-activation",
    kind: "deployer-activation",
    authority: "deployer",
    sender: DEPLOYER,
    nonce: "43",
    target: MARKETPLACE,
    transactionInput: "0x01",
    transactionInputHash: keccak256("0x01"),
    expectedResult: { owner: DEPLOYER, paused: false, eventAccount: DEPLOYER },
  });
  value.operations[0].submittedHash = `0x${"6".repeat(64)}`;
  value.operations[0].submittedAtBlock = "101";
  const observation = {
    transaction: {
      hash: `0x${"7".repeat(64)}`,
      from: DEPLOYER,
      nonce: "43",
      to: MARKETPLACE,
      transactionInputHash: value.operations[0].transactionInputHash,
    },
    receipt: {
      transactionHash: `0x${"7".repeat(64)}`,
      status: "success",
      blockNumber: "102",
      blockHash: `0x${"8".repeat(64)}`,
      contractAddress: null,
      gasUsed: "50000",
    },
  };
  const recovered = recordCanonicalOperation(
    value,
    "deployer-activation",
    observation,
    { verified: true, verifiedAtBlock: "102", checks: { owner: DEPLOYER, paused: false } },
  );

  assert.equal(recovered.operations[0].submittedHash, observation.transaction.hash);
  assert.equal(recovered.operations[0].executionTransactionHash, observation.transaction.hash);
  assert.equal(recovered.operations[0].replacementHistory.length, 1);
  assert.throws(
    () =>
      recordCanonicalOperation(
        value,
        "deployer-activation",
        { ...observation, transaction: { ...observation.transaction, from: SAFE } },
        { verified: true },
      ),
    DeploymentNoGoError,
  );
  const failed = recordCanonicalOperationFailure(
    value,
    "deployer-activation",
    { ...observation, transaction: { ...observation.transaction, from: SAFE } },
    null,
    "sender mismatch for deployer-activation",
  );
  assert.equal(failed.status, "needs-reconciliation");
  assert.equal(failed.operations[0].canonicalObservation.executionTransactionHash, observation.transaction.hash);
  assert.match(failed.operations[0].canonicalObservation.error, /sender mismatch/);
});

test("Safe canonical recovery requires and preserves a bytes32 Safe transaction hash", () => {
  const value = prepareLifecycleOperation(deployedManifest(), {
    id: "safe-activation",
    kind: "safe-activation",
    authority: "society-safe",
    sender: SAFE,
    nonce: null,
    target: MARKETPLACE,
    transactionInput: "0x03",
    transactionInputHash: keccak256("0x03"),
    expectedResult: { owner: SAFE, paused: false, eventAccount: SAFE },
  });
  const executionHash = `0x${"7".repeat(64)}`;
  const observation = {
    transaction: {
      hash: executionHash,
      from: SAFE,
      nonce: "88",
      to: SAFE,
      transactionInputHash: `0x${"3".repeat(64)}`,
    },
    receipt: {
      transactionHash: executionHash,
      status: "success",
      blockNumber: "102",
      blockHash: `0x${"8".repeat(64)}`,
      contractAddress: null,
      gasUsed: "50000",
    },
  };
  assert.throws(
    () => recordCanonicalOperation(value, "safe-activation", observation, { verified: true }),
    DeploymentNoGoError,
  );
  assert.throws(
    () => recordCanonicalOperation(value, "safe-activation", observation, { verified: true }, "0x1234"),
    DeploymentNoGoError,
  );
  assert.throws(
    () =>
      recordCanonicalOperation(
        value,
        "safe-activation",
        { ...observation, transaction: { ...observation.transaction, to: MARKETPLACE } },
        { verified: true },
        {
          eventName: "ExecutionSuccess",
          reviewedHash: `0x${"a".repeat(64)}`,
          emittedHash: `0x${"a".repeat(64)}`,
        },
      ),
    (error) => error instanceof DeploymentNoGoError && /Society Safe/.test(error.message),
  );

  const safeTransactionHash = `0x${"a".repeat(64)}`;
  assert.throws(
    () =>
      recordCanonicalOperation(value, "safe-activation", observation, { verified: true }, {
        eventName: "ExecutionSuccess",
        reviewedHash: safeTransactionHash,
        emittedHash: `0x${"b".repeat(64)}`,
      }),
    /reviewed Safe transaction hash mismatch/,
  );
  assert.throws(
    () =>
      recordCanonicalOperation(value, "safe-activation", observation, { verified: true }, {
        eventName: "ExecutionFailure",
        reviewedHash: safeTransactionHash,
        emittedHash: safeTransactionHash,
      }),
    /ExecutionSuccess/,
  );
  const recovered = recordCanonicalOperation(
    value,
    "safe-activation",
    observation,
    { verified: true, verifiedAtBlock: "102", checks: { owner: SAFE, paused: false } },
    {
      eventName: "ExecutionSuccess",
      reviewedHash: safeTransactionHash,
      emittedHash: safeTransactionHash,
    },
  );
  assert.equal(recovered.operations[0].safeTransactionHash, safeTransactionHash);
  assert.equal(recovered.operations[0].executionTransactionHash, executionHash);
});
