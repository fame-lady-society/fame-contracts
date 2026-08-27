import { encodeFunctionData, getAddress, parseAbi } from "viem";

import { buildTransactionBuilderBatch } from "./transaction-builder.mjs";
import { PUBLIC_MIGRATION_CONFIG } from "./public-config.mjs";

const DEFAULT_ADMIN_ROLE =
  "0x0000000000000000000000000000000000000000000000000000000000000000";
const TREASURER_ROLE =
  "0x3496e2e73c4d42b75d702e60d9e48102720b8691234415963a5a857b86425d07";
const ENS_VAULT_NODE =
  "0x2e52a3ea02db5dd1e719509b39047494a77b5f986dfa33bfa5ac69a204e172ae";

export const ADDRESSES = Object.freeze({
  newSafe: PUBLIC_MIGRATION_CONFIG.societySafe,
  deployer: "0xFA3Ef9890D792C7F61e3882dBDd5A8E13394B252",
  oldSafes: Object.freeze({
    1: "0xCDF3e235A04624d7f23909EbBaD008Db2c54e1cF",
    137: "0x560dF07ff3aB5eAE66683D6e11AbFa28f1801997",
    8453: "0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D",
  }),
  polygonFameus: "0x3018671f3495419636519f37FfeA85BfBe3dce0f",
  baseUsdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  baseZora: "0x1111111111166b7FE7bd91427724B487980aFc69",
  baseFame: "0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418",
  baseFameMirror: "0xbb5ed04dd7b207592429eb8d599d103ccad646c4",
  baseRouter: "0xAdefa5860389E8936ebf2977e1Fb4a365aA39636",
  baseMarketplaceV3: "0x93222897902a5Fc2f20079d242c660117277930A",
  baseMarketplaceLegacy: "0x54e7E4F2d439Be599706f51068f7EB2ce2D2a27e",
  baseFeeAuthority: "0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9",
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  fls: "0x6cF4328f1Ea83B5d592474F9fCDC714FAAfd1574",
  squad: "0xf3E6DbBE461C6fa492CeA7Cb1f5C5eA660EB1B47",
  oldDonationVault: "0x7a276F4B91A97267D652500aa4aB8b2Fa388fb9b",
  yearOfTheWoman: "0x3C7b5B7ea8e7C7ce8297baC167FEb97BF5A1ad98",
  baeApes: "0xb56011FBfdAfe460b905A40A4845A49C94712272",
  iamNax: "0x495f947276749Ce646f68AC8c248420045cb7b5e",
  obsidianElegies: "0x85A6b52F30839acbd12e1cD189e850467bCcb95a",
  funknlove: "0xf407EE7289CA1941a0D9c89C57fe53F665AD237B",
  ensResolver: "0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63",
  ensRegistry: "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
  ensReverseRegistrar: "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb",
});

export const CURRENT_FLS_TOKEN_IDS = Object.freeze([
  328, 593, 649, 722, 724, 757, 801, 1348, 1402, 1546, 1703, 1778, 1820,
  1896, 2193, 2247, 2335, 2349, 2372, 2676, 2709, 2792, 2899, 2918, 2986,
  2998, 3163, 3170, 3261, 3269, 3328, 3653, 3670, 3729, 4042, 4090, 4243,
  4276, 4289, 4404, 4456, 4516, 4520, 4543, 4567, 4975, 5037, 5149, 5246,
  5272, 5309, 5402, 5550, 5632, 5846, 5865, 6040, 6091, 6659, 6772, 6850,
  7124, 7203, 7283, 7325, 7350, 7527, 7576, 7832, 7914, 7961, 8061, 8256,
  8283, 8368, 8371, 8579, 8583, 8587, 8688,
]);

export const SQUAD_TOKEN_IDS = Object.freeze([
  2392, 2630, 2639, 2642, 2645, 3416, 3809, 3812, 3815, 3817, 3902, 3904,
  4097, 4268, 4410, 5605, 5610, 5627, 5761, 5882, 5885, 5920, 6170, 6182,
  6270, 6495, 7161,
]);

const ALL_FLS_TOKEN_IDS = Object.freeze(
  [...CURRENT_FLS_TOKEN_IDS, ...SQUAD_TOKEN_IDS].sort((a, b) => a - b),
);
if (new Set(ALL_FLS_TOKEN_IDS).size !== 107) {
  throw new Error("the approved post-wrap FLS inventory must contain 107 unique IDs");
}

