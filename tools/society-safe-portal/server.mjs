import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "node:http";

const sourceDirectory = dirname(fileURLToPath(import.meta.url));
const root = resolve(sourceDirectory, "../../out/society-safe-portal");
const port = Number(process.env.SOCIETY_SAFE_PORT ?? 4173);

if (!Number.isInteger(port) || port < 1024 || port > 65_535) {
  throw new Error(
    "SOCIETY_SAFE_PORT must be an integer between 1024 and 65535",
  );
}

const contentTypes = Object.freeze({
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
});

const allowedFiles = new Map([
  ["/", "index.html"],
  ["/index.html", "index.html"],
  ["/app.js", "app.js"],
  ["/styles.css", "styles.css"],
]);

const server = createServer(async (request, response) => {
  const requestUrl = new URL(
    request.url ?? "/",
    `http://${request.headers.host ?? "127.0.0.1"}`,
  );
  const fileName = allowedFiles.get(requestUrl.pathname);
  if (!fileName || (request.method !== "GET" && request.method !== "HEAD")) {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found\n");
    return;
  }

  const path = resolve(root, fileName);
  try {
    const fileStat = await stat(path);
    response.writeHead(200, {
      "Cache-Control": "no-store",
      "Content-Length": fileStat.size,
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "Content-Type": contentTypes[extname(path)] ?? "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    });
    if (request.method === "HEAD") {
      response.end();
      return;
    }
    createReadStream(path).pipe(response);
  } catch {
    response.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
    response.end(
      "Portal build is missing. Run npm run society-safe:portal:build.\n",
    );
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Society Safe deployment portal: http://127.0.0.1:${port}`);
  console.log(
    "This server is bound to localhost only. Press Ctrl+C to stop it.",
  );
});
