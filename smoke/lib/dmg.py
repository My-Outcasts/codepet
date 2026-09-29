"""Fetch and mount the shipped disk image.

This exists because the artefact under test should be the one a user actually
downloads, not one already sitting on this Mac. Download, mount, copy and
de-quarantine are four steps with four ways to go wrong, and doing them by
hand is what this whole tool is replacing.

Nothing in /Applications is touched. Replacing an installed app is the
founder's decision, so the copy lands in a working directory.
"""

import glob
import os
import shutil
import subprocess
import urllib.request

DEFAULT_URL = "https://code-pet.com/download/Codepet.dmg"


class DmgError(Exception):
    """The image could not be fetched, mounted, or read."""


def download(url, dest):
    try:
        urllib.request.urlretrieve(url, dest)
    except OSError as e:
        raise DmgError("could not download %s: %s" % (url, e))
    return dest


def parse_mount_point(hdiutil_stdout):
    for row in (hdiutil_stdout or "").splitlines():
        fields = [f.strip() for f in row.split("\t") if f.strip()]
        if fields and fields[-1].startswith("/Volumes/"):
            return fields[-1]
    raise DmgError("hdiutil mounted nothing under /Volumes")


def app_in(mount_point):
    found = glob.glob(os.path.join(mount_point, "*.app"))
    if not found:
        raise DmgError("no .app bundle on %s" % mount_point)
    return found[0]


def install(url, workdir):
    """Download, mount, copy out, detach. Returns the local app path."""
    os.makedirs(workdir, exist_ok=True)
    image = download(url, os.path.join(workdir, "Codepet.dmg"))

    attach = subprocess.run(
        ["/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", image],
        capture_output=True, text=True,
    )
    if attach.returncode != 0:
        raise DmgError((attach.stderr or "hdiutil attach failed").strip())

    mount_point = parse_mount_point(attach.stdout)
    try:
        source = app_in(mount_point)
        target = os.path.join(workdir, os.path.basename(source))
        if os.path.exists(target):
            shutil.rmtree(target)
        shutil.copytree(source, target, symlinks=True)
    finally:
        subprocess.run(["/usr/bin/hdiutil", "detach", mount_point],
                       capture_output=True)
    return target
