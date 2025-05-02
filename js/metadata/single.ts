import "dotenv/config";
import { promises as fs } from "fs";
import path from "path";
import { resolve as pathResolve } from "path";
import { formatEther } from "viem";
// import IPFS from "ipfs-only-hash";

import { calculateTotalPrice, getIrysArweave } from "./client.js";

const args = process.argv.slice(2);
const INPUT_FILE = pathResolve(args[0] || "./.metadata/staging/");

const client = await getIrysArweave();
const stat = await fs.stat(INPUT_FILE);

if (stat.isFile()) {
  const size = stat.size;

  const fee = BigInt((await client.getPrice(size)).toString());
  console.log(`Price estimate: ${formatEther(fee)}`);
  if ((await client.getLoadedBalance()) < fee) {
    console.info("Insufficient funds in wallet");
    await client.fund(fee - (await client.getLoadedBalance()));
  }
  console.log(`Funded wallet with ${formatEther(BigInt(fee))} ETH`);
  // const generateCID = async (content: string | object | Buffer | Uint8Array) => {
  //   return await IPFS.of(content);
  // };

  // const ONE_GIGABYTE = 1024 * 1024 * 1024;
  // console.log(
  //   `Price for 1 gigabyte: ${formatEther(await client.getPrice(ONE_GIGABYTE))}`
  // );

  const commonFileMappings: Record<string, string> = {
    png: "image/png",
    gif: "image/gif",
    mp4: "video/mp4",
    mp3: "audio/mpeg",
    wav: "audio/wav",
    ogg: "audio/ogg",
    webm: "video/webm",
    json: "application/json",
    jpeg: "image/jpeg",
    jpg: "image/jpeg",
    svg: "image/svg+xml",
    html: "text/html",
    js: "text/javascript",
    css: "text/css",
    txt: "text/plain",
    pdf: "application/pdf",
    doc: "application/msword",
    docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    xls: "application/vnd.ms-excel",
    xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  };

  client
    .uploadFile(INPUT_FILE, {
      ...(commonFileMappings[path.extname(INPUT_FILE).slice(1)] && {
        tags: [
          {
            name: "Content-Type",
            value: commonFileMappings[path.extname(INPUT_FILE).slice(1)],
          },
          {
            name: "Content-Disposition",
            value: `attachment; filename="${path.basename(INPUT_FILE)}"`,
          },
        ],
      }),
    })
    .then((tx) => {
      console.log(`Uploaded file to Arweave with transaction ID: ${tx?.id}`);
    })
    .catch((err) => {
      console.error("Error uploading file:", err);
    });
}
