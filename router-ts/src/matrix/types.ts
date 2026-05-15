import type { Address } from "viem";
import type { RouteCapabilities } from "../compiler/types.js";

export type ExecutionStatus = "executable" | "blocked" | "out-of-scope";

export interface GapMatrixRow {
  id: string;
  tokenIn: Address;
  tokenOut: Address;
  direction: string;
  supported: boolean;
  executable: ExecutionStatus;
  tsGenerated: boolean;
  forkTested: boolean;
  routeArtifactId: string | null;
  blocker: string | null;
  capabilities: RouteCapabilities;
}

export interface GapMatrixFile {
  schemaVersion: 1;
  pinnedBaseBlock: number;
  rows: GapMatrixRow[];
}
