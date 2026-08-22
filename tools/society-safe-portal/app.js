import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeEventLog,
  decodeFunctionResult,
  formatEther,
  getAddress,
  keccak256,
} from "viem";
import { base, mainnet, polygon } from "viem/chains";

import proxyCreationCodeFixture from "./proxy-creation-code-v1.5.0.txt";
import {
  FACTORY_ABI,
  SAFE_ABI,
  assertManifest,
  buildBootstrap,
  classifySafeState,
  deriveDeployment,
  validateDeploymentEvents,
} from "./core.mjs";
import { SAFE_MANIFEST, ZERO_ADDRESS } from "./manifest.mjs";
import {
  readSafeSnapshot,
  resolveSafeSnapshot,
  runtimeHash,
} from "./safe-state.mjs";

const EVIDENCE_KEY = "society-safe-deployment-evidence:v2";
const CHAIN_DEFINITIONS = new Map([
  [base.id, base],
  [polygon.id, polygon],
  [mainnet.id, mainnet],
]);

assertManifest();

const fixtureDeployment = deriveDeployment(proxyCreationCodeFixture.trim());
const bootstrap = buildBootstrap();

if (
  fixtureDeployment.predictedAddress !== SAFE_MANIFEST.safe.predictedAddress
) {
  throw new Error(
    "bundled deployment fixture does not reproduce the approved Safe address",
  );
}
if (
  fixtureDeployment.proxyCreationCodeHash !==
  SAFE_MANIFEST.safe.proxyCreationCodeHash
) {
  throw new Error(
    "bundled proxy creation code does not match the approved manifest",
  );
}

const state = {
  rabbyProvider: null,
  rabbyAnnounceInfo: null,
  account: null,
  chainId: null,
  chain: null,
  publicClient: null,
  walletClient: null,
  preflight: null,
  busy: false,
  refreshSequence: 0,
  evidence: loadEvidence(),
};

function element(id) {
  const value = document.getElementById(id);
  if (!value) throw new Error(`missing portal element: ${id}`);
  return value;
}

function sameAddress(left, right) {
  return typeof left === "string" && typeof right === "string"
    ? left.toLowerCase() === right.toLowerCase()
    : false;
}

function shortAddress(address) {
  return address ? `${address.slice(0, 8)}…${address.slice(-6)}` : "—";
}

function shortHash(hash) {
  return hash ? `${hash.slice(0, 10)}…${hash.slice(-8)}` : "—";
}

function displayActual(value) {
  if (Array.isArray(value))
    return value.length === 0 ? "none" : `${value.length} entries`;
  if (typeof value === "bigint") return value.toString();
  if (
    typeof value === "string" &&
    value.startsWith("0x") &&
    value.length > 20
  ) {
    return shortHash(value);
  }
  return String(value ?? "—");
}

function errorMessage(error) {
  if (error && typeof error === "object") {
    if ("shortMessage" in error && typeof error.shortMessage === "string")
      return error.shortMessage;
    if ("message" in error && typeof error.message === "string")
      return error.message.split("\n")[0];
  }
  return String(error);
}

function jsonReplacer(_key, value) {
  return typeof value === "bigint" ? value.toString() : value;
}

function loadEvidence() {
  try {
    const saved = localStorage.getItem(EVIDENCE_KEY);
    return saved ? JSON.parse(saved) : { schemaVersion: 2, chains: {} };
  } catch {
    return { schemaVersion: 2, chains: {} };
  }
}

function saveEvidence() {
  localStorage.setItem(
    EVIDENCE_KEY,
    JSON.stringify(state.evidence, jsonReplacer),
  );
  updateEvidenceButton();
  renderChainRail();
}

function chainEvidence(chainId) {
  const key = String(chainId);
  state.evidence.chains[key] ??= {};
  return state.evidence.chains[key];
}

function setAlert(message, tone = "warning") {
  const alert = element("portal-alert");
  alert.textContent = message;
  alert.dataset.tone = tone;
}

function setStageStatus(id, label, tone = "") {
  const status = element(id);
  status.textContent = label;
  status.dataset.tone = tone;
}

function setText(id, value) {
  element(id).textContent = value;
}

function currentChainManifest() {
  return state.chainId ? SAFE_MANIFEST.chains[state.chainId] : null;
}

