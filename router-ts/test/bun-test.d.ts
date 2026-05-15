declare module "bun:test" {
  type TestCallback = () => void | Promise<void>;

  interface Matchers<T> {
    not: Matchers<T>;
    toBe(expected: T): void;
    toEqual(expected: unknown): void;
    toHaveLength(expected: number): void;
    toMatchObject(expected: object): void;
    toMatch(expected: RegExp): void;
    toContain(expected: unknown): void;
    toBeGreaterThan(expected: number | bigint): void;
    toBeGreaterThanOrEqual(expected: number | bigint): void;
  }

  export function describe(name: string, callback: TestCallback): void;
  export function test(name: string, callback: TestCallback): void;
  export function expect<T>(actual: T): Matchers<T>;
}
