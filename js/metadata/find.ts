import { promises as fs } from "fs";
import { createPublicClient, http, erc721Abi } from "viem";
import { sepolia } from "viem/chains";
import { IMetadata } from "./metadata.js";

const data: unknown[] = [];
const FAME_NFT_ADDRESS = process.env.FAME_NFT_ADDRESS! as `0x${string}`;
const RPC = process.env.RPC!;
const client = createPublicClient({
  transport: http(RPC),
  chain: sepolia,
});

for (let i = 1n; i <= 100n; i++) {
  console.log(`Checking token ${i}`);
  const uri = await client.readContract({
    abi: erc721Abi,
    functionName: "tokenURI",
    address: FAME_NFT_ADDRESS,
    args: [i],
  });
  const response = await fetch(uri);
  const str = await response.text();
  const metadata: IMetadata = JSON.parse(str);
  data.push(metadata);
  if (metadata.animation_url || str.includes(".mp4")) {
    console.log(`Token ${i} has an animation URL`);
    console.log(metadata.animation_url);
  }
}

await fs.writeFile("./metadata.json", JSON.stringify(data, null, 2));
