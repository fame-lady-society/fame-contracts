import "dotenv/config";
import { HDNodeWallet, Mnemonic } from "ethers";

// Generate 4 accounts
/** @type {HDNodeWallet[]} */
const accounts = [];
for (let i = 0; i < 4; i++) {
  accounts.push(
    HDNodeWallet.fromMnemonic(
      Mnemonic.fromPhrase(process.env.MNEMONIC),
      `m/44'/60'/0'/0/${i}`
    )
  );
  console.log(`Address: ${accounts[i].address}`);
  console.log(`Private Key: ${accounts[i].privateKey}`);
}
