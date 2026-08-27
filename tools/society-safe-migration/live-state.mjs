import { getAddress, keccak256, parseAbi, toHex } from "viem";

import { storageWordToAddress } from "../society-safe-portal/core.mjs";
import {
  SAFE_MANIFEST,
  SENTINEL_ADDRESS,
  STORAGE_SLOTS,
  ZERO_ADDRESS,
} from "../society-safe-portal/manifest.mjs";
import {
  ADDRESSES,
  CURRENT_FLS_TOKEN_IDS,
  MIGRATION_ENS_NODE,
  MIGRATION_ROLES,
  SQUAD_TOKEN_IDS,
} from "./migration.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";

const SAFE_READ_ABI = parseAbi([
  "function VERSION() view returns (string)",
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
  "function getModulesPaginated(address,uint256) view returns (address[],address)",
]);
const OWNABLE_ABI = parseAbi([
  "function owner() view returns (address)",
  "function pendingOwner() view returns (address)",
]);
const ERC20_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
]);
const ERC721_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function ownerOf(uint256) view returns (address)",
  "function isApprovedForAll(address,address) view returns (bool)",
]);
const ERC1155_ABI = parseAbi([
  "function balanceOf(address,uint256) view returns (uint256)",
]);
const FAME_ABI = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function unit() view returns (uint256)",
  "function getSkipNFT(address) view returns (bool)",
]);
const FLS_ABI = parseAbi([
  "function owner() view returns (address)",
  "function pendingOwner() view returns (address)",
  "function balanceOf(address) view returns (uint256)",
  "function hasRole(bytes32,address) view returns (bool)",
  "function royaltyInfo(uint256,uint256) view returns (address,uint256)",
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
]);
const FEE_TARGET_ABI = parseAbi([
  "function owner() view returns (address)",
  "function feeRecipient() view returns (address)",
]);
const ROLES_ABI = parseAbi([
  "function rolesOf(address) view returns (uint256)",
]);
const OLD_SAFE_RUNTIME_HASH =
  "0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000";
const OLD_SAFE_EXPECTATIONS = Object.freeze({
  1: Object.freeze({
    singleton: "0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552",
    fallbackHandler: "0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4",
    owners: Object.freeze([
      "0x098Ec024CbeA5784B842E35972218e0679534258",
      "0x8254D14d8c8c82Bf1f9Be44881Dd535488116605",
      "0x21a64eF57be4D6930d3eAF84b8362213F5133Af7",
      "0xd397557dE23d587d70b90726cC88a862AFD915D4",
      "0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D",
      "0xD4Ca157d6ee33a5d0eB811535577cC716b876304",
      "0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c",
      "0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491",
      "0x64b7E2076c47701dF987E389eaEB7254F8a80299",
      "0x007546db322B432f82FcF6067cEEe5916a95005C",
      "0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976",
      "0x0A9071538696a7f2e76A6555c1eb8b6a3C030D47",
      "0x2C0e94B4951E084832b966ec5280924bCb4ACe48",
      "0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83",
    ]),
  }),
  137: Object.freeze({
    singleton: "0x3E5c63644E683549055b9Be8653de26E0B4CD36E",
    fallbackHandler: "0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4",
    owners: Object.freeze([
      "0x098Ec024CbeA5784B842E35972218e0679534258",
      "0x8254D14d8c8c82Bf1f9Be44881Dd535488116605",
      "0xC3E0636c20F1D03Cb2dc7a968996619A43d7B976",
      "0xd397557dE23d587d70b90726cC88a862AFD915D4",
      "0x21a64eF57be4D6930d3eAF84b8362213F5133Af7",
      "0x007546db322B432f82FcF6067cEEe5916a95005C",
      "0x0aC28e7f11cD5106A8b2606DD916Ee652Fb49f83",
      "0x64b7E2076c47701dF987E389eaEB7254F8a80299",
      "0x7e40Acf1dC4c3e844467299b1070Ae2D1951852c",
      "0x2E9BFdA965de0EDe0b41D0dEF2aE917708E7cF6D",
      "0xD4Ca157d6ee33a5d0eB811535577cC716b876304",
      "0x92d35563EA7a4DA571CEA4c15b59f8A9A0975491",
      "0x1De45d6811d6796178C0adE37516E510C1E07f77",
      "0x36eee7D790a5B9e8811fB0C570c883997069DF49",
    ]),
  }),
  8453: Object.freeze({
    singleton: "0xfb1bffC9d739B8D520DaF37dF666da4C687191EA",
    fallbackHandler: "0x017062a1dE2FE6b99BE3d9d37841FeD19F573804",
    owners: Object.freeze([...SAFE_MANIFEST.finalOwners.slice(0, 14)]),
  }),
});

