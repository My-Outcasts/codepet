/**
 * A conversation flattened into one prompt.
 *
 * Shared by every local path that has a history to send: chat (`chatSidecar`) and the
 * learning layer's session chat (`chatSession`). One implementation because the FRAMING is
 * part of the prompt — "Earlier in this conversation:", and who is called what — and two
 * copies of that framing is two different conversations.
 */

/** Structurally what both callers already have: a role and either text or content blocks. */
export interface TranscriptMessage {
  role: "user" | "assistant";
  content: string | unknown[];
}

/**
 * Render the built messages as ONE prompt string.
 *
 * **This is the one place the local path cannot match the HTTP path, and it is a
 * deliberate compromise rather than an oversight.** `claude -p` takes a single prompt on
 * stdin; it has no messages array. So a multi-turn conversation that reaches the API as
 * structured user/assistant turns reaches Claude Code as a labelled transcript followed by
 * the current turn. The words are identical — `buildChatRequest` produced them — but the
 * ROLE STRUCTURE is flattened, and a model reads a transcript slightly differently from a
 * real turn history.
 *
 * **There is no better shape available, and that was measured rather than assumed.**
 * `--input-format stream-json` looked like the faithful alternative and is not:
 *
 *   - A seeded `assistant` message costs no turn but is DROPPED. Sent one followed by a
 *     question about it, the model answered "I don't have any prior context in this
 *     conversation establishing a company name."
 *   - Every `user` message triggers its own generation. Three input messages produced two
 *     `result` frames, so replaying an N-turn history would cost N generations of the
 *     founder's quota and N× the latency.
 *
 *   An earlier reading of the first experiment concluded it DID work — the model repeated a
 *   name from the injected history. It knew the name because the first user turn had
 *   actually run and answered it; the injected assistant message played no part. The
 *   minimal two-message case is what separated those.
 *
 * So flattening is not a first cut to be improved later. It is the only shape `claude -p`
 * supports, and the divergence from the HTTP path is permanent for this transport.
 *
 * Attachments cannot ride a text prompt. They are named rather than dropped silently, so a
 * founder who attached a screenshot sees that it was not read instead of wondering why the
 * answer ignores it.
 */
export function flattenTranscript(messages: TranscriptMessage[]): string {
  const text = (content: TranscriptMessage["content"]): string => {
    if (typeof content === "string") return content;
    return content
      .map((b) => {
        const blk = b as { type?: string; text?: string };
        if (blk.type === "text") return blk.text ?? "";
        return `[attachment omitted: ${blk.type ?? "unknown"} — this path cannot read files]`;
      })
      .filter(Boolean)
      .join("\n");
  };

  if (!messages.length) return "";
  const history = messages.slice(0, -1);
  const current = messages[messages.length - 1];

  const parts: string[] = [];
  if (history.length) {
    parts.push("Earlier in this conversation:");
    for (const m of history) {
      parts.push(`${m.role === "user" ? "Founder" : "You"}: ${text(m.content)}`);
    }
    parts.push("");
  }
  parts.push(text(current.content));
  return parts.join("\n");
}