function confirmationPhrase(kind) {
  const chain = currentChainManifest();
  if (!chain) return "";
  return kind === "deployment"
    ? `DEPLOY ${chain.shortName.toUpperCase()} ${SAFE_MANIFEST.safe.predictedAddress.slice(-8)}`
    : `SET 7 OF 15 ${chain.shortName.toUpperCase()}`;
}

function renderStaticManifest() {
  setText("hero-address", SAFE_MANIFEST.safe.predictedAddress);
  setText("manifest-factory", shortAddress(SAFE_MANIFEST.safe.factory));
  setText("manifest-singleton", shortAddress(SAFE_MANIFEST.safe.singleton));
  setText(
    "manifest-initializer-hash",
    shortHash(fixtureDeployment.initializerHash),
  );
  setText("manifest-bootstrap-hash", shortHash(bootstrap.transactionDataHash));
}

function renderChainRail() {
  const rail = element("chain-rail");
  rail.replaceChildren();
  SAFE_MANIFEST.deploymentOrder.forEach((chainId, index) => {
    const chain = SAFE_MANIFEST.chains[chainId];
    const evidence = state.evidence.chains[String(chainId)] ?? {};
    const item = document.createElement("li");
    item.className = "chain-step";
    item.dataset.state = evidence.completedAt
      ? "complete"
      : state.chainId === chainId
        ? "active"
        : "pending";

    const marker = document.createElement("span");
    marker.className = "chain-step-marker chain-step-index";
    marker.textContent = evidence.completedAt
      ? "✓"
      : String(index + 1).padStart(2, "0");

    const copy = document.createElement("div");
    copy.className = "chain-step-copy";
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = chain.shortName;
    button.disabled = !state.rabbyProvider || !state.account || state.busy;
    button.addEventListener("click", () => switchChain(chainId));
    const status = document.createElement("p");
    status.textContent = evidence.completedAt
      ? "7-of-15 verified"
      : state.chainId === chainId
        ? "Active in Rabby"
        : "Awaiting verification";
    copy.append(button, status);
    item.append(marker, copy);
    rail.append(item);
  });
}

function renderWallet() {
  const connect = element("connect-wallet");
  const identity = element("wallet-identity");
  const hasRabby = Boolean(state.rabbyProvider);
  connect.disabled = !hasRabby || state.busy;
  connect.textContent = state.account ? "Reconnect Rabby" : "Connect Rabby";

  if (!hasRabby) {
    setText("wallet-status", "Rabby was not detected in this browser.");
  } else if (!state.account) {
    setText(
      "wallet-status",
      "Rabby detected. Connection requires an explicit wallet prompt.",
    );
  } else if (!sameAddress(state.account, SAFE_MANIFEST.deployer)) {
    setText(
      "wallet-status",
      "Wrong Rabby account. Switch to the approved deployer.",
    );
  } else {
    setText("wallet-status", "Approved deployer connected through Rabby.");
  }

  identity.hidden = !state.account;
  if (state.account) {
    setText("wallet-account", shortAddress(state.account));
    setText(
      "wallet-chain",
      currentChainManifest()?.name ??
        (state.chainId
          ? `Unsupported chain ${state.chainId}`
          : "Chain unknown"),
    );
  }
}

function renderChecks(checks) {
  const list = element("preflight-list");
  list.replaceChildren();
  checks.forEach((item, index) => {
    const row = document.createElement("li");
    row.className = "check-item";
    row.dataset.pass = String(item.pass);
    row.style.animationDelay = `${Math.min(index * 28, 280)}ms`;
    const symbol = document.createElement("span");
    symbol.className = "check-symbol";
    symbol.textContent = item.pass ? "✓" : "×";
    const label = document.createElement("span");
    label.textContent = item.label;
    const actual = document.createElement("span");
    actual.className = "check-value";
    actual.textContent = displayActual(item.actual);
    actual.title = String(item.actual ?? "");
    row.append(symbol, label, actual);
    list.append(row);
  });
}

function renderTransactionEvidence() {
  if (!state.chainId) return;
  const evidence = state.evidence.chains[String(state.chainId)] ?? {};
  setText("deployment-tx", shortHash(evidence.deployment?.transactionHash));
  setText("bootstrap-tx", shortHash(evidence.bootstrap?.transactionHash));
}

