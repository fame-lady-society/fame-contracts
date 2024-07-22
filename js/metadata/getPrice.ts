import "dotenv/config";
import { formatEther } from "viem";
import { getIrysArweave } from "./client.js";

const client = await getIrysArweave();

const ONE_GIGABYTE = 1024 * 1024 * 1024;
console.log(
  `Price for 1 gigabyte: ${formatEther(await client.getPrice(ONE_GIGABYTE))}`
);
