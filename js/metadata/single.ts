import "dotenv/config";
import { promises as fs } from "fs";
import { resolve as pathResolve } from "path";
import { formatEther } from "viem";
// import IPFS from "ipfs-only-hash";

import { calculateTotalPrice, getIrysArweave } from "./client.js";

const args = process.argv.slice(2);
const INPUT_FILE = pathResolve(args[0] || "./.metadata/staging/");

const client = await getIrysArweave();
const stat = await fs.stat(INPUT_FILE);

if (stat.isFile()) {
  const size = stat.size;

  const fee = BigInt((await client.getPrice(size)).toString());
  console.log(`Price estimate: ${formatEther(fee)}`);
  if ((await client.getLoadedBalance()) < fee) {
    console.info("Insufficient funds in wallet");
    await client.fund(fee - (await client.getLoadedBalance()));
  }
  console.log(`Funded wallet with ${formatEther(BigInt(fee))} ETH`);
  // const generateCID = async (content: string | object | Buffer | Uint8Array) => {
  //   return await IPFS.of(content);
  // };

  // const ONE_GIGABYTE = 1024 * 1024 * 1024;
  // console.log(
  //   `Price for 1 gigabyte: ${formatEther(await client.getPrice(ONE_GIGABYTE))}`
  // );

  client
    .uploadFile(INPUT_FILE)
    .then((tx) => {
      console.log(`Uploaded file to Arweave with transaction ID: ${tx?.id}`);
    })
    .catch((err) => {
      console.error("Error uploading file:", err);
    });
}
