import "dotenv/config";
import { resolve as pathResolve } from "path";
import { formatEther, parseEther } from "viem";

import { calculateTotalPrice, getIrysArweave } from "./client.js";

const args = process.argv.slice(2);
const INPUT_FOLDER = pathResolve(args[0] || "./.metadata/staging/");

const client = await getIrysArweave();

const balance = await client.getLoadedBalance();
console.log(`Balance: ${formatEther(balance)}`);

const fee = await calculateTotalPrice(client, INPUT_FOLDER);
console.log(`Price estimate: ${formatEther(fee)}`);
// await client.fund(parseEther("0.0499"));
// console.log(`Funded wallet with ${formatEther(BigInt(fee))} ETH`);

const ONE_GIGABYTE = 1024 * 1024 * 1024;
console.log(
  `Price for 1 gigabyte: ${formatEther(await client.getPrice(ONE_GIGABYTE))}`
);

client
  .uploadFolder(INPUT_FOLDER, {
    keepDeleted: false,
    manifestTags: [
      { name: "Collection", value: "Fame Society" },
      { name: "Type", value: "Metadata" },
    ],
  })
  .then((tx) => {
    console.log(`Uploaded folder to Arweave with transaction ID: ${tx?.id}`);
  })
  .catch((err) => {
    console.error("Error uploading folder:", err);
  });
