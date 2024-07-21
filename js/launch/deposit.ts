import "dotenv/config";
import { privateKeyToAccount } from "viem/accounts";
import {
  Account,
  createPublicClient,
  createWalletClient,
  erc20Abi,
  formatUnits,
  http,
  parseEther,
} from "viem";
import { iSwapRouter02Abi, iwethAbi } from "../wagmi/generated.js";
import { sepolia, base } from "viem/chains";

const weth = process.env.WETH_ADDRESS! as `0x${string}`;
const amount = parseEther(process.env.SNIPE_AMOUNT! ?? "0.001");
const swapRouter = process.env.SWAP_ROUTER! as `0x${string}`;
const chain = process.env.CHAIN === "base" ? base : sepolia;
const snipeWallet = createWalletClient({
  transport: http(process.env.RPC),
  account: privateKeyToAccount(process.env.SNIPE_PRIVATE_KEY! as `0x${string}`),
  chain,
});

const publicClient = createPublicClient({
  transport: http(process.env.RPC),
  chain,
});

if (
  (await publicClient.readContract({
    abi: erc20Abi,
    address: weth,
    functionName: "balanceOf",
    args: [snipeWallet.account.address],
  })) < amount
) {
  await snipeWallet.writeContract({
    abi: iwethAbi,
    address: weth,
    functionName: "deposit",
    args: [],
    value: amount,
  });
  console.log("Deposited WETH");
}

// check allowance for swap router
const allowance = await publicClient.readContract({
  abi: erc20Abi,
  address: weth,
  functionName: "allowance",
  args: [snipeWallet.account.address, swapRouter],
});

if (allowance < amount) {
  await snipeWallet.writeContract({
    abi: erc20Abi,
    address: weth,
    functionName: "approve",
    args: [swapRouter, amount],
  });
  console.log("Approved WETH for swap router");
} else {
  console.log("No deposit necessary");
}
