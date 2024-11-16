// apologies for the mess, this file was mutilated during the launch and this is what we have

import {
  encodeFunctionData,
  createPublicClient,
  createWalletClient,
  parseEther,
  formatEther,
  isAddress,
  toHex,
  erc20Abi,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import fs from "fs";
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import {
  claimToFameAbi,
  fameVestingAbi,
  iGasliteDropAbi,
} from "../wagmi/generated.js";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";
import { base } from "viem/chains";

const CHAIN_ID = Number(process.env.MULTISIG_CHAIN_ID ?? "0");
const MULTISIG_ADDRESS = process.env.MULTISIG_ADDRESS! as `0x${string}`;
const MULTISIG_PRIVATE_KEY = process.env.MULTISIG_PRIVATE_KEY! as `0x${string}`;
const MULTISIG_RPC = process.env.MULTISIG_RPC!;
const CLAIM_TO_FAME_ADDRESS = process.env
  .CLAIM_TO_FAME_ADDRESS! as `0x${string}`;
const GASLITE_DROP_ADDRESS =
  (process.env.GASLITE_DROP_ADDRESS as `0x${string}`) ??
  "0x09350F89e2D7B6e96bA730783c2d76137B045FEF";
const FAME_ADDRESS = process.env.FAME_ADDRESS! as `0x${string}`;
const FAME_VESTING_CONTRACT_ADDRESS = process.env
  .FAME_VESTING_CONTRACT_ADDRESS! as `0x${string}`;
const PRESALE_MAX = parseEther(process.env.PRESALE_MAX ?? "6");
const INPUT_FILE = process.env.INPUT_FILE ?? "holders.csv";
const PRESALE_ALLOCATION = parseEther(
  process.env.PRESALE_ALLOCATION ?? "176000000"
);
const holdersCsv = fs.readFileSync(INPUT_FILE, "utf-8");
const holdersVesting = new Map<`0x${string}`, bigint>();
const holdersAirdrop = new Map<`0x${string}`, bigint>();
function presaleHoldingToAllocation(holding: bigint) {
  return (holding * PRESALE_ALLOCATION) / PRESALE_MAX;
}
holdersCsv
  .split("\n")
  .slice(1)
  .forEach((line) => {
    if (line === "") {
      return;
    }
    let [address, amount] = line.split(",");
    address = address.trim().replace(/"/g, "");
    amount = amount.trim().replace(/"/g, "");
    if (!isAddress(address)) {
      throw new Error(`Invalid address: ${address}`);
    }
    const allocation = presaleHoldingToAllocation(parseEther(amount));
    const cliff = allocation / 10n;
    holdersVesting.set(address, allocation - cliff);
    holdersAirdrop.set(address, cliff);
  });

let totalAllocation = Array.from(holdersVesting.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);
let totalAirdrop = Array.from(holdersAirdrop.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);

// Find any delta between the total allocation and the presale allocation and
// Adjust the first holder to make up the difference
const delta = PRESALE_ALLOCATION - totalAllocation - totalAirdrop;
const firstKey = holdersVesting.keys().next().value as `0x${string}`;
if (delta > 0) {
  const firstHolder = holdersVesting.get(firstKey);
  holdersVesting.set(firstKey, firstHolder! + delta);
} else if (delta < 0) {
  const firstHolder = holdersVesting.get(firstKey);
  holdersVesting.set(firstKey, firstHolder! - delta);
}
totalAllocation = Array.from(holdersVesting.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);
console.log(`Total allocation: ${formatEther(totalAllocation)}`);
console.log(`Total airdrop: ${formatEther(totalAirdrop)}`);
console.log(`Total presale: ${formatEther(totalAirdrop + totalAllocation)}`);
console.log(`A delta of ${formatEther(delta)} was applied to the first holder`);

// Now add the claim to fame airdrop recipients, these are people
// that wrapped but did not claim, we will just airdrop to settle
// the score
holdersAirdrop.set(
  "0x00175dc0780E23D0edB8615DB6faE62F38427c2c",
  (holdersAirdrop.get("0x00175dc0780E23D0edB8615DB6faE62F38427c2c") ?? 0n) +
    parseEther("34148") +
    parseEther("27447")
);
holdersAirdrop.set(
  "0xe494d61977561d6be41590FbF940091bAE6d392e",
  (holdersAirdrop.get("0xe494d61977561d6be41590FbF940091bAE6d392e") ?? 0n) +
    parseEther("17156")
);

holdersAirdrop.set(
  "0x3D858eb26d43EFBC2d5165563A05E553Cb4c43Fd",
  (holdersAirdrop.get("0x3D858eb26d43EFBC2d5165563A05E553Cb4c43Fd") ?? 0n) +
    parseEther("12976")
);
totalAirdrop = Array.from(holdersAirdrop.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);

// Some starter values
// July 26, 2024 0 utc
const start = BigInt(new Date("2024-07-26T00:00:00Z").getTime()) / 1000n;
const cliff = 0n;
// 3 months in seconds
const duration = 60n * 60n * 24n * 30n * 3n;
const slicePeriodSeconds = 1n;

const transactionData = Array.from(holdersVesting.entries()).map(
  ([address, amount]) =>
    encodeFunctionData({
      abi: fameVestingAbi,
      functionName: "createVestingSchedule",
      args: [address, start, cliff, duration, slicePeriodSeconds, true, amount],
    })
);

const safe = await Safe.default.init({
  provider: MULTISIG_RPC,
  signer: MULTISIG_PRIVATE_KEY,
  safeAddress: MULTISIG_ADDRESS,
});

console.log(`Generated ${transactionData.length} create vesting transactions`);
// console.log(transactionData.join("\n"));

// const withdrawFromClaim = encodeFunctionData({
//   abi: claimToFameAbi,
//   functionName: "withdrawErc20",
//   args: [FAME_ADDRESS, 168921483618529361195135311n],
// });

const encodeTransferToVesting = encodeFunctionData({
  abi: erc20Abi,
  functionName: "transfer",
  args: [FAME_VESTING_CONTRACT_ADDRESS, totalAllocation],
});

// const encodedApproveFameToGaslite = encodeFunctionData({
//   abi: erc20Abi,
//   functionName: "approve",
//   args: [GASLITE_DROP_ADDRESS, totalAirdrop],
// });

// const encodedAirdrop = encodeFunctionData({
//   abi: iGasliteDropAbi,
//   functionName: "airdropERC20",
//   args: [
//     FAME_ADDRESS,
//     [...holdersAirdrop.keys()],
//     [...holdersAirdrop.values()],
//     totalAirdrop,
//   ],
// });

const safeTransactionData = [
  // {
  //   to: CLAIM_TO_FAME_ADDRESS,
  //   value: "0",
  //   data: withdrawFromClaim,
  // },
  {
    to: FAME_ADDRESS,
    value: "0",
    data: encodeTransferToVesting,
  },
  ...transactionData.map((data) => ({
    to: FAME_VESTING_CONTRACT_ADDRESS,
    value: "0",
    data,
  })),
  // {
  //   to: FAME_ADDRESS,
  //   value: "0",
  //   data: encodedApproveFameToGaslite,
  // },
  // {
  //   to: GASLITE_DROP_ADDRESS,
  //   value: "0",
  //   data: encodedAirdrop,
  // },
];

const wallet = createWalletClient({
  transport: http(MULTISIG_RPC),
  account: privateKeyToAccount(MULTISIG_PRIVATE_KEY),
  chain: base,
});
const client = createPublicClient({
  transport: http(MULTISIG_RPC),
  chain: base,
});

// await wallet.writeContract({
//   address: FAME_ADDRESS,
//   abi: erc20Abi,
//   functionName: "transfer",
//   args: [FAME_VESTING_CONTRACT_ADDRESS, totalAllocation],
// });
let SKIP_NUMBER = 19;
for (const [address, amount] of holdersVesting.entries()) {
  // console.log(address);
  if (SKIP_NUMBER > 0) {
    SKIP_NUMBER--;
    continue;
  }
  // console.log(address);
  const receipt = await wallet.writeContract({
    address: FAME_VESTING_CONTRACT_ADDRESS,
    abi: fameVestingAbi,
    functionName: "createVestingSchedule",
    args: [address, start, cliff, duration, slicePeriodSeconds, true, amount],
  });
  console.log(`Vesting schedule created for ${address}`);
  await client.waitForTransactionReceipt({
    hash: receipt,
    confirmations: 2,
  });
}

// const safeTransaction = await safe.createTransaction({
//   transactions: safeTransactionData,
// });

// console.log("Transaction ready to be sent to the Safe");

// // Deterministic hash based on transaction parameters
// const safeTxHash = await safe.getTransactionHash(safeTransaction);

// // Sign transaction to verify that the transaction is coming from owner 1
// const senderSignature = await safe.signHash(safeTxHash);

// // console.log(JSON.stringify(safeTransactionData, null, 2));

// const apiKit = new SafeApiKit.default({
//   chainId: BigInt(CHAIN_ID),
// });

// await apiKit.proposeTransaction({
//   safeAddress: MULTISIG_ADDRESS,
//   safeTransactionData: safeTransaction.data,
//   safeTxHash,
//   senderAddress: privateKeyToAccount(MULTISIG_PRIVATE_KEY).address,
//   senderSignature: senderSignature.data,
// });

// console.log("Transaction sent to the Safe");
