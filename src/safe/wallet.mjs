import { english, generateMnemonic } from "viem/accounts";

// Generate a new mnemonic
const mnemonic = generateMnemonic(english);
console.log(`Mnemonic: ${mnemonic}`);
