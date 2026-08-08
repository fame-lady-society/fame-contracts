import { randomUUID } from "node:crypto";
import { open, rename, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";

export async function writeJsonAtomic(path, value) {
  const target = resolve(path);
  const directory = dirname(target);
  const temporaryPath = join(directory, `.${basename(target)}.${process.pid}.${randomUUID()}.tmp`);
  let temporaryHandle;
  let directoryHandle;
  try {
    await writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: "utf8",
      mode: 0o600,
      flag: "wx",
    });
    temporaryHandle = await open(temporaryPath, "r");
    await temporaryHandle.sync();
    await temporaryHandle.close();
    temporaryHandle = undefined;
    await rename(temporaryPath, target);
    directoryHandle = await open(directory, "r");
    await directoryHandle.sync();
    await directoryHandle.close();
    directoryHandle = undefined;
  } catch (error) {
    if (temporaryHandle) await temporaryHandle.close();
    if (directoryHandle) await directoryHandle.close();
    await unlink(temporaryPath).catch(() => {});
    throw error;
  }
}
