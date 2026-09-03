import Anthropic from "@anthropic-ai/sdk";
import {
  CallArgs,
  NarrativeOutput,
  NarrativeStreamEvent,
  SESSION_SUMMARY_TOOL,
  SessionCallArgs,
  SessionStreamEvent,
  SessionSummaryOutput,
  cacheableSystemBlock,
  coerceNarrative,
  coerceSessionSummary,
  narrativeRequest,
  sessionSummaryRequest,
  MODEL,
  MAX_TOKENS,
  NARRATIVE_TOOL,
} from "./anthropicCore";

// Re-exported so `./anthropic` stays the name all 29 importers use, whichever half of it
// they wanted.
export * from "./anthropicCore";

export async function callAnthropicSession(
  client: Anthropic,
  args: SessionCallArgs
): Promise<SessionSummaryOutput> {
  const { system, user } = sessionSummaryRequest(args);

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 1200,
    system: [cacheableSystemBlock({ model: MODEL, text: system, tools: SESSION_SUMMARY_TOOL })],
    tools: [SESSION_SUMMARY_TOOL as any],
    tool_choice: { type: "tool", name: "record_session_summary" },
    messages: [{ role: "user", content: user }]
  });

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === "record_session_summary") {
      const summary = coerceSessionSummary(block.input);
      if (summary) return summary;
    }
  }
  throw new Error("Anthropic response missing valid record_session_summary tool use");
}

export async function* streamAnthropicSession(
  client: Anthropic,
  args: SessionCallArgs
): AsyncGenerator<SessionStreamEvent> {
  const { system, user } = sessionSummaryRequest(args);

  const stream = client.messages.stream({
    model: MODEL,
    max_tokens: 1200,
    system: [cacheableSystemBlock({ model: MODEL, text: system, tools: SESSION_SUMMARY_TOOL })],
    tools: [SESSION_SUMMARY_TOOL as any],
    tool_choice: { type: "tool", name: "record_session_summary" },
    messages: [{ role: "user", content: user }]
  });

  let jsonAccumulator = "";

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "input_json_delta"
    ) {
      const chunk = event.delta.partial_json;
      jsonAccumulator += chunk;
      yield { type: "json_delta", text: chunk };
    }
  }

  const final = await stream.finalMessage();
  const cacheHit = ((final.usage as any)?.cache_read_input_tokens ?? 0) > 0;

  let summary: SessionSummaryOutput | undefined;
  for (const block of final.content) {
    if (block.type === "tool_use" && block.name === "record_session_summary") {
      summary = coerceSessionSummary(block.input) ?? undefined;
    }
  }

  if (!summary) {
    try {
      summary = JSON.parse(jsonAccumulator) as SessionSummaryOutput;
    } catch {
      yield { type: "error", error: "Failed to parse session summary from stream" };
      return;
    }
  }

  yield { type: "done", summary, model: MODEL, cache_hit: cacheHit };
}

/**
 * Streams a narrative via tool_use. Yields `json_delta` events containing
 * partial JSON from the `input_json_delta` stream events, then a final
 * `done` event with the parsed NarrativeOutput.
 *
 * The caller (summarizeTurn) forwards these as SSE frames so the Swift
 * client can show "generating…" immediately (~1s) instead of waiting
 * for the full response (~8s).
 */
export async function* streamAnthropic(
  client: Anthropic,
  args: CallArgs
): AsyncGenerator<NarrativeStreamEvent> {
  const { system, user } = narrativeRequest(args);

  const stream = client.messages.stream({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: [cacheableSystemBlock({ model: MODEL, text: system, tools: NARRATIVE_TOOL })],
    tools: [NARRATIVE_TOOL as any],
    tool_choice: { type: "tool", name: "record_narrative" },
    messages: [{ role: "user", content: user }]
  });

  let jsonAccumulator = "";

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "input_json_delta"
    ) {
      const chunk = event.delta.partial_json;
      jsonAccumulator += chunk;
      yield { type: "json_delta", text: chunk };
    }
  }

  // Parse the accumulated JSON into a NarrativeOutput
  const final = await stream.finalMessage();
  const cacheHit = ((final.usage as any)?.cache_read_input_tokens ?? 0) > 0;

  // Try to get structured output from the tool_use block first
  let narrative: NarrativeOutput | undefined;
  for (const block of final.content) {
    if (block.type === "tool_use" && block.name === "record_narrative") {
      narrative = coerceNarrative(block.input) ?? undefined;
    }
  }

  if (!narrative) {
    // Fallback: try parsing the accumulated JSON
    try {
      narrative = JSON.parse(jsonAccumulator) as NarrativeOutput;
    } catch {
      yield { type: "error", error: "Failed to parse narrative from stream" };
      return;
    }
  }

  yield { type: "done", narrative, model: MODEL, cache_hit: cacheHit };
}

/**
 * Calls Claude Haiku with tool use enforced. Returns parsed narrative or
 * throws on malformed response / SDK error.
 */
export async function callAnthropic(
  client: Anthropic,
  args: CallArgs
): Promise<NarrativeOutput> {
  const { system, user } = narrativeRequest(args);

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: [cacheableSystemBlock({ model: MODEL, text: system, tools: NARRATIVE_TOOL })],
    tools: [NARRATIVE_TOOL as any],
    tool_choice: { type: "tool", name: "record_narrative" },
    messages: [{ role: "user", content: user }]
  });

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === "record_narrative") {
      const narrative = coerceNarrative(block.input);
      if (narrative) return narrative;
    }
  }
  throw new Error("Anthropic response missing valid record_narrative tool use");
}
