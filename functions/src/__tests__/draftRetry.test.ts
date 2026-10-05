import {
  claimsDrafts,
  needsDraftRetry,
  buildDraftRetryMessages,
  DRAFT_RETRY_INSTRUCTION,
  type ResolvedActions,
} from "../companyChatCore";

/**
 * CP-024, the half #197 did not cover. Replaying the 24 Sep turn ("I think we can start with
 * the option 1" after an options list) on 1 Oct reproduced the recording 1/15 times: the reply
 * framed "I wrote you two versions: a short DM … and a slightly longer cold email …" and
 * `draft_message` was never called. The prompt tells the model to keep the messages OUT of the
 * prose, so a skipped call leaves a reply describing drafts that exist nowhere.
 *
 * The sidecar now retries once when the reply claims drafts that did not come back. These pin
 * when it does — and, as importantly, when it does not: every false positive is a second paid
 * `claude` run on an ordinary turn.
 */

const none: ResolvedActions = {
  runTaskId: null, nav: null, setup: null, remember: [], completeTaskId: null,
  addTask: null, addTasks: [], reviseWork: null, drafts: null,
};

describe("claimsDrafts", () => {
  // Every line here is a real reply from the 1 Oct replays.
  const claims = [
    "I wrote you two versions: a short DM for founders who build in public, and a slightly longer cold email.",
    "I've written three versions: a cold email, an Instagram DM, and a text for owners you've already met.",
    "I drafted two messages: a short DM for founders who build in public on X or Indie Hackers.",
    "Here are three versions with different lengths and channels.",
    "Three versions below, each for a different channel.",
    "Your three drafts are ready: a short direct email, one that opens with the morning line problem.",
    "Your three drafts are in the cards above.",
    "Outreach it is. Two versions below, one cold DM for founders you've never talked to.",
    "Mình viết ba bản theo ba nhóm người: bản làm quen cho quán chưa biết BrewQ.",
    "Ba bản nằm trong các thẻ bên dưới.",
    "Có ba bản rồi: một email làm quen đầy đủ, một tin Zalo ngắn để nhắn lạnh.",
    "Mình đã soạn tin nhắn cho hai chủ quán.",
  ];
  for (const text of claims) {
    it(`catches: ${text.slice(0, 60)}`, () => expect(claimsDrafts(text)).toBe(true));
  }

  const ordinary = [
    "Want me to draft three versions you can test?",
    "I can write a cold email for them if you like.",
    "I wrote down your pricing decision, so I'll keep it in mind.",
    "Here's what I'd focus on this week: talk to five shop owners.",
    "I'm running your outreach task now. It'll show up here for you to approve.",
    "Start with the two owners who already asked about pricing.",
    "Bạn muốn mình soạn ba bản để thử không?",
    // Vietnamese marks no tense, so an OFFER reads like a claim unless the offer words are
    // read. 1 Oct: one planning reply in Vietnamese fired a retry (which came back empty).
    "Nếu muốn, mình soạn luôn tin nhắn cho hai chủ quán.",
    "Mình có thể viết email trả lời họ.",
    "Để mình soạn tin nhắn trả lời họ nhé.",
    "Cần thì mình viết giúp bạn một tin nhắn ngắn.",
    "",
  ];
  for (const text of ordinary) {
    it(`leaves alone: ${text.slice(0, 60) || "(empty)"}`, () => expect(claimsDrafts(text)).toBe(false));
  }
});

describe("needsDraftRetry", () => {
  const claim = "I wrote you two versions: a short DM and a cold email.";

  it("retries when the reply claims drafts and none came back", () => {
    expect(needsDraftRetry(claim, none)).toBe(true);
  });

  it("does not retry when the drafts did come back", () => {
    const drafts = [{ channel: "dm" as const, to: "", subject: "", body: "Hi [name]" }];
    expect(needsDraftRetry(claim, { ...none, drafts })).toBe(false);
  });

  it("does not retry over a run — the run is what produces the work", () => {
    expect(needsDraftRetry(claim, { ...none, runTaskId: "t1" })).toBe(false);
  });

  it("does not retry an ordinary reply", () => {
    expect(needsDraftRetry("Start with the two owners who asked.", none)).toBe(false);
  });
});

describe("buildDraftRetryMessages", () => {
  const original = [
    { role: "user" as const, content: "Hello, can you help me" },
    { role: "assistant" as const, content: "Four places we could start: 1. Outreach …" },
    { role: "user" as const, content: "I think we can start with the option 1" },
  ];
  const reply = "I wrote you two versions: a short DM and a cold email.";

  it("replays the turn with the reply as the model's own words, then asks for the drafts", () => {
    const msgs = buildDraftRetryMessages(original, reply);
    expect(msgs.slice(0, 3)).toEqual(original);
    expect(msgs[3]).toEqual({ role: "assistant", content: reply });
    expect(msgs[4]).toEqual({ role: "user", content: DRAFT_RETRY_INSTRUCTION });
  });

  it("does not mutate the turn it was given", () => {
    const copy = JSON.parse(JSON.stringify(original));
    buildDraftRetryMessages(original, reply);
    expect(original).toEqual(copy);
  });

  it("the instruction names the tool, asks for exactly the described messages, and forbids prose", () => {
    expect(DRAFT_RETRY_INSTRUCTION).toMatch(/draft_message/);
    expect(DRAFT_RETRY_INSTRUCTION).toMatch(/exactly the messages your reply describes/i);
    expect(DRAFT_RETRY_INSTRUCTION).toMatch(/do not write any other text/i);
  });
});
