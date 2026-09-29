"""Identify the binary under test. Every report states which build it judged.

The mtime is read from Info.plist because that is what changes on a rebuild,
and because "still looks the same" has meant "you are testing yesterday's
binary" often enough in this project to be worth a machine check.
"""

import os
import plistlib
import subprocess
from dataclasses import asdict, dataclass


class BuildMissing(Exception):
    """There is no app bundle at that path."""


@dataclass
class Build:
    path: str
    short_version: str
    bundle_version: str
    bundle_id: str
    signed: bool
    signature: str
    quarantined: bool
    mtime: float

    def label(self):
        return "%s (%s)" % (self.short_version, self.bundle_version)

    def to_dict(self):
        return asdict(self)


def _info_path(app_path):
    return os.path.join(app_path, "Contents", "Info.plist")


def read_info(app_path):
    try:
        with open(_info_path(app_path), "rb") as f:
            return plistlib.load(f)
    except FileNotFoundError:
        raise BuildMissing(app_path)


def parse_codesign(returncode, stderr):
    """`codesign -v` exits 0 and says nothing at all when the bundle is valid."""
    if returncode == 0:
        return True, "valid on disk"
    lines = [l.strip() for l in (stderr or "").splitlines() if l.strip()]
    return False, lines[0] if lines else "unknown signing failure"


def parse_quarantine(xattr_stdout):
    return "com.apple.quarantine" in (xattr_stdout or "")


def identify(app_path):
    info = read_info(app_path)
    cs = subprocess.run(
        ["/usr/bin/codesign", "-v", app_path], capture_output=True, text=True
    )
    signed, signature = parse_codesign(cs.returncode, cs.stderr)
    xa = subprocess.run(["/usr/bin/xattr", app_path], capture_output=True, text=True)
    return Build(
        path=app_path,
        short_version=str(info.get("CFBundleShortVersionString", "?")),
        bundle_version=str(info.get("CFBundleVersion", "?")),
        bundle_id=str(info.get("CFBundleIdentifier", "?")),
        signed=signed,
        signature=signature,
        quarantined=parse_quarantine(xa.stdout),
        mtime=os.path.getmtime(_info_path(app_path)),
    )
