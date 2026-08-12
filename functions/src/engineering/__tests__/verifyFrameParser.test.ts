import { makeFrameParser } from "../../../scripts/verify-eng-run";

// The verification script is not shipped code, but its SSE parser is the only
// thing standing between a real relay bug and a green "verified" report — a
// parser that silently drops frames would make a broken engStream look fine.
describe("makeFrameParser", () => {
  it("skips comment lines, which is all a heartbeat is", () => {
    const parse = makeFrameParser();
    expect(parse(": heartbeat\n\n")).toEqual([]);
  });

  it("reassembles a frame split across chunk boundaries", () => {
    const parse = makeFrameParser();
    // A frame cut in half is the failure a per-chunk parser hides: each half
    // parses to nothing, and the frame is dropped with no error anywhere.
    expect(parse("event: appro")).toEqual([]);
    expect(parse('val\ndata: {"toolUseId":"tu_1","name":"bash"}\n\n')).toEqual([
      { event: "approval", data: { toolUseId: "tu_1", name: "bash" } }
    ]);
  });

  it("returns every frame when several arrive in one chunk", () => {
    const parse = makeFrameParser();
    const frames = parse(
      'event: message\ndata: {"text":"a"}\n\nevent: done\ndata: {"stopReason":"end_turn"}\n\n'
    );
    expect(frames.map((f) => f.event)).toEqual(["message", "done"]);
    expect(frames[1].data).toEqual({ stopReason: "end_turn" });
  });

  it("keeps reading after a frame whose data is not JSON", () => {
    const parse = makeFrameParser();
    const frames = parse('event: step\ndata: not-json\n\nevent: done\ndata: {"stopReason":"x"}\n\n');
    // The bad frame is dropped, but the good one after it still arrives —
    // dying here would abandon a paid run mid-flight.
    expect(frames.map((f) => f.event)).toEqual(["done"]);
  });

  it("carries a heartbeat interleaved between halves of a real frame", () => {
    const parse = makeFrameParser();
    expect(parse('event: message\ndata: {"te')).toEqual([]);
    expect(parse('xt":"hi"}\n\n: heartbeat\n\n')).toEqual([
      { event: "message", data: { text: "hi" } }
    ]);
  });
});
