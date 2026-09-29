"""The record of a run. Slack is a notification about this, not the record."""

import html as html_mod
import json
import os
import time
from dataclasses import dataclass, field

from smoke.lib.result import ERROR, FAIL, PASS, SKIP, run_verdict

STATUS_MARK = {PASS: "PASS", FAIL: "FAIL", ERROR: "ERROR", SKIP: "SKIP"}


@dataclass
class Report:
    build: object
    results: list = field(default_factory=list)
    mode: str = "installed build"
    started: float = 0.0
    finished: float = 0.0
    # The app this run launched would not quit. The founder has to know: it
    # holds the LevelDB lock and will look like THEIR app to the next run.
    app_left_running: bool = False

    def verdict(self):
        return run_verdict(self.results)

    def duration(self):
        return self.finished - self.started

    def to_dict(self):
        return {
            "verdict": self.verdict(),
            "mode": self.mode,
            "duration": self.duration(),
            "started": self.started,
            "app_left_running": self.app_left_running,
            "build": self.build.to_dict(),
            "results": [r.to_dict() for r in self.results],
        }


def run_dir(root, when=None):
    stamp = time.strftime("%Y-%m-%d-%H%M%S", time.localtime(when if when is not None else time.time()))
    path = os.path.join(root, stamp)
    os.makedirs(path, exist_ok=True)
    return path


def write_json(report, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(report.to_dict(), f, indent=2)


def write_html(report, path):
    rows = []
    for r in report.results:
        rows.append(
            "<tr><td>%s</td><td>%s</td><td>%.1fs</td><td>%s</td></tr>"
            % (
                html_mod.escape(STATUS_MARK.get(r.status, r.status)),
                html_mod.escape(r.name),
                r.duration,
                html_mod.escape(r.detail),
            )
        )
    body = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Codepet smoke %s</title>"
        "<style>body{font:14px -apple-system,sans-serif;margin:2rem;}"
        "table{border-collapse:collapse}td{padding:.3rem .8rem;border-bottom:1px solid #ddd}"
        "</style></head><body>"
        "<h1>Codepet smoke &mdash; %s</h1>"
        "<p>%s &middot; %s &middot; %.0fs</p>"
        "<table>%s</table></body></html>"
    ) % (
        html_mod.escape(report.verdict()),
        html_mod.escape(report.build.label()),
        html_mod.escape(report.verdict()),
        html_mod.escape(report.mode),
        report.duration(),
        "".join(rows),
    )
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
