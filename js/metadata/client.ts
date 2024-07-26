import "dotenv/config";
import path from "path";
import { promises as fs } from "fs";
import Irys from "@irys/sdk";

const NETWORK = process.env.ARWEAVE_NETWORK || "mainnet";
const TOKEN = process.env.ARWEAVE_TOKEN || "base-eth";
const PRIVATE_KEY = process.env.ARWEAVE_PRIVATE_KEY || "";
const RPC = process.env.ARWEAVE_RPC;

export const getIrysArweave = async () => {
  console.log(`Connecting to Arweave network: ${NETWORK} paid with ${TOKEN}`);
  const irys = new Irys({
    network: NETWORK,
    token: TOKEN,
    key: PRIVATE_KEY,
    config: { providerUrl: RPC },
  });
  return irys;
};

export const calculateTotalPrice = async (
  irys: Irys,
  folderPath: string
): Promise<bigint> => {
  let totalPrice = 0n;

  const processFileOrFolder = async (itemPath: string): Promise<void> => {
    const stat = await fs.stat(itemPath);

    if (stat.isFile()) {
      const size = stat.size;
      const price = BigInt((await irys.getPrice(size)).toString());
      totalPrice += price;
    } else if (stat.isDirectory()) {
      const files = await fs.readdir(itemPath);
      for (const file of files) {
        await processFileOrFolder(path.join(itemPath, file));
      }
    }
  };

  await processFileOrFolder(folderPath);
  return totalPrice;
};
