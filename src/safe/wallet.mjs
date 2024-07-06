import { english, generateMnemonic, mnemonicToAccount } from "viem/accounts";

// Generate a new mnemonic
const mnemonic = generateMnemonic(english);
console.log(`Mnemonic: ${mnemonic}`);

for (let i = 0; i < 4; i++) {
  console.log(
    `Address: ${mnemonicToAccount(mnemonic, { path: `m/44'/60'/0'/0/${i}` }).address}`
  );
}
