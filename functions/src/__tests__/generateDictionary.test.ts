import { validateDictionaryPayload, dictCacheKey } from "../generateDictionary";

const validTerm = { term: "OAuth", seen_in: [{ file: "LoginView.swift", snippet: "ASWebAuthenticationSession(...)" }], evolution: "encountered" as const };

describe("validateDictionaryPayload", () => {
  test("accepts a minimal valid payload", () => {
    expect(validateDictionaryPayload({ language: "en", terms: [{ term: "async" }] })).toBeNull();
  });

  test("accepts a fully-specified payload", () => {
    expect(validateDictionaryPayload({
      language: "vi",
      project: { name: "CodePet", brief: "a learning companion", tags: ["swiftui"] },
      pet_persona: { id: "byte", name: "Byte", personality: "glitchy", domain: "Data" },
      terms: [validTerm]
    })).toBeNull();
  });

  test("rejects missing/invalid language", () => {
    expect(validateDictionaryPayload({ terms: [{ term: "x" }] })).toMatch(/language/);
    expect(validateDictionaryPayload({ language: "fr", terms: [{ term: "x" }] })).toMatch(/language/);
  });

  test("rejects empty or non-array terms", () => {
    expect(validateDictionaryPayload({ language: "en", terms: [] })).toMatch(/must not be empty/);
    expect(validateDictionaryPayload({ language: "en", terms: "nope" })).toMatch(/must be an array/);
  });

  test("rejects more than 12 terms", () => {
    const terms = Array.from({ length: 13 }, (_, i) => ({ term: `t${i}` }));
    expect(validateDictionaryPayload({ language: "en", terms })).toMatch(/at most 12/);
  });

  test("rejects a term with no token", () => {
    expect(validateDictionaryPayload({ language: "en", terms: [{ term: "  " }] })).toMatch(/terms\[0\].term required/);
  });

  test("rejects seen_in entry without a file", () => {
    expect(validateDictionaryPayload({
      language: "en",
      terms: [{ term: "OAuth", seen_in: [{ snippet: "x" }] }]
    })).toMatch(/seen_in\[0\].file required/);
  });

  test("rejects an invalid evolution stage", () => {
    expect(validateDictionaryPayload({
      language: "en",
      terms: [{ term: "OAuth", evolution: "owned" }]
    })).toMatch(/evolution must be/);
  });

  test("rejects a malformed pet_persona", () => {
    expect(validateDictionaryPayload({
      language: "en",
      terms: [{ term: "x" }],
      pet_persona: { id: "byte" }
    })).toMatch(/pet_persona requires/);
  });
});

describe("dictCacheKey", () => {
  test("slugifies the term and includes language + evolution", () => {
    expect(dictCacheKey("uid1", "async / await", "en", "mastered"))
      .toBe("uid1__async-await__en__mastered");
  });

  test("different evolution stages produce different keys", () => {
    const a = dictCacheKey("uid1", "OAuth", "en", "encountered");
    const b = dictCacheKey("uid1", "OAuth", "en", "used");
    expect(a).not.toBe(b);
  });

  test("strips leading/trailing separators from punctuation-heavy tokens", () => {
    expect(dictCacheKey("uid1", ".env", "vi", "used")).toBe("uid1__env__vi__used");
  });
});
