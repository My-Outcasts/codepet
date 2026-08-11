import {
  creditsToBudget,
  listCostToCredits,
  CREDIT_CENTS,
  DEFAULT_RUN_CREDITS
} from "../engBudget";

describe("creditsToBudget", () => {
  it("converts credits to an integer-cents string", () => {
    expect(creditsToBudget(40)).toEqual({
      type: "limit",
      max_list_cost: { amount: "200", currency: "USD" }
    });
  });

  it("never emits a decimal amount — the API rejects '25.00'", () => {
    const { amount } = creditsToBudget(7).max_list_cost;
    expect(amount).toMatch(/^[1-9][0-9]*$/);
  });

  it("rounds a fractional credit balance down, so we never over-grant", () => {
    // 7.9 credits * 5c = 39.5c → 39, not 40
    expect(creditsToBudget(7.9).max_list_cost.amount).toBe("39");
  });

  it("floors at one cent — a zero amount is rejected by the API", () => {
    expect(creditsToBudget(0).max_list_cost.amount).toBe("1");
    expect(creditsToBudget(-5).max_list_cost.amount).toBe("1");
  });

  it("caps a large balance at the per-run ceiling", () => {
    // A founder with 800 credits still gets a 40-credit run, not an 800-credit one.
    expect(creditsToBudget(800)).toEqual(creditsToBudget(DEFAULT_RUN_CREDITS));
  });
});

describe("listCostToCredits", () => {
  it("rounds spend up, so a partial credit is charged", () => {
    expect(listCostToCredits(1)).toBe(1);
    expect(listCostToCredits(5)).toBe(1);
    expect(listCostToCredits(6)).toBe(2);
  });

  it("charges nothing for a session that never ran", () => {
    expect(listCostToCredits(0)).toBe(0);
  });

  it("round-trips against CREDIT_CENTS", () => {
    expect(listCostToCredits(CREDIT_CENTS * 12)).toBe(12);
  });
});
