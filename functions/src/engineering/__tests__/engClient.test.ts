import { safeErrorDetail, isSafePathSegment } from "../engClient";

/**
 * Builds the shape the Anthropic SDK's `APIError` actually has: the parsed
 * response body hangs off `.error`, and the envelope inside it is
 * `{ type: "error", error: { type, message } }` — hence `.error.error.type`.
 */
function apiError(status: number, body: unknown): Error & { status: number; error: unknown } {
  return Object.assign(new Error("400 " + JSON.stringify(body)), { status, error: body });
}

describe("safeErrorDetail", () => {
  it("reports the constructor name and status", () => {
    const detail = safeErrorDetail(apiError(400, {}));
    expect(detail.name).toBe("Error");
    expect(detail.status).toBe(400);
  });

  it("reports a known error type, which is what makes a 400 actionable", () => {
    // The case that motivated this: a 400 with no type reads identically
    // whether the cause is an empty balance, a wrong agent id, or an
    // unmountable repo.
    const detail = safeErrorDetail(
      apiError(400, {
        type: "error",
        error: { type: "invalid_request_error", message: "Your credit balance is too low" }
      })
    );
    expect(detail.errorType).toBe("invalid_request_error");
  });

  it("NEVER carries the error message, which can echo the rejected resource", () => {
    // A 400 from sessions.create can quote back the resource it rejected, and
    // that resource is where the founder's GitHub token lives.
    const TOKEN = "github_pat_11ABCDEF_secret";
    const detail = safeErrorDetail(
      apiError(400, {
        type: "error",
        error: { type: "invalid_request_error", message: `bad resource: ${TOKEN}` }
      })
    );
    expect(JSON.stringify(detail)).not.toContain(TOKEN);
    expect(JSON.stringify(detail)).not.toContain("bad resource");
  });

  it("drops an UNKNOWN error type rather than passing it through", () => {
    // The allowlist is the guard, not a shape check. If `type` ever stops
    // being a closed enum, a passthrough would log whatever the body put
    // there — including, in the worst case, echoed request content.
    const TOKEN = "github_pat_11ABCDEF_secret";
    const detail = safeErrorDetail(
      apiError(400, { type: "error", error: { type: `rejected: ${TOKEN}` } })
    );
    expect(detail.errorType).toBeUndefined();
    expect(JSON.stringify(detail)).not.toContain(TOKEN);
  });

  it("omits errorType entirely when the body has no envelope", () => {
    // Firestore and network errors go through this same function.
    const detail = safeErrorDetail(Object.assign(new Error("boom"), { code: 13 }));
    expect(detail.errorType).toBeUndefined();
    expect(detail).toEqual({ name: "Error" });
  });

  it("survives a non-object error without throwing", () => {
    expect(safeErrorDetail("just a string")).toEqual({});
    expect(safeErrorDetail(null)).toEqual({});
    expect(safeErrorDetail(undefined)).toEqual({});
  });

  it("ignores a non-string type", () => {
    const detail = safeErrorDetail(apiError(400, { type: "error", error: { type: { nested: 1 } } }));
    expect(detail.errorType).toBeUndefined();
  });
});

describe("isSafePathSegment", () => {
  it("accepts an ordinary id", () => {
    expect(isSafePathSegment("run_1")).toBe(true);
  });

  it("rejects a slash, which would silently redirect a Firestore path", () => {
    expect(isSafePathSegment("founder/../other")).toBe(false);
  });

  it("rejects Firestore's reserved __name__ form", () => {
    expect(isSafePathSegment("__reserved__")).toBe(false);
  });

  it("rejects the empty string", () => {
    expect(isSafePathSegment("")).toBe(false);
  });
});
