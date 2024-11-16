import "dotenv/config";
import { HDNodeWallet, Mnemonic } from "ethers";
import { mnemonicToAccount } from "viem/accounts";

// Generate 4 accounts
/** @type {HDNodeWallet[]} */
const accounts = [];
for (let i = 0; i < 25; i++) {
  accounts.push(
    HDNodeWallet.fromMnemonic(
      Mnemonic.fromPhrase(process.env.MNEMONIC),
      `m/44'/60'/0'/0/${i}`
    )
  );
  console.log(`Address: ${accounts[i].address}`);
  // console.log(`Private Key: ${accounts[i].privateKey}`);
}

const account = mnemonicToAccount(process.env.MNEMONIC, {
  path: `m/44'/60'/0'/0/0`,
});
console.log(`Address: ${account.address}`);

console.log(JSON.stringify(accounts.map((a) => a.address)));
