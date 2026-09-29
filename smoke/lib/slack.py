"""Post the verdict to Slack.

Slack never rewrites the verdict. The local report is the record; this is a
notification about it. A failed post leaves the run exactly as the checks
found it -- a green run whose message did not deliver is still a green run.
"""

import json
import os
import urllib.error
import urllib.request

from smoke.lib.result import ERROR, FAIL, GREEN, PASS, SKIP

MARK = {PASS: "✅", FAIL: "❌", ERROR: "⚠️", SKIP: "⏭️"}
VERDICT_MARK = {"green": "\U0001F7E2", "red": "\U0001F534", "unverified": "⚠️"}


def _duration(seconds):
    m, s = divmod(int(seconds), 60)
    return "%dm%02ds" % (m, s) if m else "%ds" % s


def format_message(report):
    head = "%s Codepet smoke — %s  ·  %s  ·  %s" % (
        VERDICT_MARK.get(report.verdict(), "⚠️"),
        report.build.label(),
        report.mode,
        _duration(report.duration()),
    )
    lines = [head]
    for r in report.results:
        lines.append("%s %-10s %s" % (MARK.get(r.status, "?"), r.name.title(), r.detail))
    for r in report.results:
        for e in r.evidence:
            lines.append("   %s" % e)
    return "\n".join(lines)


def should_post(mode, verdict, previous_verdict):
    """Watch mode speaks only when the verdict CHANGES."""
    if mode != "watch":
        return True
    return previous_verdict != verdict


def read_webhook(path):
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            url = f.read().strip()
        return url or None
    except FileNotFoundError:
        return None


def post(webhook_url, text):
    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status == 200, "posted"
    except urllib.error.URLError as e:
        return False, "slack post failed: %s" % e
