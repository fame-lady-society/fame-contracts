import assert from "node:assert/strict";
import test from "node:test";

import { resolveSafeSnapshot } from "./safe-state.mjs";

test("an already-deployed Safe is fully read before classification", async () => {
  const deployedCode = "0x60016000";
  const completeSnapshot = {
    code: deployedCode,
    owners: ["0x0000000000000000000000000000000000000001"],
  };
  const reads = [];

  const snapshot = await resolveSafeSnapshot(deployedCode, async (code) => {
    reads.push(code);
    return completeSnapshot;
  });

  assert.deepEqual(reads, [deployedCode]);
  assert.equal(snapshot, completeSnapshot);
});

test("an empty destination does not attempt Safe contract reads", async () => {
  let readAttempted = false;

  const snapshot = await resolveSafeSnapshot("0x", async () => {
    readAttempted = true;
    throw new Error("should not read an undeployed Safe");
  });

  assert.equal(readAttempted, false);
  assert.deepEqual(snapshot, { code: "0x" });
});
