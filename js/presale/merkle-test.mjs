import { MerkleTree } from "merkletreejs";
import { keccak256, toBytes, getAddress } from "viem";
import { promises as fs } from "fs";

const leaves = [
  "0x0000000000000000000000000000000000000111",
  "0x0000000000000000000000000000000000000112",
  "0x0000000000000000000000000000000000000113",
].map((x) => toBytes(keccak256(getAddress(x))));
const tree = new MerkleTree(leaves, (x) => toBytes(keccak256(x)), {
  sort: true,
});
const root = tree.getRoot().toString("hex");

const leaf1 = keccak256(
  getAddress("0x0000000000000000000000000000000000000111")
);
const leaf2 = keccak256(
  getAddress("0x0000000000000000000000000000000000000112")
);
const leaf3 = keccak256(
  getAddress("0x0000000000000000000000000000000000000113")
);

const proof1 = tree.getHexProof(leaf1);
const proof2 = tree.getHexProof(leaf2);
const proof3 = tree.getHexProof(leaf3);

console.log(`Root: 0x${root}`);
console.log(proof1);
console.log(proof2);
console.log(proof3);
// console.log(tree.toString());
