import { todayKey, computeResetAt } from "../rateLimit";

describe("rateLimit helpers", () => {
  test("todayKey returns YYYY-MM-DD UTC", () => {
    const d = new Date("2026-05-05T23:59:59Z");
    expect(todayKey(d)).toBe("2026-05-05");
  });

  test("todayKey is UTC-based across timezones", () => {
    const d = new Date("2026-05-05T00:00:01Z");
    expect(todayKey(d)).toBe("2026-05-05");
  });

  test("computeResetAt returns next 00:00 UTC", () => {
    const d = new Date("2026-05-05T15:30:00Z");
    expect(computeResetAt(d).toISOString()).toBe("2026-05-06T00:00:00.000Z");
  });
});
