import "dotenv/config";
import Irys from "@irys/sdk";
import { formatEther } from "viem";

const NETWORK = process.env.ARWEAVE_NETWORK || "mainnet";
const TOKEN = process.env.ARWEAVE_TOKEN || "base-eth";
const PRIVATE_KEY = process.env.ARWEAVE_PRIVATE_KEY || "";
const RPC = process.env.ARWEAVE_RPC;

export const getIrysArweave = async () => {
  const irys = new Irys({
    network: NETWORK,
    token: TOKEN,
    key: PRIVATE_KEY,
    config: { providerUrl: RPC },
  });
  return irys;
};
