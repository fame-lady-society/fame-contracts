import path from "path";
import { promises as fs } from "fs";
import type { IMetadata } from "./metadata.js";
import { encodePacked, keccak256 } from "viem";

const args = process.argv.slice(2);
let argIndex = 0;
let gateway = "https://gateway.irys.xyz/";

let salt = 0n;

function handleFlags() {
  if (["--gateway"].includes(args[argIndex])) {
    gateway = args[argIndex + 1];
    argIndex += 2;
  } else if (["--salt"].includes(args[argIndex])) {
    salt = BigInt(args[argIndex + 1]);
    argIndex += 2;
  }
}

// Call once per flag
handleFlags();
handleFlags();

const MANIFEST = args[argIndex++] ?? "./.metadata/staging-manifest.json";
const RECEIPT = args[argIndex++] ?? "./.metadata/staging-id.txt";
const OUTPUT_DIR = args[argIndex++] ?? "./.metadata/staging-metadata/";

await fs.mkdir(OUTPUT_DIR, { recursive: true });

const { id: txId } = JSON.parse(await fs.readFile(RECEIPT, "utf-8")) as {
  id: string;
};

// load the arweave manifest
const manifest = JSON.parse(await fs.readFile(MANIFEST, "utf-8")) as {
  manifest: "arweave/paths";
  version: "0.1.0";
  paths: Record<string, { id: string }>;
};

function idToUrl(id: string) {
  return `${gateway}${id}`;
}

// get all elements of manifest.paths
// - group by path
// - turn folders into a list of files

type ImageMetadata = {
  url: string;
};
type VideoMetadata = {
  url: string;
  video: string;
};
type FileMetadata = ImageMetadata | VideoMetadata;

const metadata: Record<string, FileMetadata> = {};
for (const [path, { id }] of Object.entries(manifest.paths)) {
  if (path.includes("/")) {
    // this is a folder, so we will create a VideoMetadata with the url and video, depending on what we found here
    const pathComponents = path.split("/");
    const rootDirectory = pathComponents[0];
    const fileName = pathComponents[1];
    const currentEntry: Partial<VideoMetadata> = metadata[rootDirectory] ?? {};
    if (fileName.endsWith("gif")) {
      currentEntry.url = idToUrl(id);
    } else if (fileName.endsWith("mp4")) {
      currentEntry.video = idToUrl(`${txId}/${path}`);
    }
    if (!currentEntry.url && !currentEntry.video) {
      console.log(`Skipping ${path}`);
      // hmmmm
      continue;
    }
    // note we assume that both the url and video field will be set
    // at some point
    metadata[rootDirectory] = currentEntry as VideoMetadata;
  } else {
    // this is a file, so we will create an ImageMetadata with the url
    metadata[path] = { url: idToUrl(id) };
  }
}

let i = 0n;
for (const [arPath, fileMetadata] of Object.entries(metadata)) {
  const entry: IMetadata = {
    name: "FAME Society",
    image: fileMetadata.url,
    description: `Experience the innovative $FAME token from the Fame Lady Society, a DN404 project seamlessly integrating ERC20 and ERC721 standards. Each $FAME token is part of a revolutionary system where owning multiples of 1 million $FAME automatically mints a rare and exclusive Society NFT to your wallet. These NFTs, backed by 1 million $FAME tokens each, merge the worlds of liquidity and ownership, offering both stability and exclusivity.

When you hold a Society NFT, you're not just an owner; you're part of a vibrant, empowering community dedicated to transparency, community governance, and women's empowerment in Web3. Selling any portion of the associated 1 million $FAME will cause the NFT to vanish, reflecting the unique balance of value and rarity within the Fame Lady Society ecosystem.

The Fame Lady Society, born from the pioneering all-female generative PFP project, continues to push boundaries by promoting true decentralization and sustainability. Fame Lady Society's mission is to transform Web3 into 'webWE,' ensuring every member has a voice in shaping the future. Join us in this exciting journey and redefine how NFTs and tokens can be traded and gamified.`,
  };

  if ("video" in fileMetadata) {
    entry.animation_url = fileMetadata.video;
  }

  const saltedPath = BigInt(
    keccak256(encodePacked(["uint256", "uint256"], [i++, salt]))
  ).toString();
  const filePath = path.join(OUTPUT_DIR, `${saltedPath}.json`);
  console.log(`Writing ${filePath}`);
  await fs.writeFile(filePath, JSON.stringify(entry, null, 2));
}
