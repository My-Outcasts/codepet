import { describe, expect, test } from "@jest/globals";
import {
  DRAFT_MESSAGE_TOOL,
  validateDraftMessageToolUse,
  buildSystemPrompt,
} from "../companyChatCore";

describe("draft_message validation", () => {
  test("keeps every version the turn produced, in order", () => {
    const out = validateDraftMessageToolUse({
      messages: [
        { channel: "text", to: "the two who asked to pay", body: "Hey [name] — the real offer is $39/month." },
        { channel: "text", to: "the other seven", body: "Quick heads up — Ferment's moving to paid on [date]." },
      ],
    });
    expect(out).toHaveLength(2);
    expect(out![0].to).toBe("the two who asked to pay");
    expect(out![1].body).toContain("[date]");
  });

  test("an email keeps its subject; a dm and a text cannot have one", () => {
    const out = validateDraftMessageToolUse({
      messages: [
        { channel: "email", subject: "Quick question", body: "Hi [name]," },
        { channel: "dm", subject: "Should not survive", body: "hey" },
        { channel: "text", subject: "Nor this", body: "hi" },
      ],
    });
    expect(out![0].subject).toBe("Quick question");
    expect(out![1].subject).toBe("");
    expect(out![2].subject).toBe("");
  });

  /// The reported screenshot had every message wrapped in quotes. Those belong to the
  /// prose presentation — pasting them into an email client would send the quotes too.
  test("wrapping quotes are stripped, real punctuation is not", () => {
    const out = validateDraftMessageToolUse({
      messages: [
        { channel: "dm", body: '"Hey [name] — worth fifteen minutes?"' },
        { channel: "dm", body: 'She said "yes" and then went quiet.' },
        { channel: "dm", body: '"Quoted opener" and then more text.' },
      ],
    });
    expect(out![0].body).toBe("Hey [name] — worth fifteen minutes?");
    expect(out![1].body).toBe('She said "yes" and then went quiet.');
    expect(out![2].body).toBe('"Quoted opener" and then more text.');
  });

  test("an unknown channel falls back to dm rather than being dropped", () => {
    const out = validateDraftMessageToolUse({ messages: [{ channel: "carrier_pigeon", body: "hi" }] });
    expect(out![0].channel).toBe("dm");
  });

  /// There is no second field that could stand in for a missing body, so it is dropped —
  /// rendering an empty card would be worse than leaving the turn as prose.
  test("entries with no usable body are dropped, and an all-empty call returns null", () => {
    const mixed = validateDraftMessageToolUse({
      messages: [{ channel: "dm", body: "   " }, { channel: "dm", body: "real one" }],
    });
    expect(mixed).toHaveLength(1);
    expect(mixed![0].body).toBe("real one");

    expect(validateDraftMessageToolUse({ messages: [{ channel: "dm", body: "" }] })).toBeNull();
    expect(validateDraftMessageToolUse({ messages: [] })).toBeNull();
    expect(validateDraftMessageToolUse({ messages: "not an array" })).toBeNull();
    expect(validateDraftMessageToolUse(null)).toBeNull();
    expect(validateDraftMessageToolUse({})).toBeNull();
  });

  test("caps the number of drafts", () => {
    const many = Array.from({ length: 9 }, (_, i) => ({ channel: "dm", body: `msg ${i}` }));
    expect(validateDraftMessageToolUse({ messages: many })).toHaveLength(4);
  });

  test("the tool takes an ARRAY — the reported turn carried two drafts", () => {
    const schema = DRAFT_MESSAGE_TOOL.input_schema as any;
    expect(schema.properties.messages.type).toBe("array");
    expect(schema.required).toEqual(["messages"]);
    expect(schema.properties.messages.items.required).toEqual(["channel", "body"]);
  });
});

describe("the instruction that actually changes behaviour", () => {
  /// The bug was the model TYPING the message. A tool description is only read once the
  /// model is already reaching for a tool, so the system prompt has to say it too — and it
  /// has to stay in the cacheable prefix, which means static text only.
  test("the system prompt tells the companion to emit messages, not type them", () => {
    const prompt = buildSystemPrompt({ companionId: "byte", language: "en" });
    expect(prompt).toContain("draft_message");
    expect(prompt).toMatch(/instead of typing it/i);
  });

  test("the prefix stays static across turns, so it is still cacheable", () => {
    const a = buildSystemPrompt({ companionId: "byte", language: "en" });
    const b = buildSystemPrompt({ companionId: "byte", language: "en" });
    expect(a).toBe(b);
  });
});
