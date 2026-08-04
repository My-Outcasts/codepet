import {
  signState,
  verifyState,
  buildAuthorizeUrl,
  sealToken,
  openToken,
  exchangeCode,
  STATE_TTL_MS,
  GITHUB_SCOPES
} from "../oauth/githubOAuthCore";

const SECRET = Buffer.alloc(32, 7).toString("base64");

describe("state", () => {
  it("round-trips the uid it was minted for", () => {
    const s = signState("uid-123", SECRET);
    expect(verifyState(s, SECRET)?.uid).toBe("uid-123");
  });

  it("rejects a state signed with a different secret", () => {
    const s = signState("uid-123", SECRET);
    expect(verifyState(s, Buffer.alloc(32, 9).toString("base64"))).toBeNull();
  });

  it("rejects a tampered payload — the uid cannot be swapped", () => {
    const s = signState("uid-123", SECRET);
    const [, mac] = s.split(".");
    const forged = Buffer.from(JSON.stringify({ uid: "attacker", nonce: "x", exp: Date.now() + 1000 }))
      .toString("base64")
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");
    expect(verifyState(`${forged}.${mac}`, SECRET)).toBeNull();
  });

  it("expires", () => {
    const now = Date.now();
    const s = signState("uid-123", SECRET, now);
    expect(verifyState(s, SECRET, now + STATE_TTL_MS - 1)).not.toBeNull();
    expect(verifyState(s, SECRET, now + STATE_TTL_MS + 1)).toBeNull();
  });

  it("is single-use in shape — two mints never collide", () => {
    expect(signState("uid-123", SECRET)).not.toBe(signState("uid-123", SECRET));
  });

  it.each(["", "nodot", "a.b.c", "!!.??"])("rejects malformed state %p", (bad) => {
    expect(verifyState(bad, SECRET)).toBeNull();
  });

  // timingSafeEqual throws on a length mismatch, so a short mac must be rejected
  // by the length guard rather than blowing up the callback.
  it("rejects a truncated signature without throwing", () => {
    const s = signState("uid-123", SECRET);
    const [body] = s.split(".");
    expect(() => verifyState(`${body}.AAAA`, SECRET)).not.toThrow();
    expect(verifyState(`${body}.AAAA`, SECRET)).toBeNull();
  });
});

describe("authorize url", () => {
  it("carries the client id, redirect, scopes and state", () => {
    const url = new URL(buildAuthorizeUrl("cid", "https://cb.example/x", "st"));
    expect(url.origin + url.pathname).toBe("https://github.com/login/oauth/authorize");
    expect(url.searchParams.get("client_id")).toBe("cid");
    expect(url.searchParams.get("redirect_uri")).toBe("https://cb.example/x");
    expect(url.searchParams.get("state")).toBe("st");
    expect(url.searchParams.get("scope")).toBe(GITHUB_SCOPES.join(" "));
  });
});

describe("token at rest", () => {
  it("round-trips", () => {
    expect(openToken(sealToken("gho_secret", SECRET), SECRET)).toBe("gho_secret");
  });

  it("never stores the plaintext", () => {
    const sealed = sealToken("gho_secret", SECRET);
    expect(JSON.stringify(sealed)).not.toContain("gho_secret");
  });

  it("uses a fresh iv, so the same token seals differently each time", () => {
    expect(sealToken("gho_secret", SECRET).ciphertext).not.toBe(
      sealToken("gho_secret", SECRET).ciphertext
    );
  });

  it("fails closed on a tampered ciphertext rather than returning garbage", () => {
    const sealed = sealToken("gho_secret", SECRET);
    const bytes = Buffer.from(sealed.ciphertext, "base64");
    bytes[0] ^= 0xff;
    expect(() => openToken({ ...sealed, ciphertext: bytes.toString("base64") }, SECRET)).toThrow();
  });

  it("rejects a key that is not 32 bytes", () => {
    expect(() => sealToken("x", Buffer.alloc(16, 1).toString("base64"))).toThrow(/32 bytes/);
  });
});

describe("code exchange", () => {
  const ok = (body: unknown) =>
    (async () => ({ json: async () => body })) as unknown as typeof fetch;

  it("returns the token on success", async () => {
    const r = await exchangeCode({
      code: "c",
      clientId: "i",
      clientSecret: "s",
      redirectUri: "r",
      fetchImpl: ok({ access_token: "gho_1", scope: "repo", token_type: "bearer" })
    });
    expect(r.accessToken).toBe("gho_1");
  });

  // GitHub answers 200 with an `error` field rather than a non-2xx status, so a
  // status-only check would treat a failure as success and store an empty token.
  it("throws when GitHub reports an error inside a 200", async () => {
    await expect(
      exchangeCode({
        code: "c",
        clientId: "i",
        clientSecret: "s",
        redirectUri: "r",
        fetchImpl: ok({ error: "bad_verification_code" })
      })
    ).rejects.toThrow(/bad_verification_code/);
  });

  it("throws when the body has no access_token at all", async () => {
    await expect(
      exchangeCode({ code: "c", clientId: "i", clientSecret: "s", redirectUri: "r", fetchImpl: ok({}) })
    ).rejects.toThrow(/no_access_token/);
  });
});
