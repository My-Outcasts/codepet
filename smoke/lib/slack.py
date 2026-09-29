"""Post the verdict to Slack.

Slack never rewrites the verdict. The local report is the record; this is a
notification about it. A failed post leaves the run exactly as the checks
found it -- a green run whose message did not deliver is still a green run.
"""

import http.client
import json
import os
import urllib.error
import urllib.request

from smoke.lib.result import ERROR, FAIL, PASS, SKIP

MARK = {PASS: "✅", FAIL: "❌", ERROR: "⚠️", SKIP: "⏭️"}
VERDICT_MARK = {"green": "\U0001F7E2", "red": "\U0001F534", "unverified": "⚠️"}

_SLACK_ESCAPE = str.maketrans({"&": "&amp;", "<": "&lt;", ">": "&gt;"})


def _duration(seconds):
    m, s = divmod(int(seconds), 60)
    return "%dm%02ds" % (m, s) if m else "%ds" % s


def _cap_and_escape(text, limit=300):
    """Cap text at limit chars, escape Slack markup, append ellipsis if cut."""
    text = text.translate(_SLACK_ESCAPE)
    if len(text) > limit:
        return text[:limit - 1] + "…"
    return text


def format_message(report):
    # The label and mode come from a bundle's Info.plist and a CLI string;
    # a "<" in either would be read by Slack as markup.
    head = "%s Codepet smoke — %s  ·  %s  ·  %s" % (
        VERDICT_MARK.get(report.verdict(), "⚠️"),
        report.build.label().translate(_SLACK_ESCAPE),
        report.mode.translate(_SLACK_ESCAPE),
        _duration(report.duration()),
    )
    lines = [head]
    for r in report.results:
        detail = r.detail.replace("\n", " ")
        lines.append("%s %-10s %s" % (MARK.get(r.status, "?"), r.name.title(), _cap_and_escape(detail)))
    for r in report.results:
        if r.status not in (FAIL, ERROR):
            continue
        for e in r.evidence:
            first_line = e.split("\n")[0]
            lines.append("   %s" % _cap_and_escape(first_line))
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
    except (FileNotFoundError, OSError, UnicodeDecodeError):
        return None


def post(webhook_url, text):
    payload = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            ok = resp.status == 200
            return ok, "posted" if ok else "slack returned %d" % resp.status
    except urllib.error.URLError as e:
        return False, "slack post failed: URLError: %s" % e.reason
    except (OSError, ValueError, http.client.HTTPException) as e:
        return False, "slack post failed: %s" % e.__class__.__name__
