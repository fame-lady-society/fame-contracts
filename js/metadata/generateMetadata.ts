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
  metadata[path.split(".")[0]] = { url: idToUrl(id) };
}

let i = 0n;
for (const [arPath, fileMetadata] of Object.entries(metadata)) {
  const index = ++i;

  const entry: IMetadata = {
    name: `Lingerie Dreams ${index}`,
    id: Number(index),
    image: fileMetadata.url,
    description: `"Lingerie Dreams" is the follow up smash hit to FameOrDie's first release "MollyGirl"  It's a love story about 2 girls that lived in gay Disco's and danced their night's away in Lingerie and the sexual escapades that ensued 💋💋💋 `,
  };

  entry.animation_url = `https://node1.irys.xyz/GoP3PCu0tyB8w1PQjiT52-CQGyPafM-1uYY2BZwrgbs/?hash=${arPath}`;

  const saltedPath = index.toString();
  const filePath = path.join(OUTPUT_DIR, `${saltedPath}`);
  console.log(`Writing ${filePath}`);
  await fs.writeFile(filePath, JSON.stringify(entry, null, 2));
}
