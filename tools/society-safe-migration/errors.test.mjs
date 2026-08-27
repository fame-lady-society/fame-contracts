import assert from "node:assert/strict";
import test from "node:test";

import { safeErrorMessage } from "./errors.mjs";

test("redacts configured RPC URLs and provider tokens from errors", () => {
  const previous = process.env.TEST_MIGRATION_RPC_URL;
  process.env.TEST_MIGRATION_RPC_URL =
    "https://provider.example/v3/sentinel-secret-token";
  try {
    const message = safeErrorMessage(
      new Error(
        "request failed at https://provider.example/v3/sentinel-secret-token",
      ),
      ["TEST_MIGRATION_RPC_URL"],
    );
    assert.equal(message.includes("sentinel-secret-token"), false);
    assert.match(message, /redacted TEST_MIGRATION_RPC_URL/);
  } finally {
    if (previous === undefined) delete process.env.TEST_MIGRATION_RPC_URL;
    else process.env.TEST_MIGRATION_RPC_URL = previous;
  }
});