function updateEvidenceButton() {
  const hasEvidence = Object.values(state.evidence.chains).some(
    (entry) => entry.deployment || entry.bootstrap || entry.completedAt,
  );
  element("download-evidence").disabled = !hasEvidence;
}

function renderActionAvailability() {
  const deploymentInput = element("deployment-confirmation");
  const bootstrapInput = element("bootstrap-confirmation");
  const deploymentButton = element("broadcast-deployment");
  const bootstrapButton = element("broadcast-bootstrap");
  const phase = state.preflight?.safeState.phase;
  const ready = Boolean(state.preflight?.ready) && !state.busy;

  const deploymentPhrase = confirmationPhrase("deployment");
  const bootstrapPhrase = confirmationPhrase("bootstrap");
  setText("deployment-phrase", deploymentPhrase || "the confirmation phrase");
  setText("bootstrap-phrase", bootstrapPhrase || "the confirmation phrase");

  deploymentInput.disabled = !(ready && phase === "empty");
  bootstrapInput.disabled = !(ready && phase === "bootstrap-ready");
  deploymentButton.disabled =
    deploymentInput.disabled ||
    deploymentInput.value.trim() !== deploymentPhrase;
  bootstrapButton.disabled =
    bootstrapInput.disabled || bootstrapInput.value.trim() !== bootstrapPhrase;

  if (phase === "empty") {
    setStageStatus("deployment-status", "Ready", "ready");
    setStageStatus("bootstrap-status", "Locked");
  } else if (phase === "bootstrap-ready") {
    setStageStatus("deployment-status", "Verified", "ready");
    setStageStatus("bootstrap-status", "Ready", "ready");
  } else if (phase === "complete") {
    setStageStatus("deployment-status", "Complete", "ready");
    setStageStatus("bootstrap-status", "Complete", "ready");
  } else if (phase === "invalid") {
    setStageStatus("deployment-status", "Hard stop", "danger");
    setStageStatus("bootstrap-status", "Hard stop", "danger");
  } else {
    setStageStatus("deployment-status", "Waiting");
    setStageStatus("bootstrap-status", "Locked");
  }
}

function renderPortal() {
  renderWallet();
  renderChainRail();
  renderTransactionEvidence();
  updateEvidenceButton();
  element("refresh-state").disabled =
    !state.publicClient ||
    !sameAddress(state.account, SAFE_MANIFEST.deployer) ||
    state.busy;

  if (!state.preflight) {
    setText("preflight-summary", state.busy ? "Working…" : "Not started");
    setText(
      "active-chain-title",
      currentChainManifest()?.name ?? "Connect Rabby to begin",
    );
    renderChecks([]);
    setText("deployment-gas", "—");
    setText("bootstrap-gas", "—");
  } else {
    const chain = currentChainManifest();
    setText(
      "active-chain-title",
      `${chain.name} · ${state.preflight.safeState.phase}`,
    );
    const passed = state.preflight.checks.filter((item) => item.pass).length;
    setText(
      "preflight-summary",
      `${passed} / ${state.preflight.checks.length} checks passed`,
    );
    renderChecks(state.preflight.checks);
    setText(
      "deployment-gas",
      state.preflight.deploymentGas
        ? state.preflight.deploymentGas.toLocaleString()
        : "—",
    );
    setText(
      "bootstrap-gas",
      state.preflight.bootstrapGas
        ? state.preflight.bootstrapGas.toLocaleString()
        : "—",
    );
  }
  renderActionAvailability();
}

function makeCheck(label, expected, actual, pass) {
  return { label, expected, actual, pass };
}

