import { cacheKey, isCacheEntryFresh } from "../cache";

describe("cache helpers", () => {
  test("cacheKey combines uid, turn_id, and language", () => {
    expect(cacheKey("uid1", "session:2026-05-05T09:00:00Z", "vi"))
      .toBe("uid1__session:2026-05-05T09:00:00Z__vi");
  });

  test("cacheKey defaults language to en", () => {
    expect(cacheKey("uid1", "session:2026-05-05T09:00:00Z"))
      .toBe("uid1__session:2026-05-05T09:00:00Z__en");
  });

  test("isCacheEntryFresh true within 7 days", () => {
    const now = new Date("2026-05-10T00:00:00Z");
    const cached = new Date("2026-05-05T00:00:00Z");
    expect(isCacheEntryFresh(cached, now)).toBe(true);
  });

  test("isCacheEntryFresh false beyond 7 days", () => {
    const now = new Date("2026-05-13T00:00:01Z");
    const cached = new Date("2026-05-05T00:00:00Z");
    expect(isCacheEntryFresh(cached, now)).toBe(false);
  });
});
