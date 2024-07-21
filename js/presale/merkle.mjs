import { MerkleTree } from "merkletreejs";
import { keccak256, toBytes, getAddress } from "viem";
import { promises as fs } from "fs";

const flsSnapshot = JSON.parse(
  await fs.readFile("./src/presale/fls-snapshot.json", "utf-8")
);

const leaves = flsSnapshot.map((x) => toBytes(keccak256(getAddress(x))));
const tree = new MerkleTree(leaves, (x) => toBytes(keccak256(x)), {
  sort: true,
});
const root = tree.getRoot().toString("hex");

// const leaf = keccak256(toHex("0x1318454B32ea883dB5a729eA59783d9fAfA74908"));
// const proof = tree.getProof(leaf);

console.log(`Root: 0x${root}`);
// console.log(tree.toString());