async function refreshLiveState({ quiet = false } = {}) {
  if (!state.publicClient || !state.account || !state.chainId) return;
  if (!sameAddress(state.account, SAFE_MANIFEST.deployer)) {
    state.preflight = null;
    setAlert(
      "Hard stop: Rabby is not connected to the approved deployer account.",
      "danger",
    );
    renderPortal();
    return;
  }

  const sequence = ++state.refreshSequence;
  if (!quiet) {
    setAlert(
      "Reading current chain state through Rabby. No transaction is being requested.",
    );
  }
  state.preflight = null;
  renderPortal();

  try {
    const client = state.publicClient;
    const manifest = SAFE_MANIFEST;
    const [
      factoryCode,
      singletonCode,
      handlerCode,
      multiSendCode,
      balance,
      liveProxyCode,
      safeCode,
    ] = await Promise.all([
      client.getBytecode({ address: manifest.safe.factory }),
      client.getBytecode({ address: manifest.safe.singleton }),
      client.getBytecode({ address: manifest.safe.fallbackHandler }),
      client.getBytecode({ address: manifest.safe.multiSendCallOnly }),
      client.getBalance({ address: state.account }),
      client.readContract({
        address: manifest.safe.factory,
        abi: FACTORY_ABI,
        functionName: "proxyCreationCode",
      }),
      client.getBytecode({ address: manifest.safe.predictedAddress }),
    ]);
    if (sequence !== state.refreshSequence) return;

    const deployment = deriveDeployment(liveProxyCode);
    const liveChainId = await client.getChainId();
    const checks = [
      makeCheck(
        "Approved deployer",
        manifest.deployer,
        state.account,
        sameAddress(state.account, manifest.deployer),
      ),
      makeCheck(
        "Chain ID",
        String(state.chainId),
        liveChainId,
        liveChainId === state.chainId,
      ),
      makeCheck(
        "Factory bytecode",
        manifest.safe.factoryCodeHash,
        runtimeHash(factoryCode),
        runtimeHash(factoryCode) === manifest.safe.factoryCodeHash,
      ),
      makeCheck(
        "Singleton bytecode",
        manifest.safe.singletonCodeHash,
        runtimeHash(singletonCode),
        runtimeHash(singletonCode) === manifest.safe.singletonCodeHash,
      ),
      makeCheck(
        "Fallback handler bytecode",
        manifest.safe.fallbackHandlerCodeHash,
        runtimeHash(handlerCode),
        runtimeHash(handlerCode) === manifest.safe.fallbackHandlerCodeHash,
      ),
      makeCheck(
        "MultiSendCallOnly bytecode",
        manifest.safe.multiSendCallOnlyCodeHash,
        runtimeHash(multiSendCode),
        runtimeHash(multiSendCode) === manifest.safe.multiSendCallOnlyCodeHash,
      ),
      makeCheck(
        "Proxy creation code",
        manifest.safe.proxyCreationCodeHash,
        deployment.proxyCreationCodeHash,
        deployment.proxyCreationCodeHash ===
          manifest.safe.proxyCreationCodeHash,
      ),
      makeCheck(
        "Predicted address",
        manifest.safe.predictedAddress,
        deployment.predictedAddress,
        sameAddress(
          deployment.predictedAddress,
          manifest.safe.predictedAddress,
        ),
      ),
    ];

    const safeSnapshot = await resolveSafeSnapshot(safeCode, (code) =>
      readSafeSnapshot(client, code),
    );
    const safeState = classifySafeState(safeSnapshot);
    let deploymentGas = null;
    let bootstrapGas = null;

    if (!safeCode || safeCode === "0x") {
      const simulation = await client.call({
        account: state.account,
        to: manifest.safe.factory,
        data: deployment.transactionData,
      });
      const simulatedAddress = decodeFunctionResult({
        abi: FACTORY_ABI,
        functionName: manifest.safe.creationMethod,
        data: simulation.data,
      });
      deploymentGas = await client.estimateGas({
        account: state.account,
        to: manifest.safe.factory,
        data: deployment.transactionData,
      });
      const gasPrice = await client.getGasPrice();
      const deploymentCost = deploymentGas * gasPrice;
      checks.push(
        makeCheck("Destination vacancy", "no code", "no code", true),
        makeCheck(
          "Deployment simulation",
          manifest.safe.predictedAddress,
          simulatedAddress,
          sameAddress(simulatedAddress, manifest.safe.predictedAddress),
        ),
        makeCheck(
          "Deployer balance",
          `more than 2× estimated deployment cost`,
          `${formatEther(balance)} ${manifest.chains[state.chainId].nativeCurrency}`,
          balance > deploymentCost * 2n,
        ),
      );
    } else {
      checks.push(...safeState.checks);
      if (safeState.phase === "bootstrap-ready") {
        const simulation = await client.call({
          account: state.account,
          to: manifest.safe.predictedAddress,
          data: bootstrap.transactionData,
        });
        const simulatedSuccess = decodeFunctionResult({
          abi: SAFE_ABI,
          functionName: "execTransaction",
          data: simulation.data,
        });
        bootstrapGas = await client.estimateGas({
          account: state.account,
          to: manifest.safe.predictedAddress,
          data: bootstrap.transactionData,
        });
        const gasPrice = await client.getGasPrice();
        checks.push(
          makeCheck(
            "Bootstrap simulation",
            "success",
            simulatedSuccess ? "success" : "failure",
            simulatedSuccess,
          ),
          makeCheck(
            "Deployer balance",
            "more than 2× estimated bootstrap cost",
            `${formatEther(balance)} ${manifest.chains[state.chainId].nativeCurrency}`,
            balance > bootstrapGas * gasPrice * 2n,
          ),
        );
      }
    }

    const ready =
      checks.every((item) => item.pass) && safeState.phase !== "invalid";
    state.preflight = {
      chainId: state.chainId,
      checkedAt: new Date().toISOString(),
      deployment,
      safeSnapshot,
      safeState,
      checks,
      deploymentGas,
      bootstrapGas,
      ready,
    };

    if (safeState.phase === "empty" && ready) {
      setAlert(
        "Preflight passed. Review the manifest, type the deployment phrase, then confirm in Rabby.",
        "success",
      );
    } else if (safeState.phase === "bootstrap-ready" && ready) {
      setAlert(
        "Deployment verified. The empty Safe is ready for its atomic 7-of-15 bootstrap.",
        "success",
      );
    } else if (safeState.phase === "complete" && ready) {
      setAlert(
        "This chain is complete: exact owner order, threshold 7, nonce 1, and deployer removed.",
        "success",
      );
      recordCompletion(state.preflight);
    } else {
      setAlert(
        "Hard stop: one or more live checks do not match the approved manifest.",
        "danger",
      );
    }
    renderPortal();
  } catch (error) {
    if (sequence !== state.refreshSequence) return;
    state.preflight = null;
    setAlert(`Preflight failed: ${errorMessage(error)}`, "danger");
    renderPortal();
  }
}

