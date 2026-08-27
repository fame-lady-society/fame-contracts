export function safeErrorMessage(error, envNames) {
  let message = String(error?.shortMessage ?? error?.message ?? error);
  for (const envName of envNames) {
    const secret = process.env[envName];
    if (secret) message = message.replaceAll(secret, `[redacted ${envName}]`);
  }
  return message.replace(/https?:\/\/[^\s"']+/gu, "[redacted RPC URL]");
}
