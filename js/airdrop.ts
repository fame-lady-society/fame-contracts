import { iGasliteDrop1155Abi } from "./wagmi/generated.js";
import {
  encodeFunctionData,
  isAddress,
  zeroAddress,
} from "viem";
import fs from "fs";

const holdersCsv = fs.readFileSync("./society-holders.csv", "utf-8");
const holders = new Set<`0x${string}`>();
for (const line of holdersCsv.split("\n")) {
  if (line === "") {
    continue;
  }
  const [raw] = line.split(",");
  const address = raw.trim().replace(/"/g, "");
  if (!isAddress(address) && address !== zeroAddress) {
    throw new Error(`Invalid address: ${address}`);
  }
  holders.add(address);
}

console.log(
  encodeFunctionData({
    abi: iGasliteDrop1155Abi,
    functionName: "airdropERC1155",
    args: [
      "0x379617D2d0aA34192117F20B856A29a2715aD5ce",
      [
        {
          tokenId: 4n,
          airdropAmounts: [
            {
              amount: 1n,
              recipients: Array.from(holders),
            },
          ],
        },
      ],
    ],
  })
);

console.log(holders.size);