function recordCompletion(preflight) {
  if (!state.chainId || preflight.safeState.phase !== "complete") return;
  recordCompletionForChain(
    state.chainId,
    preflight.safeSnapshot,
    preflight.checkedAt,
  );
}

function recordCompletionForChain(chainId, snapshot, checkedAt) {
  const evidence = chainEvidence(chainId);
  evidence.completedAt ??= new Date().toISOString();
  evidence.finalState = {
    checkedAt,
    safe: SAFE_MANIFEST.safe.predictedAddress,
    owners: snapshot.owners,
    threshold: snapshot.threshold,
    nonce: snapshot.nonce,
    singleton: snapshot.singleton,
    fallbackHandler: snapshot.fallbackHandler,
    guard: snapshot.guard,
    modules: snapshot.modules,
  };
  saveEvidence();
}

async function connectRabby() {
  if (!state.rabbyProvider || state.busy) return;
  try {
    const accounts = await state.rabbyProvider.request({
      method: "eth_requestAccounts",
    });
    state.account = accounts?.[0] ? getAddress(accounts[0]) : null;
    const chainHex = await state.rabbyProvider.request({
      method: "eth_chainId",
    });
    state.chainId = Number(BigInt(chainHex));
    configureClients();
    renderPortal();
    if (!sameAddress(state.account, SAFE_MANIFEST.deployer)) {
      setAlert(
        `Hard stop: connected account ${shortAddress(state.account)} is not the approved deployer ${shortAddress(SAFE_MANIFEST.deployer)}.`,
        "danger",
      );
      renderPortal();
      return;
    }
    if (!CHAIN_DEFINITIONS.has(state.chainId)) {
      setAlert("Switch Rabby to Base, Polygon, or Ethereum.", "danger");
      renderPortal();
      return;
    }
    await refreshLiveState();
  } catch (error) {
    setAlert(`Rabby connection failed: ${errorMessage(error)}`, "danger");
    renderPortal();
  }
}

function configureClients() {
  state.chain = CHAIN_DEFINITIONS.get(state.chainId) ?? null;
  if (!state.rabbyProvider || !state.chain || !state.account) {
    state.publicClient = null;
    state.walletClient = null;
    return;
  }
  state.publicClient = createPublicClient({
    chain: state.chain,
    transport: custom(state.rabbyProvider, { retryCount: 2 }),
  });
  state.walletClient = createWalletClient({
    account: state.account,
    chain: state.chain,
    transport: custom(state.rabbyProvider, { retryCount: 0 }),
  });
}