function jsonSafe(value) {
  if (typeof value === "bigint") return value.toString();
  if (Array.isArray(value)) return value.map(jsonSafe);
  return value;
}

function encodedCall({ id, target, method, args = [], value = 0n }) {
  const abi = parseAbi([`function ${method}`]);
  const data = encodeFunctionData({
    abi,
    functionName: method.slice(0, method.indexOf("(")),
    args,
  });
  return Object.freeze({
    id,
    to: getAddress(target),
    value: value.toString(),
    data,
    method,
    args: jsonSafe(args),
    operation: 0,
  });
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function requireUnsignedInteger(snapshot, chainId, key, { positive = false } = {}) {
  const value = snapshot.chains?.[chainId]?.[key];
  if (typeof value !== "string" || !/^\d+$/.test(value)) {
    throw new Error(`chain ${chainId} ${key} must be an unsigned integer string`);
  }
  if (positive && BigInt(value) === 0n) {
    throw new Error(`chain ${chainId} ${key} must be greater than zero`);
  }
  return BigInt(value);
}

function makeBatch({
  id,
  filename,
  chainId,
  sourceSafe,
  name,
  description,
  calls,
  createdAt,
  executionGate = null,
}) {
  return Object.freeze({
    id,
    filename,
    chainId,
    sourceSafe,
    name,
    description,
    calls: Object.freeze(calls),
    executionGate,
    builder: buildTransactionBuilderBatch({
      chainId,
      safeAddress: sourceSafe,
      name,
      description,
      calls,
      createdAt,
    }),
  });
}

export function buildMigrationArtifacts(
  snapshot,
  {
    createdAt = Date.now(),
    flsChunkSize = 20,
    newDonationVaultAddress,
  } = {},
) {
  if (!Number.isSafeInteger(flsChunkSize) || flsChunkSize < 1) {
    throw new Error("flsChunkSize must be a positive integer");
  }
  if (!newDonationVaultAddress) {
    throw new Error(
      "newDonationVaultAddress is required; incomplete migration sets are not emitted",
    );
  }
  const newDonationVault = getAddress(newDonationVaultAddress);
  if (newDonationVault !== PUBLIC_MIGRATION_CONFIG.ethereumDonationVault) {
    throw new Error(
      "newDonationVaultAddress does not match config/fame-public.env",
    );
  }

  const usdcBalance = requireUnsignedInteger(snapshot, 8453, "usdcBalance", {
    positive: true,
  });
  const zoraBalance = requireUnsignedInteger(snapshot, 8453, "zoraBalance", {
    positive: true,
  });
  const fameBalance = requireUnsignedInteger(snapshot, 8453, "fameBalance", {
    positive: true,
  });
  const fameUnit = requireUnsignedInteger(snapshot, 8453, "fameUnit", {
    positive: true,
  });
  const fourMirrorUnits = 4n * fameUnit;
  if (fameBalance < fourMirrorUnits) {
    throw new Error("live FAME balance is smaller than the four mirror units");
  }
  const fameRemainder = fameBalance - fourMirrorUnits;
  const wethBalance = requireUnsignedInteger(snapshot, 1, "wethBalance", {
    positive: true,
  });

  const polygonOwnership = makeBatch({
    id: "P-CTRL-01",
    filename: "polygon-01-transfer-fameus-ownership.json",
    chainId: 137,
    sourceSafe: ADDRESSES.oldSafes[137],
    name: "Society migration - Polygon Fameus ownership",
    description:
      "Unsigned old-Safe batch. Transfer Fameus ownership to the finalized cross-chain Society Safe.",
    calls: [
      encodedCall({
        id: "P-CTRL-01",
        target: ADDRESSES.polygonFameus,
        method: "transferOwnership(address)",
        args: [ADDRESSES.newSafe],
      }),
    ],
    createdAt,
  });

  const baseCore = makeBatch({
    id: "B-CORE-ERC20",
    filename: "base-01-core-erc20.json",
    chainId: 8453,
    sourceSafe: ADDRESSES.oldSafes[8453],
    name: "Society migration - Base USDC and ZORA",
    description:
      "Unsigned old-Safe batch using balances pinned in the accompanying review manifest.",
    calls: [
      encodedCall({
        id: "B-CORE-USDC",
        target: ADDRESSES.baseUsdc,
        method: "transfer(address,uint256)",
        args: [ADDRESSES.newSafe, usdcBalance],
      }),
      encodedCall({
        id: "B-CORE-ZORA",
        target: ADDRESSES.baseZora,
        method: "transfer(address,uint256)",
        args: [ADDRESSES.newSafe, zoraBalance],
      }),
    ],
    createdAt,
  });

  const baseFame = makeBatch({
    id: "B-FAME-DN404",
    filename: "base-02-fame-dn404.json",
    chainId: 8453,
    sourceSafe: ADDRESSES.oldSafes[8453],
    name: "Society migration - Base FAME linked position",
    description:
      "Atomic old-Safe batch: preserve mirror IDs 170, 230, 424, and 479, then transfer only the FAME remainder.",
    calls: [
      ...[170, 230, 424, 479].map((tokenId) =>
        encodedCall({
          id: `B-FAME-MIRROR-${tokenId}`,
          target: ADDRESSES.baseFameMirror,
          method: "safeTransferFrom(address,address,uint256)",
          args: [
            ADDRESSES.oldSafes[8453],
            ADDRESSES.newSafe,
            BigInt(tokenId),
          ],
        }),
      ),
      encodedCall({
        id: "B-CORE-FAME-REMAINDER",
        target: ADDRESSES.baseFame,
        method: "transfer(address,uint256)",
        args: [ADDRESSES.newSafe, fameRemainder],
      }),
    ],
    createdAt,
  });

  const ethereumWrap = makeBatch({
    id: "E-SQUAD-WRAP-FIRST",
    filename: "ethereum-01-wrap-squad.json",
    chainId: 1,
    sourceSafe: ADDRESSES.oldSafes[1],
    name: "Society migration - wrap 27 FameLadySquad NFTs",
    description:
      "Unsigned old-Safe normalization batch. Wrap the exact 27 approved Squad IDs through the existing donation vault before FLS migration.",
    calls: [
      encodedCall({
        id: "E-SQUAD-WRAP-FIRST",
        target: ADDRESSES.oldDonationVault,
        method: "wrapAndDonate(uint256[])",
        args: [SQUAD_TOKEN_IDS.map(BigInt)],
      }),
    ],
    createdAt,
  });

  const ethereumRelatedAssets = makeBatch({
    id: "E-RELATED-ASSETS",
    filename: "ethereum-02-related-assets.json",
    chainId: 1,
    sourceSafe: ADDRESSES.oldSafes[1],
    name: "Society migration - Ethereum WETH and related collectibles",
    description:
      "Unsigned old-Safe batch for the approved WETH, ERC-721, and ERC-1155 holdings other than FLS.",
    calls: [
      encodedCall({
        id: "E-CORE-WETH",
        target: ADDRESSES.weth,
        method: "transfer(address,uint256)",
        args: [ADDRESSES.newSafe, wethBalance],
      }),
      encodedCall({
        id: "E-RELATED-721-YEAR-OF-THE-WOMAN",
        target: ADDRESSES.yearOfTheWoman,
        method: "safeTransferFrom(address,address,uint256)",
        args: [ADDRESSES.oldSafes[1], ADDRESSES.newSafe, 8626n],
      }),
      encodedCall({
        id: "E-RELATED-721-BAE-APES",
        target: ADDRESSES.baeApes,
        method: "safeTransferFrom(address,address,uint256)",
        args: [ADDRESSES.oldSafes[1], ADDRESSES.newSafe, 2520n],
      }),
      encodedCall({
        id: "E-RELATED-1155-IAMNAX",
        target: ADDRESSES.iamNax,
        method:
          "safeTransferFrom(address,address,uint256,uint256,bytes)",
        args: [
          ADDRESSES.oldSafes[1],
          ADDRESSES.newSafe,
          24847003539941428306476414038544445787743965496585528607173026678158422704461n,
          1n,
          "0x",
        ],
      }),
      encodedCall({
        id: "E-RELATED-1155-OBSIDIAN",
        target: ADDRESSES.obsidianElegies,
        method:
          "safeTransferFrom(address,address,uint256,uint256,bytes)",
        args: [ADDRESSES.oldSafes[1], ADDRESSES.newSafe, 3n, 1n, "0x"],
      }),
      encodedCall({
        id: "E-SOCIETY-1155-FUNKNLOVE",
        target: ADDRESSES.funknlove,
        method:
          "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)",
        args: [
          ADDRESSES.oldSafes[1],
          ADDRESSES.newSafe,
          [0n, 1n],
          [11n, 1n],
          "0x",
        ],
      }),
    ],
    createdAt,
  });

  const flsChunks = chunks(ALL_FLS_TOKEN_IDS, flsChunkSize).map(
    (tokenIds, index, allChunks) =>
      makeBatch({
        id: `E-FLS-721-${String(index + 1).padStart(2, "0")}`,
        filename: `ethereum-03-fls-${String(index + 1).padStart(2, "0")}-of-${String(allChunks.length).padStart(2, "0")}.json`,
        chainId: 1,
        sourceSafe: ADDRESSES.oldSafes[1],
        name: `Society migration - FLS NFTs ${index + 1} of ${allChunks.length}`,
        description:
          "Unsigned old-Safe batch. Execute only after E-SQUAD-WRAP-FIRST succeeds and the refreshed old-Safe FLS inventory is exactly 107 approved IDs.",
        calls: tokenIds.map((tokenId) =>
          encodedCall({
            id: `E-FLS-721-${tokenId}`,
            target: ADDRESSES.fls,
            method: "safeTransferFrom(address,address,uint256)",
            args: [ADDRESSES.oldSafes[1], ADDRESSES.newSafe, BigInt(tokenId)],
          }),
        ),
        createdAt,
        executionGate: "after-squad-wrap-and-107-ownerOf-refresh",
      }),
  );

  const ethereumAuthority = makeBatch({
    id: "E-FLS-AUTHORITY-HANDOFF",
    filename: "ethereum-04-fls-authority-handoff.json",
    chainId: 1,
    sourceSafe: ADDRESSES.oldSafes[1],
    name: "Society migration - FLS authority handoff",
    description:
      "CONDITIONAL: do not execute until the paired new-Safe finalization batch is fully signed at its reserved nonce and the replacement donation-vault grant is complete.",
    calls: [
      encodedCall({
        id: "E-FLS-ADMIN-GRANT",
        target: ADDRESSES.fls,
        method: "grantRole(bytes32,address)",
        args: [DEFAULT_ADMIN_ROLE, ADDRESSES.newSafe],
      }),
      encodedCall({
        id: "E-FLS-TREASURER-GRANT",
        target: ADDRESSES.fls,
        method: "grantRole(bytes32,address)",
        args: [TREASURER_ROLE, ADDRESSES.newSafe],
      }),
      encodedCall({
        id: "E-FLS-ROYALTY-RECEIVER",
        target: ADDRESSES.fls,
        method: "setDefaultRoyalty(address,uint96)",
        args: [ADDRESSES.newSafe, 500n],
      }),
      encodedCall({
        id: "E-FLS-OWNER-START",
        target: ADDRESSES.fls,
        method: "transferOwnership(address)",
        args: [ADDRESSES.newSafe],
      }),
    ],
    createdAt,
    executionGate:
      "all-approved-asset-batches-complete-new-safe-finalization-fully-signed-and-new-donation-vault-ready",
  });

  const ethereumDonationGrant = makeBatch({
    id: "E-FLS-DONATION-GRANT",
    filename: "ethereum-04a-donation-vault-role-grant.json",
    chainId: 1,
    sourceSafe: ADDRESSES.oldSafes[1],
    name: "Society migration - authorize replacement donation vault",
    description:
      "Unsigned old-Safe batch. Grant TREASURER_ROLE only after the replacement vault bytecode and all three immutable addresses are verified.",
    calls: [
      encodedCall({
        id: "E-FLS-DONATION-GRANT",
        target: ADDRESSES.fls,
        method: "grantRole(bytes32,address)",
        args: [TREASURER_ROLE, newDonationVault],
      }),
    ],
    createdAt,
    executionGate: "replacement-donation-vault-onchain-immutables-verified",
  });

  const ethereumEns = makeBatch({
    id: "E-ENS-FORWARD-AND-OWNER",
    filename: "ethereum-05-ens-forward-and-owner.json",
    chainId: 1,
    sourceSafe: ADDRESSES.oldSafes[1],
    name: "Society migration - ENS forward record and ownership",
    description:
      "Unsigned old-Safe batch. Update vault.fameladysociety.eth address first, then transfer the child node to the new Safe.",
    calls: [
      encodedCall({
        id: "E-ENS-FORWARD-ADDR",
        target: ADDRESSES.ensResolver,
        method: "setAddr(bytes32,address)",
        args: [ENS_VAULT_NODE, ADDRESSES.newSafe],
      }),
      encodedCall({
        id: "E-ENS-OWNER",
        target: ADDRESSES.ensRegistry,
        method: "setOwner(bytes32,address)",
        args: [ENS_VAULT_NODE, ADDRESSES.newSafe],
      }),
    ],
    createdAt,
  });

  const ethereumPostAuthority = makeBatch({
    id: "E-POST-MIGRATION-AUTHORITY",
    filename: "ethereum-06-post-migration-authority.json",
    chainId: 1,
    sourceSafe: ADDRESSES.newSafe,
    name: "Society migration - accept and finalize authority",
    description:
      "CONDITIONAL NEW-SAFE BATCH: fully sign at reserved nonce before the old Safe starts ownership transfer; execute immediately afterward and only after donation cutover gates pass.",
    calls: [
      encodedCall({
        id: "E-FLS-OWNER-ACCEPT",
        target: ADDRESSES.fls,
        method: "acceptOwnership()",
      }),
      encodedCall({
        id: "E-FLS-REVOKE-OLD-TREASURER",
        target: ADDRESSES.fls,
        method: "revokeRole(bytes32,address)",
        args: [TREASURER_ROLE, ADDRESSES.oldSafes[1]],
      }),
      encodedCall({
        id: "E-FLS-REVOKE-OLD-ADMIN",
        target: ADDRESSES.fls,
        method: "revokeRole(bytes32,address)",
        args: [DEFAULT_ADMIN_ROLE, ADDRESSES.oldSafes[1]],
      }),
      encodedCall({
        id: "E-FLS-REVOKE-OLD-DONATION",
        target: ADDRESSES.fls,
        method: "revokeRole(bytes32,address)",
        args: [TREASURER_ROLE, ADDRESSES.oldDonationVault],
      }),
      encodedCall({
        id: "E-ENS-REVERSE",
        target: ADDRESSES.ensReverseRegistrar,
        method: "setName(string)",
        args: ["vault.fameladysociety.eth"],
      }),
    ],
    createdAt,
    executionGate:
      "pendingOwner-new-safe-ens-owner-new-safe-and-donation-cutover-complete",
  });

  const operatorCalls = [
    ...[
      ["B-FEE-01", ADDRESSES.baseRouter],
      ["B-FEE-02", ADDRESSES.baseMarketplaceV3],
      ["B-FEE-03", ADDRESSES.baseMarketplaceLegacy],
    ].map(([id, target]) => ({
      chainId: 8453,
      from: ADDRESSES.baseFeeAuthority,
      ...encodedCall({
        id,
        target,
        method: "setFeeRecipient(address)",
        args: [ADDRESSES.newSafe],
      }),
    })),
    {
      chainId: 1,
      from: ADDRESSES.deployer,
      ...encodedCall({
        id: "E-FNL-ROLE-01",
        target: ADDRESSES.funknlove,
        method: "grantRoles(address,uint256)",
        args: [ADDRESSES.newSafe, 2n],
      }),
    },
    {
      chainId: 1,
      from: ADDRESSES.deployer,
      ...encodedCall({
        id: "E-FNL-ROLE-02",
        target: ADDRESSES.funknlove,
        method: "revokeRoles(address,uint256)",
        args: [ADDRESSES.oldSafes[1], 2n],
      }),
    },
  ];

  return Object.freeze({
    snapshot,
    batches: Object.freeze([
      polygonOwnership,
      baseCore,
      baseFame,
      ethereumWrap,
      ethereumRelatedAssets,
      ...flsChunks,
      ethereumDonationGrant,
      ethereumAuthority,
      ethereumEns,
      ethereumPostAuthority,
    ]),
    operatorCalls: Object.freeze(operatorCalls),
    blocked: Object.freeze([
      {
        id: "CANARY-TRANSFERS",
        reason:
          "No exact canary assets or amounts have been approved; no canary calldata is invented.",
      },
      {
        id: "B-NATIVE-FINAL",
        reason:
          "Generate from the refreshed Base balance only after every earlier Base batch executes.",
      },
      {
        id: "E-NATIVE-FINAL",
        reason:
          "Generate from the refreshed Ethereum balance only after every earlier Ethereum batch executes.",
      },
    ]),
    externalPrerequisites: Object.freeze([]),
    newDonationVault,
  });
}

export const MIGRATION_ROLES = Object.freeze({
  defaultAdmin: DEFAULT_ADMIN_ROLE,
  treasurer: TREASURER_ROLE,
});

export const MIGRATION_ENS_NODE = ENS_VAULT_NODE;
