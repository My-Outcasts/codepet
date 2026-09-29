"""Fetch and mount the shipped disk image.

This exists because the artefact under test should be the one a user actually
downloads, not one already sitting on this Mac. Download, mount, copy and
detach are steps with ways to go wrong, and doing them by hand is what this
whole tool is replacing. The launch check judges the copy by Gatekeeper
(spctl), not by the quarantine flag it inherits from the download.

The IMAGE is judged too, before it is mounted. A disk image is its own code
object: CLAUDE.md's release failure #4 was an unsigned .dmg that notarytool
and stapler both accepted and every user's Mac would have refused, and
`spctl -a -t open` was the one check that caught it. So a rejected image is
a FAIL -- the shipped artefact is broken -- not a harness problem.

Every failure is a DmgError carrying the launch status it should become:
FAIL when the artefact is at fault (a 404 on the download page, a rejected
image), ERROR when we merely could not get at it.

Nothing in /Applications is touched. Replacing an installed app is the
founder's decision, so the copy lands in a working directory.
"""

import glob
import os
import shutil
import subprocess
import urllib.error
import urllib.request

from smoke.lib import build as build_lib
from smoke.lib.result import ERROR, FAIL

DEFAULT_URL = "https://code-pet.com/download/Codepet.dmg"


class DmgError(Exception):
    """The image could not be fetched, mounted, or read -- or was rejected.

    `status` is what the launch result becomes: FAIL or ERROR.
    """

    def __init__(self, message, status=ERROR):
        super().__init__(message)
        self.status = status


def download(url, dest):
    try:
        urllib.request.urlretrieve(url, dest)
    except urllib.error.HTTPError as e:
        # A 404 on the download page IS the product being broken: the link a
        # user clicks leads nowhere. Anything else may be this Mac's network.
        raise DmgError("could not download %s: HTTP %d" % (url, e.code),
                       FAIL if e.code == 404 else ERROR)
    except OSError as e:
        raise DmgError("could not download %s: %s" % (url, e))
    return dest


def assess_image(image):
    """Gatekeeper's verdict on the disk image itself, as a user's Mac opens it."""
    try:
        r = subprocess.run(
            ["/usr/sbin/spctl", "-a", "-t", "open",
             "--context", "context:primary-signature", "-vv", image],
            capture_output=True, text=True,
        )
    except OSError as e:
        raise DmgError("could not assess the disk image: %s" % e)
    accepted, detail = build_lib.parse_spctl(r.returncode, r.stderr or r.stdout)
    if not accepted:
        raise DmgError("the disk image is not signed/notarized: %s" % detail, FAIL)
    return detail


def parse_mount_point(hdiutil_stdout):
    for row in (hdiutil_stdout or "").splitlines():
        fields = [f.strip() for f in row.split("\t") if f.strip()]
        if fields and fields[-1].startswith("/Volumes/"):
            return fields[-1]
    raise DmgError("hdiutil mounted nothing under /Volumes")


def parse_device(hdiutil_stdout):
    for row in (hdiutil_stdout or "").splitlines():
        for f in row.split("\t"):
            if f.strip().startswith("/dev/disk"):
                return f.strip()
    return None


def app_in(mount_point):
    found = glob.glob(os.path.join(mount_point, "*.app"))
    if not found:
        raise DmgError("no .app bundle on %s" % mount_point)
    return found[0]


def install(url, workdir):
    """Download, mount, copy out, detach. Returns the local app path."""
    os.makedirs(workdir, exist_ok=True)
    image = download(url, os.path.join(workdir, "Codepet.dmg"))
    assess_image(image)

    attach = subprocess.run(
        ["/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", image],
        capture_output=True, text=True,
    )
    if attach.returncode != 0:
        raise DmgError((attach.stderr or "hdiutil attach failed").strip())

    device = parse_device(attach.stdout)
    mount_point = None
    failure = None
    target = None
    try:
        mount_point = parse_mount_point(attach.stdout)
        source = app_in(mount_point)
        target = os.path.join(workdir, os.path.basename(source))
        try:
            if os.path.exists(target):
                shutil.rmtree(target)
            shutil.copytree(source, target, symlinks=True)
        except OSError as e:
            raise DmgError("could not copy %s: %s" % (source, e))
    except DmgError as e:
        failure = e
        raise
    finally:
        where = mount_point or device
        if where:
            d = subprocess.run(["/usr/bin/hdiutil", "detach", where],
                               capture_output=True)
            if d.returncode != 0 and failure is None:
                raise DmgError("could not detach %s" % where)
    return target