async function switchChain(chainId) {
  if (!state.rabbyProvider || state.busy) return;
  try {
    await state.rabbyProvider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: SAFE_MANIFEST.chains[chainId].hexId }],
    });
    const chainHex = await state.rabbyProvider.request({
      method: "eth_chainId",
    });
    state.chainId = Number(BigInt(chainHex));
    state.preflight = null;
    configureClients();
    renderPortal();
    await refreshLiveState();
  } catch (error) {
    setAlert(`Chain switch failed: ${errorMessage(error)}`, "danger");
  }
}

function assertTransaction(transaction, { from, to, data }) {
  if (!sameAddress(transaction.from, from))
    throw new Error("receipt transaction sender mismatch");
  if (!sameAddress(transaction.to, to))
    throw new Error("receipt transaction target mismatch");
  if (transaction.input.toLowerCase() !== data.toLowerCase()) {
    throw new Error("receipt transaction calldata mismatch");
  }
  if (transaction.value !== 0n)
    throw new Error("receipt transaction value is not zero");
}

function requireExecutionSuccess(receipt) {
  for (const log of receipt.logs) {
    if (!sameAddress(log.address, SAFE_MANIFEST.safe.predictedAddress))
      continue;
    try {
      const decoded = decodeEventLog({
        abi: SAFE_ABI,
        data: log.data,
        topics: log.topics,
      });
      if (decoded.eventName === "ExecutionFailure") {
        throw new Error("Safe emitted ExecutionFailure");
      }
      if (decoded.eventName === "ExecutionSuccess") return decoded;
    } catch (error) {
      if (errorMessage(error).includes("ExecutionFailure")) throw error;
    }
  }
  throw new Error("receipt does not contain Safe ExecutionSuccess");
}

function captureExecutionContext() {
  const { account, chain, chainId, publicClient, walletClient } = state;
  if (!account || !chain || !chainId || !publicClient || !walletClient) {
    throw new Error("Rabby execution context is incomplete");
  }
  if (!sameAddress(account, SAFE_MANIFEST.deployer)) {
    throw new Error("Rabby is not connected to the approved deployer");
  }
  return { account, chain, chainId, publicClient, walletClient };
}

async function broadcastDeployment() {
  const expectedPhrase = confirmationPhrase("deployment");
  if (element("deployment-confirmation").value.trim() !== expectedPhrase)
    return;
  await withBroadcastLock(async () => {
    await refreshLiveState({ quiet: true });
    if (
      !state.preflight?.ready ||
      state.preflight.safeState.phase !== "empty"
    ) {
      throw new Error("deployment preflight is no longer valid");
    }
    const { account, chain, chainId, publicClient, walletClient } =
      captureExecutionContext();
    const transactionData = state.preflight.deployment.transactionData;
    setAlert(
      "Rabby is preparing the deployment request. Verify the target and predicted address in the wallet.",
    );
    const hash = await walletClient.sendTransaction({
      account,
      chain,
      to: SAFE_MANIFEST.safe.factory,
      data: transactionData,
      value: 0n,
    });
    const evidence = chainEvidence(chainId);
    evidence.deployment = {
      transactionHash: hash,
      submittedAt: new Date().toISOString(),
      transactionDataHash: keccak256(transactionData),
      status: "submitted",
    };
    saveEvidence();
    setText("deployment-tx", shortHash(hash));
    setAlert(
      `Deployment submitted: ${shortHash(hash)}. Waiting for its receipt.`,
    );

    const receipt = await publicClient.waitForTransactionReceipt({
      hash,
      confirmations: 1,
    });
    if (receipt.status !== "success")
      throw new Error("deployment receipt status is not success");
    const transaction = await publicClient.getTransaction({ hash });
    assertTransaction(transaction, {
      from: SAFE_MANIFEST.deployer,
      to: SAFE_MANIFEST.safe.factory,
      data: transactionData,
    });
    validateDeploymentEvents(receipt.logs, state.preflight.deployment);
    evidence.deployment = {
      ...evidence.deployment,
      status: "verified",
      blockNumber: receipt.blockNumber,
      blockHash: receipt.blockHash,
      gasUsed: receipt.gasUsed,
      verifiedAt: new Date().toISOString(),
    };
    saveEvidence();
    element("deployment-confirmation").value = "";
    const deployedCode = await publicClient.getBytecode({
      address: SAFE_MANIFEST.safe.predictedAddress,
    });
    const snapshot = await readSafeSnapshot(publicClient, deployedCode ?? "0x");
    if (classifySafeState(snapshot).phase !== "bootstrap-ready") {
      throw new Error(
        "deployed Safe did not reach the exact deployer-only bootstrap state",
      );
    }
    if (state.chainId === chainId && sameAddress(state.account, account)) {
      await refreshLiveState({ quiet: true });
    }
    setAlert(
      "Deployment receipt verified. Review and confirm the separate bootstrap transaction.",
      "success",
    );
  });
}

