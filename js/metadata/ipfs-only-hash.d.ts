// ipfs-only-hash.d.ts

declare module "ipfs-only-hash" {
  /**
   * Generates a Content Identifier (CID) for the given content.
   * @param content The content to generate a CID for. Can be a string, Buffer, or other supported types.
   * @returns A promise that resolves to a string representing the CID of the content.
   */
  export function of(
    content: string | Buffer | Uint8Array | object
  ): Promise<string>;
}
