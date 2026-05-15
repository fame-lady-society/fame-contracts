import { describe, expect, test } from "bun:test";
import { generateOutputs } from "../src/artifacts/writeArtifacts.js";

describe("route hash artifacts", () => {
  test("generation is deterministic", () => {
    const first = generateOutputs();
    const second = generateOutputs();

    expect(first.solverRoutesJson).toBe(second.solverRoutesJson);
    expect(first.gapMatrixJson).toBe(second.gapMatrixJson);
    expect(first.parityVectorsJson).toBe(second.parityVectorsJson);
  });

  test("every generated route has ABI bytes and a route hash", () => {
    const outputs = generateOutputs();
    expect(outputs.routeArtifacts.length).toBeGreaterThanOrEqual(4);
    for (const artifact of outputs.routeArtifacts) {
      expect(artifact.abiEncodedRoute.startsWith("0x")).toBe(true);
      expect(artifact.routeHash).toMatch(/^0x[0-9a-f]{64}$/);
      expect(artifact.route.legs.length).toBeGreaterThan(0);
    }
  });
});
