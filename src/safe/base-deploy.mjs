import "dotenv/config";
import { SafeFactory } from "@safe-global/protocol-kit";
import { HDNodeWallet, Mnemonic } from "ethers";

// Generate 4 accounts
/** @type {HDNodeWallet[]} */
const accounts = [];
for (let i = 0; i < 1; i++) {
  accounts.push(
    HDNodeWallet.fromMnemonic(
      Mnemonic.fromPhrase(process.env.BASE_MNEMONIC),
      `m/44'/60'/0'/0/${i}`
    )
  );
  console.log(`Address: ${accounts[i].address}`);
}

// console.log(`Deploying from ${accounts[0].address}`);
const [deployer] = accounts;
const safeFactory = await SafeFactory.init({
  provider: process.env.BASE_RPC,
  signer: deployer.privateKey,
});

/** @type {import('@safe-global/protocol-kit').SafeAccountConfig} */
const safeAccountConfig = {
  owners: [
    deployer.address,
    process.env.BASE_SIGNER1,
    process.env.BASE_SIGNER2,
  ],
  threshold: 2,
};

const protocolKitOwner1 = await safeFactory.deploySafe({ safeAccountConfig });

const safeAddress = await protocolKitOwner1.getAddress();
console.log("Your Safe has been deployed:");
console.log(`https://basescan.org/address/${safeAddress}`);
console.log(`https://app.safe.global/base:${safeAddress}`);
