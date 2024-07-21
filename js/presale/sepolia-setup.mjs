import "dotenv/config";
import { encodeFunctionData, parseUnits } from "viem";
import { sepolia } from "viem/chains";
import { mnemonicToAccount } from "viem/accounts";
import { MerkleTree } from "merkletreejs";
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { keccak256, toBytes, getAddress, toHex } from "viem";
import {} from "viem/actions";
import { fameSaleAbi } from "./abis.mjs";
import { promises as fs } from "fs";

const flsSnapshot = JSON.parse(
  await fs.readFile("./src/presale/fls-snapshot.json", "utf-8")
);

const RPC_URL = process.env.SEPOLIA_RPC;
const MNEMONIC = process.env.SEPOLIA_MNEMONIC;
const FAME_SALE_CONTRACT_ADDRESS = process.env.SEPOLIA_FAME_SALE;
const safeAddress = process.env.SEPOLIA_MULTISIG_ADDRESS;

/** @type {SafeApiKit} */
const apiKit = new SafeApiKit.default({
  chainId: BigInt(sepolia.id),
});

// Generate 4 accounts
/** @type {import('viem/accounts').HDAccount[]} */
const accounts = [];
for (let i = 0; i < 4; i++) {
  accounts.push(
    mnemonicToAccount(MNEMONIC, {
      path: `m/44'/60'/0'/0/${i}`,
    })
  );
  console.log(`Address: ${accounts[i].address}`);
}

const [deployer, signer1, signer2, signer3] = accounts;

const leaves = flsSnapshot.map((x) => toBytes(keccak256(getAddress(x))));
const tree = new MerkleTree(leaves, (x) => toBytes(keccak256(x)), {
  sort: true,
});
const root = `0x${tree.getRoot().toString("hex")}`;
console.log(`Root: ${root}`);

const maxBuyData = encodeFunctionData({
  abi: fameSaleAbi,
  functionName: "setMaxBuy",
  args: [parseUnits("0.1", 18)],
});
const maxRaiseData = encodeFunctionData({
  abi: fameSaleAbi,
  functionName: "setMaxRaise",
  args: [parseUnits("1", 18)],
});
const setMerkleRootData = encodeFunctionData({
  abi: fameSaleAbi,
  functionName: "setMerkleRoot",
  args: [root],
});

console.log(
  `All data ready to be sent to the Safe: ${FAME_SALE_CONTRACT_ADDRESS}`
);

/** @type {(import('@safe-global/safe-core-sdk-types').MetaTransactionData)[]} */
const safeTransactionData = [
  {
    to: FAME_SALE_CONTRACT_ADDRESS,
    data: maxBuyData,
    value: "0",
  },
  {
    to: FAME_SALE_CONTRACT_ADDRESS,
    data: maxRaiseData,
    value: "0",
  },
  {
    to: FAME_SALE_CONTRACT_ADDRESS,
    data: setMerkleRootData,
    value: "0",
  },
];

/** @type {Safe} */
const protocolKitOwner1 = await Safe.default.init({
  provider: RPC_URL,
  signer: toHex(deployer.getHdKey().privateKey),
  safeAddress,
});

const safeTransaction = await protocolKitOwner1.createTransaction({
  transactions: safeTransactionData,
});

console.log("Transaction ready to be sent to the Safe");

// Deterministic hash based on transaction parameters
const safeTxHash = await protocolKitOwner1.getTransactionHash(safeTransaction);

// Sign transaction to verify that the transaction is coming from owner 1
const senderSignature = await protocolKitOwner1.signHash(safeTxHash);

await apiKit.proposeTransaction({
  safeAddress,
  safeTransactionData: safeTransaction.data,
  safeTxHash,
  senderAddress: deployer.address,
  senderSignature: senderSignature.data,
});

/** @type {Safe} */
const protocolKitOwner2 = await Safe.default.init({
  provider: RPC_URL,
  signer: toHex(signer1.getHdKey().privateKey),
  safeAddress,
});

let pendingTransactions = (await apiKit.getPendingTransactions(safeAddress))
  .results;

const signature = await protocolKitOwner2.signHash(
  pendingTransactions[0].safeTxHash
);
await apiKit.confirmTransaction(safeTxHash, signature.data);
pendingTransactions = (await apiKit.getPendingTransactions(safeAddress))
  .results;
const executeTxResponse = await protocolKitOwner1.executeTransaction(
  pendingTransactions[0]
);
const receipt = await executeTxResponse.transactionResponse.wait();

console.log("Transaction executed:");
console.log(`https://sepolia.etherscan.io/tx/${receipt.transactionHash}`);
