import { coerceRoomOffer, resolveActions, buildChatRequest, buildSystemPrompt } from "../companyChatCore";
import { doneFrame } from "../local/chatSidecar";

// 9 Oct: since #247 a department in Ask is told to say "this one needs Marketing too", and the
// founder could do nothing with it. suggest_room turns that sentence into an offer.
describe("coerceRoomOffer", () => {
  const ok = { departments: ["fin", "sales"], question: "Discount Pro to close more deals?", why: "Price and pipeline pull apart." };

  it("keeps a valid offer", () => {
    expect(coerceRoomOffer(ok)).toEqual(ok);
  });
  it("drops an offer with fewer than two known departments", () => {
    expect(coerceRoomOffer({ ...ok, departments: ["fin", "product", "chief_of_staff"] })).toBeNull();
    expect(coerceRoomOffer({ ...ok, departments: ["fin"] })).toBeNull();
  });
  it("removes unknown keys and duplicates, and caps at four", () => {
    const r = coerceRoomOffer({ ...ok, departments: ["fin", "fin", "nope", "sales", "mkt", "eng", "legal"] });
    expect(r?.departments).toEqual(["fin", "sales", "mkt", "eng"]);
  });
  it("needs a question and a why", () => {
    expect(coerceRoomOffer({ ...ok, why: " " })).toBeNull();
    expect(coerceRoomOffer({ ...ok, question: "" })).toBeNull();
    expect(coerceRoomOffer(null)).toBeNull();
  });
  it("clips the question and the why", () => {
    const r = coerceRoomOffer({ ...ok, question: "q".repeat(500), why: "w".repeat(500) });
    expect(r?.question.length).toBe(300);
    expect(r?.why.length).toBe(160);
  });
});

describe("suggest_room on the wire", () => {
  const offer = { departments: ["fin", "sales"], question: "Discount?", why: "They pull apart." };

  it("resolves alongside remember_fact", () => {
    const r = resolveActions(
      [{ name: "remember_fact", input: { facts: [{ topic: "price", statement: "$19" }] } },
       { name: "suggest_room", input: offer }], [], [], []);
    expect(r.roomOffer).toEqual(offer);
    expect(r.remember.length).toBe(1);
  });
  it("puts room_offer on the done frame only when set", () => {
    const base = resolveActions([], [], [], []);
    expect(doneFrame(base, "m")).not.toHaveProperty("room_offer");
    expect(doneFrame({ ...base, roomOffer: offer }, "m").room_offer).toEqual(offer);
  });
  // Offered only on a department's turn — an ordinary turn has nobody to bring the room in.
  it("is offered only when the turn answers as a known department", () => {
    const names = (b: object) => (buildChatRequest(b as never).tools as Array<{ name?: string }>).map((t) => t.name);
    expect(names({ user_message: "hi", dept_key: "fin" })).toContain("suggest_room");
    expect(names({ user_message: "hi" })).not.toContain("suggest_room");
    expect(names({ user_message: "hi", dept_key: "nope" })).not.toContain("suggest_room");
  });
});

// 9 Oct, measured in the app: with a project folder linked (Read/Glob/Grep on), the model said
// "Marketing and Sales both want this money" in prose and called suggest_room 0 times in 3 on
// the founder's real request (3/3 without the folder). The role framing told it to SAY the
// room was needed, never to OFFER it. The prompt now names the tool at that exact point.
describe("the department is told to offer the room, not just mention it", () => {
  it("names suggest_room where it says another department is needed", () => {
    const p = buildSystemPrompt({ companionId: "crash", language: "en", deptKey: "fin" });
    expect(p).toMatch(/suggest_room/);
  });
  it("says nothing about it on an ordinary turn", () => {
    expect(buildSystemPrompt({ companionId: "byte", language: "en" })).not.toMatch(/suggest_room/);
  });
});
