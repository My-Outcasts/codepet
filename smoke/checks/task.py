"""Check 4 -- does a task run to a deliverable?

Opt-in, because a real task run spends real credits. Watch mode never
requests it.

For now a REQUESTED task check is a SKIP that drives nothing and spends
nothing, and it says why: the spec's verdict is "a terminal state with a
deliverable", and nothing this tool can read yet is specific to one task
record. The earlier version typed a probe asking for a deliverable titled
with the reversed token and looked for that string -- but a plain chat reply
that echoes the title satisfies it, so a PASS would have meant "something
replied", which the chat check already proves. The same lesson came first
from the bare word "deliverable": a scan of the live store on 24 September
found it 15 times before any run, so a needle that is not record-specific is
green forever and believed.

When the app exposes a task- or deliverable-specific signal, this is the
check to fill in; until then SKIP is the honest status, and it never turns a
run green on its own (run_verdict needs a PASS).
"""

from smoke.lib.result import SKIP, Result

NAME = "task"

NOT_REQUESTED = "not requested (pass --with-task to spend credits)"
NOT_VERIFIABLE = "task outcome not yet verifiable (no record-specific needle)"


def evaluate(requested):
    if not requested:
        return Result(NAME, SKIP, 0.0, NOT_REQUESTED)
    return Result(NAME, SKIP, 0.0, NOT_VERIFIABLE)


def run(token, capture, requested, **_):
    """Drives nothing, in either case. See the module docstring."""
    return evaluate(requested)
