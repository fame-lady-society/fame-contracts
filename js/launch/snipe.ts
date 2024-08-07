import "dotenv/config";
import { privateKeyToAccount } from "viem/accounts";
import {
  Account,
  createPublicClient,
  createWalletClient,
  erc20Abi,
  formatEther,
  formatUnits,
  http,
  parseEther,
} from "viem";
import { iSwapRouter02Abi, iwethAbi } from "../wagmi/generated.js";
import { sepolia, base } from "viem/chains";

const fameAddress = process.env.FAME_ADDRESS! as `0x${string}`;
const weth = process.env.WETH_ADDRESS! as `0x${string}`;
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

async function submitSwap(amount: bigint) {
  const params = {
    amountIn: amount,
    amountOutMinimum: 0n,
    fee: 3000,
    recipient: snipeWallet.account.address,
    sqrtPriceLimitX96: 0n,
    tokenIn: weth,
    tokenOut: fameAddress,
  };
  const { maxFeePerGas, maxPriorityFeePerGas } =
    await publicClient.estimateFeesPerGas();

  const gasEstimate = await publicClient.estimateContractGas({
    abi: iSwapRouter02Abi,
    address: swapRouter,
    functionName: "exactInputSingle",
    args: [params],
    account: snipeWallet.account,
    ...(maxPriorityFeePerGas && {
      maxPriorityFeePerGas: maxPriorityFeePerGas * 10n,
    }),
    ...(maxFeePerGas && { maxFeePerGas: maxFeePerGas * 10n }),
  });
  const receipt = await snipeWallet.writeContract({
    abi: iSwapRouter02Abi,
    address: swapRouter,
    functionName: "exactInputSingle",
    args: [params],
    gas: gasEstimate,
    ...(maxPriorityFeePerGas && {
      maxPriorityFeePerGas: maxPriorityFeePerGas * 10n,
    }),
    ...(maxFeePerGas && { maxFeePerGas: maxFeePerGas * 10n }),
  });

  console.log(`\nSubmitted: ${receipt}`);
  return receipt;
}

// get weth balance
const wethBalance = await publicClient.readContract({
  abi: erc20Abi,
  address: weth,
  functionName: "balanceOf",
  args: [snipeWallet.account.address],
});

console.log(`WETH balance: ${formatEther(wethBalance)}`);

let success = false;

do {
  try {
    process.stdout.write(".");
    console.log(`WETH balance: ${formatEther(wethBalance)}`);
    await publicClient.waitForTransactionReceipt({
      hash: await submitSwap(wethBalance),
      confirmations: 1,
    });
    success = true;
  } catch (error) {
    // console.error(error);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
} while (!success);

console.log("\ndone");
