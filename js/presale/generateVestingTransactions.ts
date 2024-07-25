import {
  encodeFunctionData,
  createPublicClient,
  parseEther,
  formatEther,
  isAddress,
} from "viem";
import fs from "fs";
import { fameVestingAbi } from "../wagmi/generated.js";

const RPC_URL = process.env.RPC;
const FAME_RPC_URL = process.env.FAME_RPC_URL ?? RPC_URL;
const FAME_ADDRESS = process.env.FAME_ADDRESS;
const PRESALE_MAX = parseEther(process.env.PRESALE_MAX ?? "6");
const INPUT_FILE = process.env.INPUT_FILE ?? "holders.csv";
const PRESALE_ALLOCATION = parseEther(
  process.env.PRESALE_ALLOCATION ?? "176000000"
);
const holdersCsv = fs.readFileSync(INPUT_FILE, "utf-8");
const holders = new Map<`0x${string}`, bigint>();
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
    holders.set(address, presaleHoldingToAllocation(parseEther(amount)));
  });

let totalAllocation = Array.from(holders.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);

// Find any delta between the total allocation and the presale allocation and
// Adjust the first holder to make up the difference
const delta = totalAllocation - PRESALE_ALLOCATION;
const firstKey = holders.keys().next().value as `0x${string}`;
if (delta > 0) {
  const firstHolder = holders.get(firstKey);
  holders.set(firstKey, firstHolder! + delta);
} else if (delta < 0) {
  const firstHolder = holders.get(firstKey);
  holders.set(firstKey, firstHolder! - delta);
}
totalAllocation = Array.from(holders.values()).reduce(
  (a, b) => a + b,
  BigInt(0)
);
console.log(`Total allocation: ${formatEther(totalAllocation)}`);

// const FAME_VESTING_CONTRACT_ADDRESS = process.env.FAME_VESTING_CONTRACT_ADDRESS;

// Some starter values
const start = BigInt(Math.floor(Date.now() / 1000));
const cliff = 0n;
// 3 months in seconds
const duration = 60n * 60n * 24n * 30n * 3n;
const slicePeriodSeconds = 1n;

const transactionData = Array.from(holders.entries()).map(([address, amount]) =>
  encodeFunctionData({
    abi: fameVestingAbi,
    functionName: "createVestingSchedule",
    args: [address, start, cliff, duration, slicePeriodSeconds, true, amount],
  })
);

console.log(`Generated ${transactionData.length} transactions`);
console.log(transactionData.join("\n"));
