import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const appSource = await readFile(new URL("./app.js", import.meta.url), "utf8");
const htmlSource = await readFile(
  new URL("./index.html", import.meta.url),
  "utf8",
);
const serverSource = await readFile(
  new URL("./server.mjs", import.meta.url),
  "utf8",
);
const rehearsalSource = await readFile(
  new URL("./fork-rehearsal.mjs", import.meta.url),
  "utf8",
);

test("portal has no key ingestion or editable deployment parameters", () => {
  assert.doesNotMatch(appSource, /privateKey|mnemonic|seed phrase/i);
  assert.doesNotMatch(htmlSource, /private.?key|mnemonic|seed phrase/i);
  assert.doesNotMatch(
    htmlSource,
    /name=["'](?:factory|singleton|salt|owner|threshold)/i,
  );
  assert.match(htmlSource, /autocomplete="off"/);
});

test("portal exposes exactly the two reviewed broadcast calls", () => {
  assert.equal(appSource.match(/\.sendTransaction\(\{/g)?.length, 2);
  assert.match(appSource, /to: SAFE_MANIFEST\.safe\.factory/);
  assert.match(appSource, /to: SAFE_MANIFEST\.safe\.predictedAddress/);
  assert.match(appSource, /validateDeploymentEvents/);
  assert.doesNotMatch(appSource, /sendRawTransaction|eth_sendRawTransaction/);
  assert.doesNotMatch(appSource, /createChainSpecificProxyWithNonce/);
});

test("server is localhost-only and sends restrictive browser headers", () => {
  assert.match(serverSource, /server\.listen\(port, "127\.0\.0\.1"/);
  assert.match(serverSource, /Content-Security-Policy/);
  assert.match(serverSource, /frame-ancestors 'none'/);
  assert.match(serverSource, /Cache-Control": "no-store"/);
  assert.match(serverSource, /X-Frame-Options": "DENY"/);
});

test("fork rehearsal sends writes only through loopback Anvil", () => {
  assert.match(
    rehearsalSource,
    /const LOCAL_RPC_URL = "http:\/\/127\.0\.0\.1:18545"/,
  );
  assert.match(rehearsalSource, /const transport = http\(LOCAL_RPC_URL/);
  assert.match(rehearsalSource, /--fork-url/);
  assert.doesNotMatch(
    rehearsalSource,
    /createWalletClient\(\{[^}]*process\.env/s,
  );
});
