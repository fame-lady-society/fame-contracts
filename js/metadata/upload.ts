import "dotenv/config";
import { resolve as pathResolve } from "path";
import { formatEther } from "viem";
// import IPFS from "ipfs-only-hash";

import { calculateTotalPrice, getIrysArweave } from "./client.js";

const args = process.argv.slice(2);
const INPUT_FOLDER = pathResolve(args[0] || "./.metadata/staging/");

const client = await getIrysArweave();

const fee = await calculateTotalPrice(client, INPUT_FOLDER);
console.log(`Price estimate: ${formatEther(fee)}`);
await client.fund((fee * 3n) / 2n);
console.log(`Funded wallet with ${formatEther(BigInt(fee))} ETH`);
// const generateCID = async (content: string | object | Buffer | Uint8Array) => {
//   return await IPFS.of(content);
// };

// const ONE_GIGABYTE = 1024 * 1024 * 1024;
// console.log(
//   `Price for 1 gigabyte: ${formatEther(await client.getPrice(ONE_GIGABYTE))}`
// );

client.uploadFolder(INPUT_FOLDER, {}).then((tx) => {
  console.log(`Uploaded folder to Arweave with transaction ID: ${tx?.id}`);
});
