import "dotenv/config";
import FameSale from "../../out/FameSale.sol/FameSale.json";
import { createWalletClient, http } from "viem";
import { sepolia } from "viem/chains";
import { mnemonicToAccount } from "viem/accounts";
import { waitForTransactionReceipt } from "viem/actions";

const account = mnemonicToAccount(
  process.env.SEPOLIA_MNEMONIC,
  `m/44'/60'/0'/0/0`
);

const wallet = createWalletClient({
  transport: http(process.env.SEPOLIA_RPC),
  account,
  chain: sepolia,
});

const hash = await wallet.deployContract({
  abi: FameSale.abi,
  bytecode: FameSale.bytecode.object,
});

console.log(`Contract deployment hash: ${hash}`);

const receipt = await waitForTransactionReceipt(wallet, {
  hash,
});

console.log(`Contract deployed at: ${receipt.contractAddress}`);
