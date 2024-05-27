import "dotenv/config";
import { SafeFactory } from "@safe-global/protocol-kit";
import { JsonRpcProvider, Wallet, HDNodeWallet, Mnemonic } from "ethers";

const provider = new JsonRpcProvider(process.env.SEPOLIA_RPC, "sepolia");
// Generate 4 accounts
/** @type {HDNodeWallet[]} */
const accounts = [];
for (let i = 0; i < 4; i++) {
  accounts.push(
    HDNodeWallet.fromMnemonic(
      Mnemonic.fromPhrase(process.env.SEPOLIA_MNEMONIC),
      `m/44'/60'/0'/0/${i}`
    ).connect(provider)
  );
  console.log(`Address: ${accounts[i].address}`);
}

// console.log(`Deploying from ${accounts[0].address}`);
const [deployer, signer1, signer2, signer3] = accounts;
const safeFactory = await SafeFactory.init({
  provider: process.env.SEPOLIA_RPC,
  signer: deployer.privateKey,
});

/** @type {import('@safe-global/protocol-kit').SafeAccountConfig} */
const safeAccountConfig = {
  owners: [deployer.address, signer1.address, signer2.address, signer3.address],
  threshold: 2,
};

const protocolKitOwner1 = await safeFactory.deploySafe({ safeAccountConfig });

const safeAddress = await protocolKitOwner1.getAddress();
console.log("Your Safe has been deployed:");
console.log(`https://sepolia.etherscan.io/address/${safeAddress}`);
console.log(`https://app.safe.global/sep:${safeAddress}`);
