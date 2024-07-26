import {
  encodeFunctionData,
  createPublicClient,
  parseEther,
  formatEther,
  isAddress,
  toHex,
  erc20Abi,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import fs from "fs";
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { fameVestingAbi, iGasliteDropAbi } from "../wagmi/generated.js";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

const CHAIN_ID = Number(process.env.MULTISIG_CHAIN_ID ?? "0");
const MULTISIG_ADDRESS = process.env.MULTISIG_ADDRESS! as `0x${string}`;
const MULTISIG_PRIVATE_KEY = process.env.MULTISIG_PRIVATE_KEY! as `0x${string}`;
const MULTISIG_RPC = process.env.MULTISIG_RPC!;
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
const totalAirdrop = Array.from(holdersAirdrop.values()).reduce(
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

const encodeTransferToVesting = encodeFunctionData({
  abi: erc20Abi,
  functionName: "transfer",
  args: [FAME_VESTING_CONTRACT_ADDRESS, totalAllocation],
});

const encodedApproveFameToGaslite = encodeFunctionData({
  abi: erc20Abi,
  functionName: "approve",
  args: [GASLITE_DROP_ADDRESS, totalAirdrop],
});

const encodedAirdrop = encodeFunctionData({
  abi: iGasliteDropAbi,
  functionName: "airdropERC20",
  args: [
    FAME_ADDRESS,
    [...holdersAirdrop.keys()],
    [...holdersAirdrop.values()],
    totalAirdrop,
  ],
});

const safeTransactionData: MetaTransactionData[] = [
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
  {
    to: FAME_ADDRESS,
    value: "0",
    data: encodedApproveFameToGaslite,
  },
  {
    to: GASLITE_DROP_ADDRESS,
    value: "0",
    data: encodedAirdrop,
  },
];

const safeTransaction = await safe.createTransaction({
  transactions: safeTransactionData,
});

console.log("Transaction ready to be sent to the Safe");

// Deterministic hash based on transaction parameters
const safeTxHash = await safe.getTransactionHash(safeTransaction);

// Sign transaction to verify that the transaction is coming from owner 1
const senderSignature = await safe.signHash(safeTxHash);

const apiKit = new SafeApiKit.default({
  chainId: BigInt(CHAIN_ID),
});

await apiKit.proposeTransaction({
  safeAddress: MULTISIG_ADDRESS,
  safeTransactionData: safeTransaction.data,
  safeTxHash,
  senderAddress: privateKeyToAccount(MULTISIG_PRIVATE_KEY).address,
  senderSignature: senderSignature.data,
});

console.log("Transaction sent to the Safe");
