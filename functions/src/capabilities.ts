// Which skills this backend actually implements, so the app can tell a built
// toolkit item from an unbuilt one.
//
// It exists to keep a property the client would otherwise have to give up:
// `IMPLEMENTED_SKILLS` is the authority on what a turn can do, so shipping a
// skill must stay a backend deploy rather than a client release. Exporting that
// same array — rather than maintaining a second manifest that can disagree with
// it — is the whole design.
//
// Deliberately UNAUTHENTICATED: the response is a static constant naming which
// features exist, with no founder data in it. That is what lets the Environment
// tab resolve its state on first paint without a token round-trip.
import type { Request } from "firebase-functions/v2/https";
import type { Response } from "express";
import { IMPLEMENTED_SKILLS } from "./companyChatCore";

/**
 * The response body. Pure and separately tested, mirroring the
 * companyChatCore / companyChat split — the handler below stays a shell so
 * there is nothing in it worth faking an express `Response` to reach.
 *
 * Spreads into a new array so a caller cannot mutate the module constant.
 */
export function capabilitiesPayload(): { skills: string[] } {
  return { skills: [...IMPLEMENTED_SKILLS] };
}

export function handleCapabilities(_req: Request, res: Response): void {
  // Five minutes: long enough that opening the tab repeatedly costs nothing,
  // short enough that a founder sees a newly deployed skill the same session.
  res.set("Cache-Control", "public, max-age=300");
  res.json(capabilitiesPayload());
}