async function broadcastBootstrap() {
  const expectedPhrase = confirmationPhrase("bootstrap");
  if (element("bootstrap-confirmation").value.trim() !== expectedPhrase) return;
  await withBroadcastLock(async () => {
    await refreshLiveState({ quiet: true });
    if (
      !state.preflight?.ready ||
      state.preflight.safeState.phase !== "bootstrap-ready"
    ) {
      throw new Error("bootstrap preflight is no longer valid");
    }
    const { account, chain, chainId, publicClient, walletClient } =
      captureExecutionContext();
    const transactionData = bootstrap.transactionData;
    setAlert(
      "Rabby is preparing the atomic 7-of-15 bootstrap. Verify the new Safe target in the wallet.",
    );
    const hash = await walletClient.sendTransaction({
      account,
      chain,
      to: SAFE_MANIFEST.safe.predictedAddress,
      data: transactionData,
      value: 0n,
    });
    const evidence = chainEvidence(chainId);
    evidence.bootstrap = {
      transactionHash: hash,
      submittedAt: new Date().toISOString(),
      transactionDataHash: keccak256(transactionData),
      status: "submitted",
    };
    saveEvidence();
    setText("bootstrap-tx", shortHash(hash));
    setAlert(
      `Bootstrap submitted: ${shortHash(hash)}. Waiting for its receipt.`,
    );

    const receipt = await publicClient.waitForTransactionReceipt({
      hash,
      confirmations: 1,
    });
    if (receipt.status !== "success")
      throw new Error("bootstrap receipt status is not success");
    const transaction = await publicClient.getTransaction({ hash });
    assertTransaction(transaction, {
      from: SAFE_MANIFEST.deployer,
      to: SAFE_MANIFEST.safe.predictedAddress,
      data: transactionData,
    });
    requireExecutionSuccess(receipt);
    evidence.bootstrap = {
      ...evidence.bootstrap,
      status: "verified",
      blockNumber: receipt.blockNumber,
      blockHash: receipt.blockHash,
      gasUsed: receipt.gasUsed,
      verifiedAt: new Date().toISOString(),
    };
    saveEvidence();
    element("bootstrap-confirmation").value = "";
    const finalCode = await publicClient.getBytecode({
      address: SAFE_MANIFEST.safe.predictedAddress,
    });
    const finalSnapshot = await readSafeSnapshot(
      publicClient,
      finalCode ?? "0x",
    );
    if (classifySafeState(finalSnapshot).phase !== "complete") {
      throw new Error("Safe did not reach the approved 7-of-15 terminal state");
    }
    recordCompletionForChain(chainId, finalSnapshot, new Date().toISOString());
    if (state.chainId === chainId && sameAddress(state.account, account)) {
      await refreshLiveState({ quiet: true });
    }
    setAlert(
      "Chain complete. Download the evidence or continue to the next chain.",
      "success",
    );
  });
}

async function withBroadcastLock(operation) {
  if (state.busy) return;
  state.busy = true;
  renderPortal();
  try {
    await operation();
  } catch (error) {
    setAlert(`Operation stopped: ${errorMessage(error)}`, "danger");
  } finally {
    state.busy = false;
    renderPortal();
  }
}

