"""Run the checks in order, and never invent a verdict.

Teardown lives in a finally: a crashed check must not leave the app holding
the LevelDB lock and blocking the next xcodebuild test.

Two stores are read, and they are not the same store: auth reads the
Firestore LevelDB (db_dir), chat reads the local chat transcript under
~/.codepet/accounts/<uid>/ (uid, accounts_root) -- the app stopped writing
chat to Firestore on 25 September.
"""

import os
import time

from smoke.checks import auth as auth_check
from smoke.checks import chat as chat_check
from smoke.checks import launch as launch_check
from smoke.checks import task as task_check
from smoke.lib import build as build_lib
from smoke.lib import drive, store
from smoke.lib.logstream import Capture
from smoke.lib.report import Report, run_dir, write_html, write_json
from smoke.lib.result import ERROR, FAIL, Result, skip_rest

ORDER = ["launch", "auth", "chat", "task"]


def order():
    return list(ORDER)


def downstream_of(name):
    return ORDER[ORDER.index(name) + 1:]


def _guarded(name, fn, *args, **kw):
    """A check that blows up is an ERROR result, never an escape."""
    t0 = time.time()
    try:
        return fn(*args, **kw)
    except Exception as e:  # not BaseException: let Ctrl-C through
        return Result(name, ERROR, time.time() - t0,
                      "check crashed: %s: %s" % (type(e).__name__, e))


def execute(app_path, mode, with_task, account, db_dir=None, runs_root=None,
            uid=None, accounts_root=None):
    db_dir = db_dir or store.DEFAULT_DB
    runs_root = runs_root or os.path.join(os.path.dirname(__file__), "..", "runs")
    started = time.time()
    where = run_dir(os.path.abspath(runs_root))
    results = []

    try:
        target = build_lib.identify(app_path)
    except build_lib.BuildMissing:
        target = build_lib.Build(app_path, "?", "?", "?", False,
                                 "no bundle at %s" % app_path, False, 0.0)

    with Capture(os.path.join(where, "log.txt")) as capture:
        try:
            first = _guarded("launch", launch_check.run, app_path,
                             evidence_dir=where,
                             assess_gatekeeper=(mode != "local build"))
            results.append(first)
            if first.status in (FAIL, ERROR):
                results.extend(skip_rest(downstream_of("launch"),
                                         "launch %s" % first.status))
            else:
                token = chat_check.mint_token()
                chat = _guarded("chat", chat_check.run, token, capture,
                                uid=uid, accounts_root=accounts_root)
                # chat may return early without quitting; auth must read a
                # released lock whatever happened.
                drive.quit_app()
                results.append(_guarded("auth", auth_check.run, account,
                                        db_dir=db_dir))
                results.append(chat)
                if chat.status in (FAIL, ERROR):
                    results.extend(skip_rest(downstream_of("chat"),
                                             "chat %s" % chat.status))
                elif with_task:
                    # Only pay for a relaunch when the task check will really run.
                    try:
                        drive.launch(app_path)
                    except drive.DriveError as e:
                        results.append(Result(
                            "task", ERROR, 0.0,
                            "could not relaunch the app for the task check: %s" % e))
                    else:
                        drive.wait_until(drive.is_running, timeout=45)
                        results.append(_guarded(
                            "task", task_check.run, chat_check.mint_token(),
                            capture, True, db_dir=db_dir))
                else:
                    results.append(task_check.evaluate(
                        False, False, False, "", None))
        finally:
            drive.quit_app()

    # Put the results back in declared order so the report always reads the same.
    results.sort(key=lambda r: ORDER.index(r.name) if r.name in ORDER else 99)
    report = Report(build=target, results=results, mode=mode,
                    started=started, finished=time.time())
    write_json(report, os.path.join(where, "report.json"))
    write_html(report, os.path.join(where, "report.html"))
    return report, where
