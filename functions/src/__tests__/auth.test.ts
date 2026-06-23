import { extractBearerToken } from "../auth";

describe("extractBearerToken", () => {
  test("returns token from Bearer header", () => {
    expect(extractBearerToken("Bearer abc.def.ghi")).toBe("abc.def.ghi");
  });

  test("returns null for missing header", () => {
    expect(extractBearerToken(undefined)).toBeNull();
  });

  test("returns null for non-Bearer scheme", () => {
    expect(extractBearerToken("Basic abc")).toBeNull();
  });

  test("returns null for empty token", () => {
    expect(extractBearerToken("Bearer ")).toBeNull();
  });
});
