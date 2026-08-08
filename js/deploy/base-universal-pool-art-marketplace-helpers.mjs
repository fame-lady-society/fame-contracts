import { isIP } from "node:net";

import { DeploymentNoGoError } from "./base-universal-pool-art-marketplace-state.mjs";

export const DEFAULT_MANIFEST =
  "script/manifests/base-universal-pool-art-marketplace-deployment.json";

const COMMAND_ARGUMENTS = new Map([
  ["prepare", { identifier: null, extra: 0 }],
  ["status", { identifier: null, extra: 0 }],
  ["reconcile", { identifier: null, extra: 0 }],
  ["advance", { identifier: null, extra: 0 }],
  ["replace", { identifier: "deployment step ID", extra: 0 }],
  ["prepare-operation", { identifier: "lifecycle operation kind", extra: 0 }],
  ["advance-operation", { identifier: "lifecycle operation ID", extra: 0 }],
  ["replace-operation", { identifier: "lifecycle operation ID", extra: 0 }],
  ["reconcile-operation", { identifier: "lifecycle operation ID", extra: 2 }],
]);

function noGo(message) {
  throw new DeploymentNoGoError(message);
}

function loopbackHostname(hostname) {
  const normalized = hostname
    .toLowerCase()
    .replace(/^\[|\]$/g, "")
    .replace(/\.$/, "");
  if (normalized === "localhost" || normalized.endsWith(".localhost")) return true;
  if (isIP(normalized) === 4) return normalized.startsWith("127.");
  if (isIP(normalized) !== 6) return false;
  if (normalized === "::1" || normalized === "0:0:0:0:0:0:0:1") return true;
  if (!normalized.startsWith("::ffff:")) return false;
  const mapped = normalized.slice("::ffff:".length);
  if (isIP(mapped) === 4) return mapped.startsWith("127.");
  return mapped.split(":")[0].padStart(4, "0").startsWith("7f");
}

export function assertRpcMode(mode, rpcUrl) {
  if (mode !== "production" && mode !== "fork-rehearsal") {
    noGo(`unsupported MARKETPLACE_DEPLOYMENT_MODE: ${mode}`);
  }
  let parsed;
  try {
    parsed = new URL(rpcUrl);
  } catch {
    noGo("RPC_URL must be an absolute HTTP or WebSocket URL");
  }
  if (!["http:", "https:", "ws:", "wss:"].includes(parsed.protocol)) {
    noGo("RPC_URL must be an absolute HTTP or WebSocket URL");
  }
  const hostname = parsed.hostname;
  const isLoopback = loopbackHostname(hostname);
  if (mode === "fork-rehearsal" && !isLoopback) {
    noGo("fork-rehearsal mode requires a loopback RPC URL");
  }
  if (mode === "production" && isLoopback) {
    noGo("production mode rejects loopback RPC URLs");
  }
}

function sanitizeErrorText(value) {
  return String(value)
    .replace(
      /(^|\n)\s*(?:Request body|Body):[\s\S]*?(?=\n\s*\n|$)/gi,
      "$1Request body: [redacted]",
    )
    .replace(/^\s*(?:Authorization|Proxy-Authorization):.*$/gim, "Authorization: [redacted]")
    .replace(/\b(?:https?|wss?):\/\/[^\s"'<>]+/gi, "[redacted-url]")
    .replace(/\bBearer\s+(?:Bearer\s+)?[^\s,;]+/gi, "Bearer [redacted]")
    .replace(
      /(\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|secret|private[_-]?key|mnemonic|raw[_-]?signed(?:[_-]?transaction)?)\b["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s&,;]+)/gi,
      "$1[redacted]",
    )
    .replace(/([?&][A-Za-z0-9_.~-]+)=([^\s&,;]+)/g, "$1=[redacted]");
}

function safeIdentifier(value, fallback) {
  if (typeof value !== "string") return fallback;
  const sanitized = value.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 80);
  return sanitized || fallback;
}

function errorDetails(error, seen) {
  if (error && typeof error === "object") {
    if (seen.has(error)) return { name: "Error", code: null, message: "circular error cause" };
    seen.add(error);
  }
  const name = safeIdentifier(error?.name, "Error");
  const rawCode = error?.code ?? (Number.isInteger(error?.status) ? `HTTP_${error.status}` : null);
  const code = rawCode == null ? null : safeIdentifier(String(rawCode), "UNKNOWN");
  const message = sanitizeErrorText(error instanceof Error ? error.message : String(error));
  const details = { name, code, message };
  if (error?.cause !== undefined && error.cause !== error) {
    details.cause = errorDetails(error.cause, seen);
  }
  return details;
}

export function deploymentErrorDetails(error) {
  return errorDetails(error, new Set());
}

export function deploymentErrorMessage(error) {
  const details = deploymentErrorDetails(error);
  const code = details.code ? `[${details.code}]` : "";
  const cause = details.cause
    ? `; caused by ${details.cause.name}${details.cause.code ? `[${details.cause.code}]` : ""}: ${details.cause.message}`
    : "";
  return `${details.name}${code}: ${details.message}${cause}`;
}

export function parseCommandArguments(command, postCommandArguments) {
  const grammar = COMMAND_ARGUMENTS.get(command);
  if (!grammar) noGo(`unsupported command: ${command}`);
  if (!grammar.identifier) {
    if (postCommandArguments.length > 1) noGo(`${command} accepts at most one manifest path`);
    return {
      manifestPath: postCommandArguments[0] ?? DEFAULT_MANIFEST,
      arguments: [],
    };
  }
  if (postCommandArguments.length === 0) {
    noGo(`${command} requires a ${grammar.identifier}`);
  }
  if (postCommandArguments.length === 1) {
    return { manifestPath: DEFAULT_MANIFEST, arguments: [postCommandArguments[0]] };
  }
  if (postCommandArguments.length > 2 + grammar.extra) {
    noGo(`${command} received too many arguments`);
  }
  return {
    manifestPath: postCommandArguments[0],
    arguments: postCommandArguments.slice(1),
  };
}
