import { describe, expect, test } from "bun:test";
import { loadSupportedBasePools } from "../src/config/base.js";

describe("router-ts tooling", () => {
  test("loads checked-in pool fixtures without RPC environment", () => {
    const original = process.env.BASE_RPC;
    delete process.env.BASE_RPC;
    const config = loadSupportedBasePools();
    process.env.BASE_RPC = original;

    expect(config.pools).toHaveLength(20);
  });
});
