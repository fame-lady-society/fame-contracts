import "dotenv/config";
import { HDNodeWallet, Mnemonic } from "ethers";
import { mnemonicToAccount } from "viem/accounts";

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

const account = mnemonicToAccount(process.env.MNEMONIC, {
  path: `m/44'/60'/0'/0/0`,
});
console.log(`Address: ${account.address}`);

const personalMessage =
  "I am me@0xflick.xyz and I deployed 0x3e2cab55bEbF41719148b4e6b63F6644B18AE49c which was a DN404 contract that deployed 0xbb5ed04dd7b207592429eb8d599d103ccad646c4";

const signature = await account.signMessage({
  message: personalMessage,
});

console.log(`Signature: ${signature}`);
