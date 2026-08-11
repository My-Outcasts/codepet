//
// Shared by every engineering-handler leak test. Two channels carry logs in
// this codebase — bare `console` (engWebhook, engSendTurn) and
// `firebase-functions/logger` (engStream, and engStartRun per Finding 5) —
// and a leak assertion that only spies on one is blind to a secret logged
// through the other. `spyOnLogs` covers both from one call site so no test
// file has to remember to wire up the second channel itself.
import * as logger from "firebase-functions/logger";

/**
 * Whether `marker` shows up anywhere in a logged call — including inside an
 * `Error`'s `message`/`stack`. Bare `JSON.stringify` under-detects this:
 * `message` and `stack` are non-enumerable on `Error`, so
 * `JSON.stringify(new Error("secret"))` is `"{}"` and would hide a leaked
 * secret carried on a raw error object — exactly the regression shape a
 * leak test exists to catch (a call site swapping a picked-field object for
 * the raw `err`). Real `console.error(err)`/`logger.error(err)` print the
 * message and stack via `util.inspect`, so this check has to look there
 * too or the assertion is not load-bearing against that regression.
 */
export function callsContainMarker(calls: unknown[][], marker: string): boolean {
  const seen = new Set<unknown>();
  const valueContains = (value: unknown): boolean => {
    if (value == null) return false;
    if (typeof value === "string") return value.includes(marker);
    if (value instanceof Error) {
      return value.message.includes(marker) || (value.stack ?? "").includes(marker);
    }
    if (typeof value === "object") {
      if (seen.has(value)) return false;
      seen.add(value);
      return Object.values(value as Record<string, unknown>).some(valueContains);
    }
    return false;
  };
  return calls.some((call) => call.some(valueContains));
}

/**
 * Spies on every log sink a handler in this codebase might write to —
 * `console.error/warn/log` AND `firebase-functions/logger`'s `error/warn/log`
 * — and hands back one combined view. Works whether or not the test file
 * has also called `jest.mock("firebase-functions/logger", ...)`: `spyOn`
 * wraps whatever function is currently on the property, mocked or real.
 */
export function spyOnLogs() {
  const consoleError = jest.spyOn(console, "error").mockImplementation(() => undefined);
  const consoleWarn = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  const consoleLog = jest.spyOn(console, "log").mockImplementation(() => undefined);
  const loggerError = jest.spyOn(logger, "error").mockImplementation(() => undefined);
  const loggerWarn = jest.spyOn(logger, "warn").mockImplementation(() => undefined);
  const loggerLog = jest.spyOn(logger, "log").mockImplementation(() => undefined);

  const allCalls = (): unknown[][] => [
    ...consoleError.mock.calls,
    ...consoleWarn.mock.calls,
    ...consoleLog.mock.calls,
    ...loggerError.mock.calls,
    ...loggerWarn.mock.calls,
    ...loggerLog.mock.calls
  ];

  return {
    allCalls,
    containsMarker: (marker: string) => callsContainMarker(allCalls(), marker),
    restore: () => {
      consoleError.mockRestore();
      consoleWarn.mockRestore();
      consoleLog.mockRestore();
      loggerError.mockRestore();
      loggerWarn.mockRestore();
      loggerLog.mockRestore();
    }
  };
}