function downloadEvidence() {
  const exportValue = {
    schemaVersion: 2,
    kind: SAFE_MANIFEST.kind,
    exportedAt: new Date().toISOString(),
    manifest: {
      safeRelease: SAFE_MANIFEST.safe.release,
      creationMethod: SAFE_MANIFEST.safe.creationMethod,
      deployer: SAFE_MANIFEST.deployer,
      factory: SAFE_MANIFEST.safe.factory,
      singleton: SAFE_MANIFEST.safe.singleton,
      fallbackHandler: SAFE_MANIFEST.safe.fallbackHandler,
      multiSendCallOnly: SAFE_MANIFEST.safe.multiSendCallOnly,
      saltNonce: SAFE_MANIFEST.safe.saltNonce,
      predictedSafeAddress: SAFE_MANIFEST.safe.predictedAddress,
      finalOwners: SAFE_MANIFEST.finalOwners,
      finalThreshold: SAFE_MANIFEST.finalThreshold,
      initializerHash: fixtureDeployment.initializerHash,
      deploymentTransactionDataHash: fixtureDeployment.transactionDataHash,
      bootstrapTransactionDataHash: bootstrap.transactionDataHash,
    },
    evidence: state.evidence,
  };
  const blob = new Blob([`${JSON.stringify(exportValue, jsonReplacer, 2)}\n`], {
    type: "application/json",
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `society-safe-deployment-evidence-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  URL.revokeObjectURL(url);
}

function registerRabbyProvider(detail) {
  const isRabby =
    detail?.info?.rdns === "io.rabby" ||
    detail?.info?.name?.toLowerCase().includes("rabby") ||
    detail?.provider?.isRabby === true;
  if (!isRabby || state.rabbyProvider) return;
  state.rabbyProvider = detail.provider;
  state.rabbyAnnounceInfo = {
    name: detail.info?.name ?? "Rabby",
    rdns: detail.info?.rdns ?? "io.rabby",
    uuid: detail.info?.uuid ?? null,
  };
  state.rabbyProvider.on?.("accountsChanged", handleAccountsChanged);
  state.rabbyProvider.on?.("chainChanged", handleChainChanged);
  renderPortal();
}

async function handleAccountsChanged(accounts) {
  state.account = accounts?.[0] ? getAddress(accounts[0]) : null;
  state.preflight = null;
  configureClients();
  renderPortal();
  if (state.account && sameAddress(state.account, SAFE_MANIFEST.deployer)) {
    await refreshLiveState();
  } else if (state.account) {
    setAlert(
      "Hard stop: Rabby changed to an account that is not the approved deployer.",
      "danger",
    );
  }
}

async function handleChainChanged(chainHex) {
  state.chainId = Number(BigInt(chainHex));
  state.preflight = null;
  configureClients();
  renderPortal();
  if (
    state.publicClient &&
    sameAddress(state.account, SAFE_MANIFEST.deployer)
  ) {
    await refreshLiveState();
  }
}

function discoverRabby() {
  window.addEventListener("eip6963:announceProvider", (event) =>
    registerRabbyProvider(event.detail),
  );
  window.dispatchEvent(new Event("eip6963:requestProvider"));
  window.setTimeout(() => {
    if (!state.rabbyProvider && window.ethereum?.isRabby) {
      registerRabbyProvider({
        info: { name: "Rabby Wallet", rdns: "io.rabby" },
        provider: window.ethereum,
      });
    }
    renderPortal();
  }, 600);
}

function bindInteractions() {
  element("connect-wallet").addEventListener("click", connectRabby);
  element("refresh-state").addEventListener("click", () => refreshLiveState());
  element("deployment-confirmation").addEventListener(
    "input",
    renderActionAvailability,
  );
  element("bootstrap-confirmation").addEventListener(
    "input",
    renderActionAvailability,
  );
  element("broadcast-deployment").addEventListener(
    "click",
    broadcastDeployment,
  );
  element("broadcast-bootstrap").addEventListener("click", broadcastBootstrap);
  element("download-evidence").addEventListener("click", downloadEvidence);
  element("copy-address").addEventListener("click", async () => {
    await navigator.clipboard.writeText(SAFE_MANIFEST.safe.predictedAddress);
    setText("copy-address-label", "Copied");
    window.setTimeout(() => setText("copy-address-label", "Copy"), 1200);
  });
  window.addEventListener("beforeunload", (event) => {
    if (!state.busy) return;
    event.preventDefault();
    event.returnValue = "";
  });
}

renderStaticManifest();
renderPortal();
bindInteractions();
discoverRabby();
