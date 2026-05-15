import { describe, expect, test } from "bun:test";
import { encodeAbiParameters } from "viem";
import { encodeSolidlyPayload } from "../src/adapters/solidly.js";
import { encodeSlipstreamPayload } from "../src/adapters/slipstream.js";
import { encodeUniswapV2Payload } from "../src/adapters/uniswapV2.js";
import { encodeV3Path, encodeUniversalRouterV3Payload } from "../src/adapters/universalRouterV3.js";
import { encodeUniversalRouterV4Payload, v4HookDataKey } from "../src/adapters/universalRouterV4.js";
import { BASEDFLICK, FAME, USDC, WETH, ZORA } from "../src/config/tokens.js";

describe("venue payload encoders", () => {
  test("encodes Uniswap V2 path payload", () => {
    const payload = encodeUniswapV2Payload([WETH, FAME], 123n);
    const expected = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "path", type: "address[]" },
            { name: "deadline", type: "uint256" }
          ]
        }
      ],
      [{ path: [WETH, FAME], deadline: 123n }]
    );
    expect(payload).toBe(expected);
  });

  test("encodes Solidly route payload", () => {
    const payload = encodeSolidlyPayload([{ from: USDC, to: FAME, stable: false }], 123n);
    expect(payload.startsWith("0x")).toBe(true);
  });

  test("encodes Slipstream exact-input-single payload", () => {
    const payload = encodeSlipstreamPayload({
      router: "0xbe6d8f0d05cc4be24d5167a3ef062215be6d18a5",
      factory: "0x5e7bb104d84c7cb9b682aac2f3d509f5f406809a",
      tokenIn: BASEDFLICK,
      tokenOut: FAME,
      tickSpacing: 2000,
      sqrtPriceLimitX96: 0n,
      deadline: 123n
    });
    expect(payload.startsWith("0x")).toBe(true);
  });

  test("encodes V3 packed path", () => {
    expect(encodeV3Path(USDC, 3000, ZORA)).toBe(
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913000bb81111111111166b7fe7bd91427724b487980afc69"
    );
  });

  test("encodes V3 and V4 Universal Router structured payloads", () => {
    const v3 = encodeUniversalRouterV3Payload({
      tokenIn: USDC,
      tokenOut: ZORA,
      fee: 3000,
      deadline: 123n,
      recipient: "0x0000000000000000000000000000000000001003"
    });
    const v4 = encodeUniversalRouterV4Payload({
      tokenIn: BASEDFLICK,
      tokenOut: ZORA,
      amountIn: 1n,
      minAmountOut: 1n,
      currency0: ZORA,
      currency1: BASEDFLICK,
      fee: 30000,
      tickSpacing: 200,
      hooks: "0xd61a675f8a0c67a73dc3b54fb7318b4d91409040",
      hookData: "0x1234",
      deadline: 123n,
      recipient: "0x0000000000000000000000000000000000001003"
    });

    expect(v3.startsWith("0x")).toBe(true);
    expect(v4.startsWith("0x")).toBe(true);
    expect(v4HookDataKey({
      currency0: ZORA,
      currency1: BASEDFLICK,
      fee: 30000,
      tickSpacing: 200,
      hooks: "0xd61a675f8a0c67a73dc3b54fb7318b4d91409040",
      hookData: "0x1234"
    }).startsWith("0x")).toBe(true);
  });
});
