import { buildMessages, ATTACHMENT_REPLAY_WINDOW, type AttachmentDTO } from "../companyChatCore";

/**
 * buildMessages coalesces consecutive same-role turns with
 *   last.content = `${last.content}\n\n${msg.content}`
 * which is correct for strings and silently produces "[object Object]" the moment
 * content can be an array. That one line is why this suite exists.
 */
describe("buildMessages with attachments", () => {
  const img: AttachmentDTO = {
    kind: "image",
    filename: "shot.png",
    media_type: "image/png",
    data: "aGVsbG8=",
  };
  const img2: AttachmentDTO = {
    kind: "image",
    filename: "second.png",
    media_type: "image/png",
    data: "d29ybGQ=",
  };
  const b64 = (s: string) => Buffer.from(s, "utf8").toString("base64");

  it("returns string content for every message when no turn has an attachment", () => {
    // The regression guard: every existing caller passes no attachments and must
    // get byte-identical output to before this parameter existed.
    const out = buildMessages(
      [{ role: "me", text: "hi" }, { role: "companion", text: "hello" }],
      "and now?",
    );
    expect(out.every((m) => typeof m.content === "string")).toBe(true);
    expect(out).toEqual([
      { role: "user", content: "hi" },
      { role: "assistant", content: "hello" },
      { role: "user", content: "and now?" },
    ]);
  });

  it("puts the image block before the text block on the current turn", () => {
    // Documented ordering: the media block precedes the text block that asks
    // about it. Reversed, the model reads the question before seeing the image.
    const out = buildMessages([], "what is this?", [img]);
    const blocks = out[out.length - 1].content as any[];
    expect(Array.isArray(blocks)).toBe(true);
    expect(blocks[0].type).toBe("image");
    expect(blocks[0].source).toEqual({
      type: "base64",
      media_type: "image/png",
      data: "aGVsbG8=",
    });
    expect(blocks[blocks.length - 1]).toEqual({ type: "text", text: "what is this?" });
  });

  it("inlines a text attachment into the text content instead of giving it a block type", () => {
    const out = buildMessages([], "review this", [
      { kind: "text", filename: "notes.md", media_type: "text/plain", data: b64("# Notes") },
    ]);
    const content = out[out.length - 1].content;
    // A text-only attachment set leaves content a plain string — no block array needed.
    expect(typeof content).toBe("string");
    const rendered = content as string;
    expect(rendered).toContain("notes.md");
    expect(rendered).toContain("# Notes");
    expect(rendered).toContain("review this");
    expect(rendered).not.toContain('"type":"text_file"');
  });

  it("inlines a text attachment into the text block that follows the image", () => {
    const out = buildMessages([], "both please", [
      img,
      { kind: "text", filename: "notes.md", media_type: "text/plain", data: b64("# Notes") },
    ]);
    const blocks = out[out.length - 1].content as any[];
    expect(blocks).toHaveLength(2);
    expect(blocks[0].type).toBe("image");
    expect(blocks[1].type).toBe("text");
    expect(blocks[1].text).toContain("# Notes");
    expect(blocks[1].text).toContain("both please");
  });

  it("sends a pdf as a document block", () => {
    const out = buildMessages([], "summarize", [
      { kind: "pdf", filename: "q3.pdf", media_type: "application/pdf", data: "JVBER" },
    ]);
    const blocks = out[out.length - 1].content as any[];
    expect(blocks[0].type).toBe("document");
    expect(blocks[0].source.media_type).toBe("application/pdf");
  });

  it("forces a pdf's media_type to application/pdf whatever the client sent", () => {
    // The API accepts exactly one media_type on a document block. Passing the
    // client's string through would turn a wrong header into a 400 for the turn.
    const out = buildMessages([], "summarize", [
      { kind: "pdf", filename: "q3.pdf", media_type: "application/x-pdf", data: "JVBER" },
    ]);
    const blocks = out[out.length - 1].content as any[];
    expect(blocks[0].source.media_type).toBe("application/pdf");
  });

  it("omits the text block entirely when a turn has media and no text", () => {
    // An empty text block is a 400 from the API ("text content blocks must be
    // non-empty"), so a media-only turn must be media blocks alone.
    const out = buildMessages([], "   ", [img]);
    const blocks = out[out.length - 1].content as any[];
    expect(blocks).toHaveLength(1);
    expect(blocks[0].type).toBe("image");
  });

  // ── The landmine: four coalescing shapes, one for each the widened type permits ──

  it("coalesces string + string into a single string", () => {
    const out = buildMessages(
      [{ role: "me", text: "a" }, { role: "me", text: "b" }],
      "c",
    );
    expect(out).toEqual([{ role: "user", content: "a\n\nb\n\nc" }]);
  });

  it("coalesces string + blocks without stringifying the blocks", () => {
    // Plain turn first, attachment turn second.
    const out = buildMessages(
      [
        { role: "me", text: "look" },
        { role: "me", text: "at this", attachments: [img] },
      ],
      "well?",
    );
    const serialized = JSON.stringify(out);
    expect(serialized).not.toContain("[object Object]");
    expect(serialized).toContain("aGVsbG8=");
    const blocks = out[0].content as any[];
    expect(Array.isArray(blocks)).toBe(true);
    expect(blocks.map((b) => b.type)).toEqual(["text", "image", "text", "text"]);
    expect(blocks[0].text).toBe("look");
  });

  it("coalesces blocks + string without stringifying the blocks", () => {
    // Two consecutive user turns, the first carrying an attachment. The old
    // concat produced "[object Object]" here — with no error and no crash.
    const out = buildMessages(
      [
        { role: "me", text: "look at this", attachments: [img] },
        { role: "me", text: "specifically the top left" },
      ],
      "what do you see?",
    );
    const serialized = JSON.stringify(out);
    expect(serialized).not.toContain("[object Object]");
    expect(serialized).toContain("aGVsbG8=");
    const blocks = out[0].content as any[];
    expect(blocks.map((b) => b.type)).toEqual(["image", "text", "text", "text"]);
    expect(blocks[2].text).toBe("specifically the top left");
  });

  it("coalesces blocks + blocks into one flat block array keeping both payloads", () => {
    const out = buildMessages(
      [
        { role: "me", text: "one", attachments: [img] },
        { role: "me", text: "two", attachments: [img2] },
      ],
      "compare them",
    );
    const serialized = JSON.stringify(out);
    expect(serialized).not.toContain("[object Object]");
    expect(serialized).toContain("aGVsbG8=");
    expect(serialized).toContain("d29ybGQ=");
    const blocks = out[0].content as any[];
    expect(blocks.every((b) => typeof b === "object" && typeof b.type === "string")).toBe(true);
    expect(blocks.filter((b) => b.type === "image")).toHaveLength(2);
  });

  it("coalesces an assistant pair without stringifying anything", () => {
    // Assistant turns never carry attachments, but they take the same merge path.
    const out = buildMessages(
      [
        { role: "me", text: "hi" },
        { role: "companion", text: "one" },
        { role: "companion", text: "two" },
      ],
      "ok",
    );
    expect(out[1]).toEqual({ role: "assistant", content: "one\n\ntwo" });
  });

  // ── Replay window ───────────────────────────────────────────────────────────

  it("replays an attachment from history so a follow-up can still see it", () => {
    // The reason a one-shot attachment isn't worth shipping: the second question
    // is the one founders ask.
    const out = buildMessages(
      [
        { role: "me", text: "what is in this screenshot?", attachments: [img] },
        { role: "companion", text: "A login form." },
      ],
      "what about the top left?",
    );
    expect(JSON.stringify(out)).toContain("aGVsbG8=");
  });

  it("drops attachments older than the replay window", () => {
    // An inlined image re-uploads on every turn it survives. Unbounded replay
    // bills the founder for the same screenshot forever.
    const history = Array.from({ length: 12 }, (_, i) => ({
      role: i % 2 === 0 ? "me" : "companion",
      text: `turn ${i}`,
      ...(i === 0 ? { attachments: [img] } : {}),
    }));
    const out = buildMessages(history, "still there?");
    expect(JSON.stringify(out)).not.toContain("aGVsbG8=");
  });

  it("keeps an attachment exactly at the edge of the window and drops it one turn later", () => {
    // Pins the window to a turn count rather than to "the most recent N turns
    // that carry one" — the latter replays a single image for the whole 20-turn
    // history, which is the cost the cap exists to bound.
    const mk = (len: number) =>
      Array.from({ length: len }, (_, i) => ({
        role: i % 2 === 0 ? "me" : "companion",
        text: `turn ${i}`,
        ...(i === 0 ? { attachments: [img] } : {}),
      }));
    const atEdge = buildMessages(mk(ATTACHMENT_REPLAY_WINDOW), "q");
    const oneTooOld = buildMessages(mk(ATTACHMENT_REPLAY_WINDOW + 1), "q");
    expect(JSON.stringify(atEdge)).toContain("aGVsbG8=");
    expect(JSON.stringify(oneTooOld)).not.toContain("aGVsbG8=");
  });

  it("still emits the turn's text when its attachment falls outside the window", () => {
    // Dropping the payload must not drop the sentence that came with it.
    const history = Array.from({ length: 12 }, (_, i) => ({
      role: i % 2 === 0 ? "me" : "companion",
      text: `turn ${i}`,
      ...(i === 0 ? { attachments: [img] } : {}),
    }));
    const out = buildMessages(history, "still there?");
    expect(JSON.stringify(out)).toContain("turn 0");
  });

  // ── Unrecognised / malformed input from an untrusted client ──────────────────

  it("drops an attachment whose kind is not image, pdf or text", () => {
    // media_type is deliberately a VALID image type here: without the kind gate this
    // would sail through as an image block, so this test fails if the gate is removed
    // rather than being covered by the media_type check below.
    const out = buildMessages([], "what is this?", [
      { kind: "screenshot", filename: "a.sketch", media_type: "image/png", data: "aGVsbG8=" } as unknown as AttachmentDTO,
    ]);
    expect(out[0].content).toBe("what is this?");
  });

  it("drops an image whose media_type is not one the API accepts", () => {
    // image/jpg (not jpeg), image/bmp, image/svg+xml are all 400s. Dropping the
    // attachment loses the image; passing it through loses the whole turn.
    const out = buildMessages([], "what is this?", [
      { ...img, media_type: "image/jpg" },
    ]);
    expect(out[0].content).toBe("what is this?");
  });

  it("drops an attachment whose data is empty or not base64", () => {
    const out = buildMessages([], "what is this?", [
      { ...img, data: "" },
      { ...img, filename: "b.png", data: "not base64!!" },
    ]);
    expect(out[0].content).toBe("what is this?");
  });

  it("strips whitespace out of wrapped base64 rather than sending it", () => {
    // The API rejects wrapped base64. A client that used
    // .lineLength64Characters would otherwise fail every attached image.
    const out = buildMessages([], "what is this?", [
      { ...img, data: "aGVs\nbG8=" },
    ]);
    const blocks = out[0].content as any[];
    expect(blocks[0].source.data).toBe("aGVsbG8=");
  });

  it("keeps every image media_type the API accepts", () => {
    for (const mt of ["image/jpeg", "image/png", "image/gif", "image/webp"]) {
      const out = buildMessages([], "q", [{ ...img, media_type: mt }]);
      const blocks = out[0].content as any[];
      expect(blocks[0].source.media_type).toBe(mt);
    }
  });

  it("ignores a non-array attachments value instead of throwing", () => {
    const out = buildMessages([], "hello", "nope" as unknown as AttachmentDTO[]);
    expect(out).toEqual([{ role: "user", content: "hello" }]);
  });
});
