import { decide } from "../../../scripts/migrate-eng-balance";

// The migration's whole risk is in one decision, so that decision is pure and
// tested here. Getting it wrong does not throw — it silently hands a founder
// credits they already spent, or silently locks them out of credits they have.
describe("decide", () => {
  it("migrates a plain credits figure when no balance exists yet", () => {
    expect(decide(20, false)).toBe("migrate");
  });

  it("migrates a zero balance, which is a real state and not the same as absent", () => {
    // A founder who has spent everything must end up at 0, not unmigrated —
    // an unmigrated company gets 0 from readBalance anyway, but leaving the
    // document absent makes a second run of this script migrate them from a
    // stale companies/{uid}.credits later.
    expect(decide(0, false)).toBe("migrate");
  });

  it("skips a company that already has a balance, whatever its credits field says", () => {
    // The expensive mistake: re-running after a founder has spent credits
    // would restore them to the pre-migration figure.
    expect(decide(999, true)).toBe("skip-existing");
  });

  it("checks the existing balance BEFORE the credits value, so a stale figure cannot win", () => {
    expect(decide(undefined, true)).toBe("skip-existing");
    expect(decide(NaN, true)).toBe("skip-existing");
  });

  it("skips a company with no credits field", () => {
    expect(decide(undefined, false)).toBe("skip-no-credits");
  });

  it("skips NaN rather than copying it", () => {
    // Copying NaN produces a balance readBalance reports as 0 — the founder
    // is locked out with nothing indicating why.
    expect(decide(NaN, false)).toBe("skip-no-credits");
  });

  it("skips Infinity rather than copying an unbounded balance", () => {
    expect(decide(Infinity, false)).toBe("skip-no-credits");
  });

  it("skips a string, which is what a hand-edited console value looks like", () => {
    expect(decide("20", false)).toBe("skip-no-credits");
  });
});
