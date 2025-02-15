import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";
import { mainnet } from "viem/chains";

export default defineConfig({
  out: "js/wagmi/generated.ts",
  contracts: [],
  plugins: [
    foundry({
      include: [
        "FameSale.sol/**",
        "FameSaleToken.sol/**",
        "FameLaunch.sol/**",
        "ISwapRouter02.sol/**",
        "IWETH.sol/**",
        "IGasliteDrop.sol/**",
        "IGasliteDrop1155.sol/**",
        "FameVesting.sol/**",
        "ClaimToFame.sol/**",
        "Fame.sol/**",
      ],
    }),
  ],
});