function sameAddress(left, right) {
  return (
    typeof left === "string" &&
    typeof right === "string" &&
    left.toLowerCase() === right.toLowerCase()
  );
}

function assertAddress(label, actual, expected) {
  if (!sameAddress(actual, expected)) {
    throw new Error(`${label}: expected ${expected}, received ${actual}`);
  }
}

function assertEqual(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${expected}, received ${actual}`);
  }
}

function serializeSafe(safe) {
  return {
    version: safe.version,
    owners: safe.owners,
    threshold: safe.threshold.toString(),
    nonce: safe.nonce.toString(),
    runtimeHash: safe.runtimeHash,
    singleton: safe.singleton,
    fallbackHandler: safe.fallbackHandler,
    guard: safe.guard,
    modules: safe.modules,
    modulesNext: safe.modulesNext,
  };
}

async function readAt(client, blockNumber, request) {
  return client.readContract({ ...request, blockNumber });
}

async function readSafe(client, address, blockNumber) {
  const [
    code,
    version,
    owners,
    threshold,
    nonce,
    modulePage,
    singletonWord,
    fallbackWord,
    guardWord,
  ] = await Promise.all([
    client.getBytecode({ address, blockNumber }),
    readAt(client, blockNumber, {
      address,
      abi: SAFE_READ_ABI,
      functionName: "VERSION",
    }),
    readAt(client, blockNumber, {
      address,
      abi: SAFE_READ_ABI,
      functionName: "getOwners",
    }),
    readAt(client, blockNumber, {
      address,
      abi: SAFE_READ_ABI,
      functionName: "getThreshold",
    }),
    readAt(client, blockNumber, {
      address,
      abi: SAFE_READ_ABI,
      functionName: "nonce",
    }),
    readAt(client, blockNumber, {
      address,
      abi: SAFE_READ_ABI,
      functionName: "getModulesPaginated",
      args: [SENTINEL_ADDRESS, 50n],
    }),
    client.getStorageAt({
      address,
      slot: toHex(STORAGE_SLOTS.singleton, { size: 32 }),
      blockNumber,
    }),
    client.getStorageAt({
      address,
      slot: toHex(STORAGE_SLOTS.fallbackHandler, { size: 32 }),
      blockNumber,
    }),
    client.getStorageAt({
      address,
      slot: toHex(STORAGE_SLOTS.guard, { size: 32 }),
      blockNumber,
    }),
  ]);
  if (!code || code === "0x") throw new Error(`${address} has no Safe runtime code`);
  return {
    version,
    owners: [...owners],
    threshold,
    nonce,
    runtimeHash: keccak256(code),
    modules: [...modulePage[0]],
    modulesNext: modulePage[1],
    singleton: storageWordToAddress(singletonWord),
    fallbackHandler: storageWordToAddress(fallbackWord),
    guard: storageWordToAddress(guardWord),
  };
}

function validateNoSafeExtensions(label, safe) {
  assertAddress(`${label} guard`, safe.guard, ZERO_ADDRESS);
  assertEqual(`${label} module count`, safe.modules.length, 0);
  assertAddress(`${label} module cursor`, safe.modulesNext, SENTINEL_ADDRESS);
}

function validateNewSafe(chainId, safe) {
  assertEqual(`chain ${chainId} new Safe version`, safe.version, "1.5.0");
  assertEqual(`chain ${chainId} new Safe threshold`, safe.threshold, 7n);
  assertEqual(`chain ${chainId} new Safe nonce`, safe.nonce, 1n);
  assertEqual(
    `chain ${chainId} new Safe owner count`,
    safe.owners.length,
    SAFE_MANIFEST.finalOwners.length,
  );
  safe.owners.forEach((owner, index) =>
    assertAddress(
      `chain ${chainId} new Safe owner ${index + 1}`,
      owner,
      SAFE_MANIFEST.finalOwners[index],
    ),
  );
  assertEqual(
    `chain ${chainId} new Safe runtime hash`,
    safe.runtimeHash,
    PUBLIC_MIGRATION_CONFIG.societySafeProxyRuntimeHash,
  );
  assertAddress(
    `chain ${chainId} new Safe singleton`,
    safe.singleton,
    SAFE_MANIFEST.safe.singleton,
  );
  assertAddress(
    `chain ${chainId} new Safe fallback handler`,
    safe.fallbackHandler,
    SAFE_MANIFEST.safe.fallbackHandler,
  );
  validateNoSafeExtensions(`chain ${chainId} new Safe`, safe);
}

function validateOldSafe(chainId, safe) {
  const expected = OLD_SAFE_EXPECTATIONS[chainId];
  assertEqual(`chain ${chainId} old Safe version`, safe.version, "1.3.0");
  assertEqual(`chain ${chainId} old Safe threshold`, safe.threshold, 7n);
  assertEqual(`chain ${chainId} old Safe runtime hash`, safe.runtimeHash, OLD_SAFE_RUNTIME_HASH);
  assertAddress(`chain ${chainId} old Safe singleton`, safe.singleton, expected.singleton);
  assertAddress(
    `chain ${chainId} old Safe fallback handler`,
    safe.fallbackHandler,
    expected.fallbackHandler,
  );
  assertEqual(`chain ${chainId} old Safe owner count`, safe.owners.length, expected.owners.length);
  safe.owners.forEach((owner, index) =>
    assertAddress(`chain ${chainId} old Safe owner ${index + 1}`, owner, expected.owners[index]),
  );
  validateNoSafeExtensions(`chain ${chainId} old Safe`, safe);
}

async function assertOwners(client, blockNumber, contract, tokenIds, owner, label) {
  const results = await client.multicall({
    allowFailure: false,
    blockNumber,
    contracts: tokenIds.map((tokenId) => ({
      address: contract,
      abi: ERC721_ABI,
      functionName: "ownerOf",
      args: [BigInt(tokenId)],
    })),
  });
  results.forEach((actual, index) =>
    assertAddress(`${label} token ${tokenIds[index]} owner`, actual, owner),
  );
}

async function readCommonSafeState(client, chainId, blockNumber) {
  const [oldSafe, newSafe, singletonCode, fallbackCode, multiSendCode] = await Promise.all([
    readSafe(client, ADDRESSES.oldSafes[chainId], blockNumber),
    readSafe(client, ADDRESSES.newSafe, blockNumber),
    client.getBytecode({ address: SAFE_MANIFEST.safe.singleton, blockNumber }),
    client.getBytecode({ address: SAFE_MANIFEST.safe.fallbackHandler, blockNumber }),
    client.getBytecode({ address: SAFE_MANIFEST.safe.multiSendCallOnly, blockNumber }),
  ]);
  validateOldSafe(chainId, oldSafe);
  validateNewSafe(chainId, newSafe);
  assertEqual(
    `chain ${chainId} Safe singleton code hash`,
    keccak256(singletonCode),
    SAFE_MANIFEST.safe.singletonCodeHash,
  );
  assertEqual(
    `chain ${chainId} fallback handler code hash`,
    keccak256(fallbackCode),
    SAFE_MANIFEST.safe.fallbackHandlerCodeHash,
  );
  assertEqual(
    `chain ${chainId} MultiSendCallOnly code hash`,
    keccak256(multiSendCode),
    SAFE_MANIFEST.safe.multiSendCallOnlyCodeHash,
  );
  return { oldSafe, newSafe };
}

async function readPolygon(client, blockNumber) {
  const { oldSafe, newSafe } = await readCommonSafeState(
    client,
    137,
    blockNumber,
  );
  const fameusOwner = await readAt(client, blockNumber, {
    address: ADDRESSES.polygonFameus,
    abi: OWNABLE_ABI,
    functionName: "owner",
  });
  assertAddress("Polygon Fameus owner", fameusOwner, ADDRESSES.oldSafes[137]);
  return {
    blockNumber: blockNumber.toString(),
    oldSafeNonce: oldSafe.nonce.toString(),
    newSafeNonce: newSafe.nonce.toString(),
    oldSafe: serializeSafe(oldSafe),
    newSafe: serializeSafe(newSafe),
    fameusOwner,
  };
}

async function readBase(client, blockNumber) {
  const { oldSafe, newSafe } = await readCommonSafeState(
    client,
    8453,
    blockNumber,
  );
  const oldSafeAddress = ADDRESSES.oldSafes[8453];
  const [
    usdcBalance,
    zoraBalance,
    fameBalance,
    fameUnit,
    destinationSkipNft,
    destinationUsdcBalance,
    destinationZoraBalance,
    destinationFameBalance,
  ] =
    await Promise.all([
      readAt(client, blockNumber, {
        address: ADDRESSES.baseUsdc,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [oldSafeAddress],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseZora,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [oldSafeAddress],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseFame,
        abi: FAME_ABI,
        functionName: "balanceOf",
        args: [oldSafeAddress],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseFame,
        abi: FAME_ABI,
        functionName: "unit",
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseFame,
        abi: FAME_ABI,
        functionName: "getSkipNFT",
        args: [ADDRESSES.newSafe],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseUsdc,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [ADDRESSES.newSafe],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseZora,
        abi: ERC20_ABI,
        functionName: "balanceOf",
        args: [ADDRESSES.newSafe],
      }),
      readAt(client, blockNumber, {
        address: ADDRESSES.baseFame,
        abi: FAME_ABI,
        functionName: "balanceOf",
        args: [ADDRESSES.newSafe],
      }),
    ]);
  if (!destinationSkipNft) {
    throw new Error("Base FAME destination must remain skip-NFT enabled");
  }
  await assertOwners(
    client,
    blockNumber,
    ADDRESSES.baseFameMirror,
    [170, 230, 424, 479],
    oldSafeAddress,
    "Base FAME mirror",
  );

  const feeTargets = await Promise.all(
    [
      ADDRESSES.baseRouter,
      ADDRESSES.baseMarketplaceV3,
      ADDRESSES.baseMarketplaceLegacy,
    ].map(async (address) => {
      const [owner, feeRecipient] = await Promise.all([
        readAt(client, blockNumber, {
          address,
          abi: FEE_TARGET_ABI,
          functionName: "owner",
        }),
        readAt(client, blockNumber, {
          address,
          abi: FEE_TARGET_ABI,
          functionName: "feeRecipient",
        }),
      ]);
      assertAddress(`Base fee target ${address} owner`, owner, ADDRESSES.baseFeeAuthority);
      assertAddress(
        `Base fee target ${address} recipient`,
        feeRecipient,
        oldSafeAddress,
      );
      return { address, owner, feeRecipient };
    }),
  );

  return {
    blockNumber: blockNumber.toString(),
    oldSafeNonce: oldSafe.nonce.toString(),
    newSafeNonce: newSafe.nonce.toString(),
    oldSafe: serializeSafe(oldSafe),
    newSafe: serializeSafe(newSafe),
    usdcBalance: usdcBalance.toString(),
    zoraBalance: zoraBalance.toString(),
    fameBalance: fameBalance.toString(),
    fameUnit: fameUnit.toString(),
    destinationUsdcBalance: destinationUsdcBalance.toString(),
    destinationZoraBalance: destinationZoraBalance.toString(),
    destinationFameBalance: destinationFameBalance.toString(),
    destinationSkipNft,
    mirrorTokenIds: [170, 230, 424, 479],
    feeTargets,
  };
}

async function readEthereum(client, blockNumber, newDonationVault) {
  const { oldSafe, newSafe } = await readCommonSafeState(client, 1, blockNumber);
  const oldSafeAddress = ADDRESSES.oldSafes[1];
  const [newDonationCode, donationDeployment, donationReceipt] =
    await Promise.all([
      client.getBytecode({ address: newDonationVault, blockNumber }),
      client.getTransaction({
        hash: PUBLIC_MIGRATION_CONFIG.ethereumDonationVaultDeploymentTx,
      }),
      client.getTransactionReceipt({
        hash: PUBLIC_MIGRATION_CONFIG.ethereumDonationVaultDeploymentTx,
      }),
    ]);
  if (!newDonationCode || newDonationCode === "0x") {
    throw new Error("replacement donation vault address has no runtime code");
  }
  assertEqual(
    "replacement donation vault runtime hash",
    keccak256(newDonationCode),
    PUBLIC_MIGRATION_CONFIG.ethereumDonationVaultRuntimeHash,
  );
  assertEqual("replacement donation vault receipt", donationReceipt.status, "success");
  assertAddress(
    "replacement donation vault contract address",
    donationReceipt.contractAddress,
    newDonationVault,
  );
  assertAddress(
    "replacement donation vault deployer",
    donationDeployment.from,
    ADDRESSES.deployer,
  );
  assertEqual("replacement donation vault creation target", donationDeployment.to, null);
  if (donationReceipt.blockNumber > blockNumber) {
    throw new Error("replacement donation vault was deployed after the pinned block");
  }
  const [
    wethBalance,
    destinationWethBalance,
    flsBalance,
    destinationFlsBalance,
    flsOwner,
    flsPendingOwner,
    oldSafeAdmin,
    oldSafeTreasurer,
    oldDonationTreasurer,
    royalty,
    donationVaultDestination,
    squadApproval,
    yearOwner,
    baeOwner,
    iamNaxBalance,
    obsidianBalance,
    funknloveZeroBalance,
    funknloveOneBalance,
    ensOwner,
    ensResolver,
    ensAddress,
    newDonationWrappedNft,
    newDonationUnderlying,
    newDonationDestination,
    newDonationTreasurer,
    oldFunknloveRoles,
    newFunknloveRoles,
    destinationIamNaxBalance,
    destinationObsidianBalance,
    destinationFunknloveZeroBalance,
    destinationFunknloveOneBalance,
  ] = await Promise.all([
    readAt(client, blockNumber, {
      address: ADDRESSES.weth,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [oldSafeAddress],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.weth,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [ADDRESSES.newSafe],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "balanceOf",
      args: [oldSafeAddress],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "balanceOf",
      args: [ADDRESSES.newSafe],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "owner",
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "pendingOwner",
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "hasRole",
      args: [MIGRATION_ROLES.defaultAdmin, oldSafeAddress],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "hasRole",
      args: [MIGRATION_ROLES.treasurer, oldSafeAddress],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "hasRole",
      args: [MIGRATION_ROLES.treasurer, ADDRESSES.oldDonationVault],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "royaltyInfo",
      args: [0n, 10_000n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.oldDonationVault,
      abi: DONATION_ABI,
      functionName: "vault",
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.squad,
      abi: ERC721_ABI,
      functionName: "isApprovedForAll",
      args: [oldSafeAddress, ADDRESSES.oldDonationVault],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.yearOfTheWoman,
      abi: ERC721_ABI,
      functionName: "ownerOf",
      args: [8626n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.baeApes,
      abi: ERC721_ABI,
      functionName: "ownerOf",
      args: [2520n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.iamNax,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [
        oldSafeAddress,
        24847003539941428306476414038544445787743965496585528607173026678158422704461n,
      ],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.obsidianElegies,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [oldSafeAddress, 3n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [oldSafeAddress, 0n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [oldSafeAddress, 1n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.ensRegistry,
      abi: ENS_REGISTRY_ABI,
      functionName: "owner",
      args: [MIGRATION_ENS_NODE],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.ensRegistry,
      abi: ENS_REGISTRY_ABI,
      functionName: "resolver",
      args: [MIGRATION_ENS_NODE],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.ensResolver,
      abi: ENS_RESOLVER_ABI,
      functionName: "addr",
      args: [MIGRATION_ENS_NODE],
    }),
    readAt(client, blockNumber, {
      address: newDonationVault,
      abi: DONATION_ABI,
      functionName: "wrappedNFT",
    }),
    readAt(client, blockNumber, {
      address: newDonationVault,
      abi: DONATION_ABI,
      functionName: "underlying",
    }),
    readAt(client, blockNumber, {
      address: newDonationVault,
      abi: DONATION_ABI,
      functionName: "vault",
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.fls,
      abi: FLS_ABI,
      functionName: "hasRole",
      args: [MIGRATION_ROLES.treasurer, newDonationVault],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ROLES_ABI,
      functionName: "rolesOf",
      args: [oldSafeAddress],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ROLES_ABI,
      functionName: "rolesOf",
      args: [ADDRESSES.newSafe],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.iamNax,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [
        ADDRESSES.newSafe,
        24847003539941428306476414038544445787743965496585528607173026678158422704461n,
      ],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.obsidianElegies,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [ADDRESSES.newSafe, 3n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [ADDRESSES.newSafe, 0n],
    }),
    readAt(client, blockNumber, {
      address: ADDRESSES.funknlove,
      abi: ERC1155_ABI,
      functionName: "balanceOf",
      args: [ADDRESSES.newSafe, 1n],
    }),
  ]);

  assertEqual("Ethereum current FLS count", flsBalance, 80n);
  assertEqual("Ethereum destination initial FLS count", destinationFlsBalance, 0n);
  assertAddress("FLS owner", flsOwner, oldSafeAddress);
  assertAddress("FLS pending owner", flsPendingOwner, ZERO_ADDRESS);
  assertEqual("old Safe DEFAULT_ADMIN_ROLE", oldSafeAdmin, true);
  assertEqual("old Safe TREASURER_ROLE", oldSafeTreasurer, true);
  assertEqual("old donation vault TREASURER_ROLE", oldDonationTreasurer, true);
  assertAddress("FLS royalty receiver", royalty[0], oldSafeAddress);
  assertEqual("FLS royalty at 10,000", royalty[1], 500n);
  assertAddress("old donation vault destination", donationVaultDestination, oldSafeAddress);
  assertEqual("Squad approval for donation vault", squadApproval, true);
  assertAddress("YEAR OF THE WOMAN #8626 owner", yearOwner, oldSafeAddress);
  assertAddress("Bae Apes #2520 owner", baeOwner, oldSafeAddress);
  assertEqual("IAMNAX ERC-1155 balance", iamNaxBalance, 1n);
  assertEqual("Obsidian Elegies #3 balance", obsidianBalance, 1n);
  assertEqual("FUNKNLOVE ID 0 balance", funknloveZeroBalance, 11n);
  assertEqual("FUNKNLOVE ID 1 balance", funknloveOneBalance, 1n);
  assertAddress("ENS child owner", ensOwner, oldSafeAddress);
  assertAddress("ENS resolver", ensResolver, ADDRESSES.ensResolver);
  assertAddress("ENS resolved address", ensAddress, oldSafeAddress);
  assertAddress("new donation wrappedNFT", newDonationWrappedNft, ADDRESSES.fls);
  assertAddress("new donation underlying", newDonationUnderlying, ADDRESSES.squad);
  assertAddress("new donation destination", newDonationDestination, ADDRESSES.newSafe);
  assertEqual("new donation vault initial TREASURER_ROLE", newDonationTreasurer, false);
  if ((oldFunknloveRoles & 2n) !== 2n) {
    throw new Error("old Safe does not hold FUNKNLOVE role 2");
  }
  if ((newFunknloveRoles & 2n) !== 0n) {
    throw new Error("new Safe already holds FUNKNLOVE role 2");
  }

  await Promise.all([
    assertOwners(
      client,
      blockNumber,
      ADDRESSES.fls,
      CURRENT_FLS_TOKEN_IDS,
      oldSafeAddress,
      "FLS",
    ),
    assertOwners(
      client,
      blockNumber,
      ADDRESSES.squad,
      SQUAD_TOKEN_IDS,
      oldSafeAddress,
      "Squad",
    ),
  ]);

  return {
    blockNumber: blockNumber.toString(),
    oldSafeNonce: oldSafe.nonce.toString(),
    newSafeNonce: newSafe.nonce.toString(),
    oldSafe: serializeSafe(oldSafe),
    newSafe: serializeSafe(newSafe),
    wethBalance: wethBalance.toString(),
    destinationWethBalance: destinationWethBalance.toString(),
    flsBalance: flsBalance.toString(),
    destinationFlsBalance: destinationFlsBalance.toString(),
    flsTokenIds: [...CURRENT_FLS_TOKEN_IDS],
    squadTokenIds: [...SQUAD_TOKEN_IDS],
    flsOwner,
    flsPendingOwner,
    roles: {
      oldSafeAdmin,
      oldSafeTreasurer,
      oldDonationTreasurer,
      oldFunknloveRoles: oldFunknloveRoles.toString(),
      newFunknloveRoles: newFunknloveRoles.toString(),
    },
    royaltyReceiver: royalty[0],
    royaltyBps: royalty[1].toString(),
    donationVaultDestination,
    squadApproval,
    relatedBalances: {
      iamNax: iamNaxBalance.toString(),
      obsidianElegies: obsidianBalance.toString(),
      funknlove0: funknloveZeroBalance.toString(),
      funknlove1: funknloveOneBalance.toString(),
    },
    destinationRelatedBalances: {
      iamNax: destinationIamNaxBalance.toString(),
      obsidianElegies: destinationObsidianBalance.toString(),
      funknlove0: destinationFunknloveZeroBalance.toString(),
      funknlove1: destinationFunknloveOneBalance.toString(),
    },
    ens: {
      owner: ensOwner,
      resolver: ensResolver,
      address: ensAddress,
    },
    newDonationVault: {
      address: newDonationVault,
      wrappedNFT: newDonationWrappedNft,
      underlying: newDonationUnderlying,
      vault: newDonationDestination,
      hasTreasurerRole: newDonationTreasurer,
      deploymentTx: PUBLIC_MIGRATION_CONFIG.ethereumDonationVaultDeploymentTx,
      deploymentBlock: donationReceipt.blockNumber.toString(),
      deployer: donationDeployment.from,
      runtimeHash: keccak256(newDonationCode),
    },
  };
}

export async function readMigrationSnapshot(
  clients,
  generatedAt = new Date(),
  { newDonationVaultAddress } = {},
) {
  for (const chainId of [1, 137, 8453]) {
    if (!clients[chainId]) throw new Error(`missing public client for chain ${chainId}`);
  }
  if (!newDonationVaultAddress) {
    throw new Error("newDonationVaultAddress is required for live verification");
  }
  const newDonationVault = getAddress(newDonationVaultAddress);
  assertAddress(
    "replacement donation vault public config",
    newDonationVault,
    PUBLIC_MIGRATION_CONFIG.ethereumDonationVault,
  );
  const [ethereumBlock, polygonBlock, baseBlock] = await Promise.all([
    clients[1].getBlockNumber(),
    clients[137].getBlockNumber(),
    clients[8453].getBlockNumber(),
  ]);
  const [ethereum, polygon, base] = await Promise.all([
    readEthereum(clients[1], ethereumBlock, newDonationVault),
    readPolygon(clients[137], polygonBlock),
    readBase(clients[8453], baseBlock),
  ]);
  return {
    schemaVersion: 1,
    generatedAt: generatedAt.toISOString(),
    destinationSafe: getAddress(ADDRESSES.newSafe),
    chains: {
      1: ethereum,
      137: polygon,
      8453: base,
    },
  };
}
