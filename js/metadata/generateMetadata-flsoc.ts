import path from "path";
import { promises as fs } from "fs";
import type { IMetadata } from "./metadata.js";
import {
  encodePacked,
  keccak256,
  createPublicClient,
  http,
  erc721Abi,
} from "viem";
import { mainnet } from "viem/chains";

const args = process.argv.slice(2);
let argIndex = 0;
let gateway = "https://gateway.irys.xyz/";
let cache: string = "./.metadata/fls-metadata-cache";

function handleFlags() {
  if (["--gateway"].includes(args[argIndex])) {
    gateway = args[argIndex + 1];
    argIndex += 2;
  }
  if (["--cache"].includes(args[argIndex])) {
    cache = args[argIndex + 1];
    argIndex += 2;
  }
}

// Call once per flag
handleFlags();
handleFlags();

const MANIFEST = args[argIndex++] ?? "./.metadata/fls-images-manifest.json";
const OUTPUT_DIR = args[argIndex++] ?? "./.metadata/fls-images-metadata/";

const client = createPublicClient({
  chain: mainnet,
  transport: http(process.env.MAINNET_RPC_URL),
});

await fs.mkdir(OUTPUT_DIR, { recursive: true });
await fs.mkdir(cache, { recursive: true });

// load the arweave manifest
const manifest = JSON.parse(await fs.readFile(MANIFEST, "utf-8")) as {
  manifest: "arweave/paths";
  version: "0.1.0";
  paths: Record<string, { id: string }>;
};

function idToUrl(id: string) {
  return `${gateway}${id}`;
}

async function getCache(tokenId: number) {
  const filePath = path.join(cache, `${tokenId}.json`);
  if (await fs.stat(filePath).catch(() => null)) {
    return JSON.parse(await fs.readFile(filePath, "utf-8")) as IMetadata;
  }
  return null;
}

const MAX_RETRIES = 30;
const INITIAL_BACKOFF = 1000;

async function fetchWithRetry<T>(
  fetchFn: () => Promise<T>,
  retries = 0
): Promise<T> {
  try {
    return await fetchFn();
  } catch (error) {
    // describe the error, assuming it is a fetch error
    if (error instanceof Error) {
      console.log(`Fetch failed with error: ${error.message}. Retrying...`);
    }
    if (retries >= MAX_RETRIES) throw error;
    const backoff = INITIAL_BACKOFF * Math.sqrt(retries + 1);
    console.log(`Retrying fetch in ${backoff}ms...`);
    await new Promise((resolve) => setTimeout(resolve, backoff));
    return fetchWithRetry(fetchFn, retries + 1);
  }
}

export async function fetchJson<T>({ cid }: { cid: string }): Promise<T> {
  return JSON.parse(new TextDecoder().decode(await fetchBuffer({ cid })));
}

export async function fetchBuffer({ cid }: { cid: string }): Promise<Buffer> {
  const url = new URL("http://localhost:5001/api/v0/cat");
  url.searchParams.append("arg", cid);

  const response = await fetch(url.toString(), {
    method: "POST",
  });

  if (!response.ok) {
    console.error(await response.text());
    throw new Error(
      `Failed to fetch content: ${response.status} - ${response.statusText}`
    );
  }
  return Buffer.from(await response.arrayBuffer());
}

for (const [arPath, { id }] of Object.entries(manifest.paths)) {
  const url = idToUrl(id);
  const tokenId = parseInt(arPath.split(".")[0]);
  const filePath = path.join(OUTPUT_DIR, `${tokenId}`);

  // console.log(`Processing token ${tokenId} with URL ${url}`);

  let metadata: IMetadata | null = await getCache(tokenId);
  if (!metadata) {
    const metadataUrl = await fetchWithRetry(() =>
      client.readContract({
        address: "0x6cf4328f1ea83b5d592474f9fcdc714faafd1574",
        abi: erc721Abi,
        functionName: "tokenURI",
        args: [BigInt(tokenId)],
      })
    );
    console.log(`Fetching ${metadataUrl}`);
    if (metadataUrl.startsWith("ipfs://")) {
      try {
        metadata = await fetchWithRetry(async () => {
          return await fetchJson<IMetadata>({
            cid: metadataUrl.replace("ipfs://", "/ipfs/"),
          });
        });

        await fs.writeFile(
          path.join(cache, `${tokenId}.json`),
          JSON.stringify(metadata, null, 2)
        );
      } catch (error) {
        if (error instanceof Error && error.name === "AbortError") {
          console.error(`Fetch timed out for token ${tokenId}`);
        } else {
          console.error(`Error fetching metadata for token ${tokenId}:`, error);
        }
        throw error;
      }
    } else {
      console.warn("We should not be here");
    }
    if (!metadata) {
      throw new Error(
        `No metadata found for token ${tokenId} with URL ${metadataUrl}`
      );
    }
  }

  const entry: IMetadata = {
    name: `Fame Lady #${tokenId}`,
    description:
      "Fame Lady Society is the wrapped token for the first ever generative all-female avatar collection on the Ethereum blockchain. Yes, we are THE community who took over a project TWICE to write our own story. This is NFT history. This is HERstory. FLS are 8888 distinctive Ladies made up of millions of fierce trait combinations. Community = Everything. Commercial IP rights of each Lady NFT belong to its owner.",
    image: url,
    id: tokenId.toString(),
    attributes: metadata.attributes,
  };

  await fs.writeFile(filePath, JSON.stringify(entry, null, 2));
}
