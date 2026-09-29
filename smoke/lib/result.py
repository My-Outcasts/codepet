"""The one record every check returns, and how a run's verdict is computed.

The four statuses are not cosmetic. scripts/ci-test.sh once reported a test
target that failed to COMPILE as a dead host -- in green, having verified
nothing at all. A check that could not run must never read as a check that
passed, so "the harness broke" and "the product broke" are different words
here, and neither of them is a pass.
"""

from dataclasses import asdict, dataclass, field

PASS = "pass"
FAIL = "fail"
ERROR = "error"
SKIP = "skip"

GREEN = "green"
RED = "red"
UNVERIFIED = "unverified"


@dataclass
class Result:
    name: str
    status: str
    duration: float = 0.0
    detail: str = ""
    evidence: list = field(default_factory=list)

    def to_dict(self):
        return asdict(self)


def run_verdict(results):
    """RED if anything failed or errored, GREEN only if something passed."""
    if any(r.status in (FAIL, ERROR) for r in results):
        return RED
    if any(r.status == PASS for r in results):
        return GREEN
    return UNVERIFIED


def skip_rest(names, reason):
    """Mark downstream checks skipped so the report names ONE broken thing."""
    return [Result(name=n, status=SKIP, detail=reason) for n in names]
