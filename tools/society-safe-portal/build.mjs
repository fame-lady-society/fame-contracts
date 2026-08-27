import { copyFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

const sourceDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(sourceDirectory, "../..");
const outputDirectory = resolve(repositoryRoot, "out/society-safe-portal");

await mkdir(outputDirectory, { recursive: true });
await build({
  entryPoints: [resolve(sourceDirectory, "app.js")],
  outfile: resolve(outputDirectory, "app.js"),
  bundle: true,
  format: "esm",
  platform: "browser",
  target: ["es2022"],
  loader: { ".txt": "text" },
  legalComments: "none",
  minify: false,
  sourcemap: false,
});
await Promise.all([
  copyFile(
    resolve(sourceDirectory, "index.html"),
    resolve(outputDirectory, "index.html"),
  ),
  copyFile(
    resolve(sourceDirectory, "styles.css"),
    resolve(outputDirectory, "styles.css"),
  ),
]);

console.log(`Built local Society Safe portal at ${outputDirectory}`);
