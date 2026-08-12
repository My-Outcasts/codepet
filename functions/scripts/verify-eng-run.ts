//
// Live end-to-end verification for the engineering backend. NOT part of the
// test suite — it needs a real deployed backend, a real repo linked in
// Firestore, and a real ID token, and it spends real credits.
//
// Drives the deployed functions the way the app will: start a run, tail the
// SSE relay, answer the permission asks, print what comes back. Keeps a human
// in the loop for the one thing unit tests cannot cover — whether the agent
// actually does the job.
//
//   cd functions
//   export ID_TOKEN=$(npm run -s token -- --email a@b.c --password pw)
//   npm run verify:eng
//
// Environment:
//   ID_TOKEN       required. `npm run -s token` prints one. Valid one hour.
//   AUTO_APPROVE   "1" to allow every permission ask as it arrives. Without
//                  it the run stalls at the first `bash`, because the agent
//                  is provisioned `bash: always_ask` and this script has no
//                  other way to answer. That stall is not a hang — the stream
//                  correctly stays open on `requires_action` — but it means
//                  the default mode can never reach `done`.
//   RUN_ID         attach to an existing run instead of starting a new one.
//                  Resuming a paused run costs nothing extra; starting a
//                  fresh one pays for the repo read again.
//   ASK            what to ask for. Defaults to the CONTRIBUTING.md task.
//
// The ID token is read from the environment, never from argv: a token passed
// as a CLI argument lands in shell history and in `ps` output for the
// lifetime of the process, which a value read from `process.env` does not.
//
// This script never logs the token, the Authorization header, or any other
// credential. If you extend it to echo a request for debugging, redact the
// Authorization value before printing — do not print headers verbatim.
const BASE = process.env.ENG_BASE ?? "https://us-central1-devpet-8f4b1.cloudfunctions.net";

interface Frame {
  event: string;
  data: Record<string, unknown>;
}

/**
 * Splits an SSE byte stream into frames.
 *
 * Stateful across chunks on purpose: a frame can straddle a chunk boundary,
 * and parsing each chunk independently silently drops whichever frame was cut
 * in half. Comment lines (`: heartbeat`) carry no event and are skipped.
 */
export function makeFrameParser(): (chunk: string) => Frame[] {
  let buffer = "";
  return (chunk: string): Frame[] => {
    buffer += chunk;
    const frames: Frame[] = [];
    let split = buffer.indexOf("\n\n");
    while (split !== -1) {
      const block = buffer.slice(0, split);
      buffer = buffer.slice(split + 2);
      let event = "";
      let data = "";
      for (const line of block.split("\n")) {
        if (line.startsWith("event:")) event = line.slice(6).trim();
        else if (line.startsWith("data:")) data += line.slice(5).trim();
      }
      if (event) {
        try {
          frames.push({ event, data: data ? JSON.parse(data) : {} });
        } catch {
          // A frame whose data is not JSON is the relay's problem, not this
          // script's — report it and keep reading rather than dying mid-run.
          console.error(`! unparseable data on "${event}" frame`);
        }
      }
      split = buffer.indexOf("\n\n");
    }
    return frames;
  };
}

async function sendTurn(idToken: string, body: Record<string, unknown>): Promise<void> {
  const response = await fetch(`${BASE}/engSendTurn`, {
    method: "POST",
    headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!response.ok) {
    // Status and the handler's own error code only. The body of a failed
    // request can echo back what was sent, and what was sent is authenticated.
    throw new Error(`engSendTurn ${response.status}: ${await response.text()}`);
  }
}

async function main(): Promise<void> {
  const idToken = process.env.ID_TOKEN;
  if (!idToken) throw new Error("ID_TOKEN required — get one with `npm run token`");
  const autoApprove = process.env.AUTO_APPROVE === "1";

  let runId = process.env.RUN_ID ?? "";
  if (runId) {
    console.log("attaching to existing run:", runId);
  } else {
    const started = await fetch(`${BASE}/engStartRun`, {
      method: "POST",
      headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ ask: process.env.ASK ?? "Add a CONTRIBUTING.md explaining how to run the tests." })
    });
    if (!started.ok) throw new Error(`engStartRun ${started.status}: ${await started.text()}`);
    ({ runId } = (await started.json()) as { runId: string });
    console.log("runId:", runId);
  }

  if (!autoApprove) {
    console.log("AUTO_APPROVE is not set — this run will stall at the first permission ask.");
  }

  const stream = await fetch(`${BASE}/engStream?runId=${runId}`, {
    headers: { Authorization: `Bearer ${idToken}`, Accept: "text/event-stream" }
  });
  if (!stream.ok) throw new Error(`engStream ${stream.status}: ${await stream.text()}`);
  if (!stream.body) throw new Error("engStream returned no readable body");

  // An approval can be replayed from history on reconnect, and answering the
  // same tool_use twice is a wasted round trip at best.
  const answered = new Set<string>();
  const parse = makeFrameParser();
  const reader = stream.body.getReader();
  const decoder = new TextDecoder();

  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      console.log("\n-- stream closed by the server --");
      break;
    }
    for (const frame of parse(decoder.decode(value, { stream: true }))) {
      if (frame.event === "message") {
        console.log(`\n${String(frame.data.text ?? "")}\n`);
      } else if (frame.event === "step") {
        console.log(`  · ${JSON.stringify(frame.data)}`);
      } else if (frame.event === "approval") {
        const toolUseId = String(frame.data.toolUseId ?? "");
        console.log(`  ? ${String(frame.data.name ?? "tool")} ${JSON.stringify(frame.data.input)}`);
        if (!autoApprove || !toolUseId || answered.has(toolUseId)) continue;
        answered.add(toolUseId);
        await sendTurn(idToken, { runId, approve: { toolUseId, allow: true } });
        console.log(`  ✓ approved ${toolUseId}`);
      } else if (frame.event === "done") {
        console.log(`\n-- done: ${String(frame.data.stopReason ?? "?")} --`);
        return;
      } else if (frame.event === "error") {
        console.error(`\n-- error: ${JSON.stringify(frame.data)} --`);
        return;
      }
    }
  }
}

// Guarded so a test can import `makeFrameParser` without the import itself
// starting a paid run against production.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
