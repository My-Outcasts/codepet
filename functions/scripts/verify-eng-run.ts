//
// Live end-to-end verification for the engineering backend. NOT part of the
// test suite — it needs a real deployed backend, a real repo linked in
// Firestore, and a real ID token, and it spends real credits.
//
// Drives the deployed functions the way the app will: start a run, tail the
// SSE relay, print what comes back. Keeps a human in the loop for the one
// thing unit tests cannot cover — whether the agent actually does the job.
//
//   cd functions
//   npm run token                # prints an ID_TOKEN to stdout
//   ID_TOKEN=<paste> npm run verify:eng
//
// The ID token is read from the environment, never from argv: a token passed
// as a CLI argument lands in shell history and in `ps` output for the
// lifetime of the process, which a value read from `process.env` does not.
//
// This script never logs the token, the Authorization header, or any other
// credential. If you extend it to echo a request for debugging, redact the
// Authorization value before printing — do not print headers verbatim.
const BASE = process.env.ENG_BASE ?? "https://us-central1-devpet-8f4b1.cloudfunctions.net";

async function main(): Promise<void> {
  const idToken = process.env.ID_TOKEN;
  if (!idToken) throw new Error("ID_TOKEN required — get one with `npm run token`");

  const started = await fetch(`${BASE}/engStartRun`, {
    method: "POST",
    headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ask: process.env.ASK ?? "Add a CONTRIBUTING.md explaining how to run the tests." })
  });
  if (!started.ok) throw new Error(`engStartRun ${started.status}: ${await started.text()}`);
  const { runId } = (await started.json()) as { runId: string };
  console.log("runId:", runId);

  const stream = await fetch(`${BASE}/engStream?runId=${runId}`, {
    headers: { Authorization: `Bearer ${idToken}`, Accept: "text/event-stream" }
  });
  if (!stream.ok) throw new Error(`engStream ${stream.status}: ${await stream.text()}`);
  if (!stream.body) throw new Error("engStream returned no readable body");

  const reader = stream.body.getReader();
  const decoder = new TextDecoder();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    process.stdout.write(decoder.decode(value));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
