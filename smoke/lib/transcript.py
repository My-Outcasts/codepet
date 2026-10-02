"""Read the company chat transcript the app keeps on disk.

Since 25 September the app keeps the company chat in a local JSON file per
account, ~/.codepet/accounts/<uid>/company_chats.json, and "never Firestore"
(codepet/Services/ChatThreadArchive.swift:5-10). A chat reply therefore cannot
be found in the Firestore LevelDB at all, which is what this tool used to scan.

The schema below is derived from the Swift source, not from a real file -- no
founder's transcript was read to write this. Every field relied on is cited
next to the line that reads it. The first real run is the confirmation.

File shape (ChatThreadArchive.swift:51, :65):

    [                                   # [StoredThread], JSONEncoder, dates as ms numbers
      {"id": str, "title": str?,        # StoredThread, :71-77
       "createdAt": ms, "updatedAt": ms,
       "kind": "ask" | "dev",           # ChatThreadKind, Managers/ChatThreads.swift:12-15
       "messages": [                    # in conversation order (CompanyStore.swift:1558-1573
                                        # writes chatMessages into the thread as-is)
         {"id": str, "fromFounder": bool,   # StoredMessage, :97-101; fromFounder = role == .me (:127)
          "createdAt": ms, "text": str,
          "draftApproved": bool, ...optional fields omitted when nil}
       ]}
    ]
"""

import json
import os
import re
import tempfile
from dataclasses import dataclass, field

ACCOUNTS_ROOT = os.path.expanduser("~/.codepet/accounts")
# ChatThreadArchive.swift:33 -- <root>/<uid>/company_chats.json
FILENAME = "company_chats.json"
UID_ENV = "CODEPET_SMOKE_UID"


class TranscriptMissing(Exception):
    """We could not find or read the transcript. We could not look -- ERROR, not FAIL."""


class TranscriptUnreadable(TranscriptMissing):
    """The file is there but is not the shape the Swift source writes."""


def _safe_uid(uid):
    # The app strips a uid to letters, digits, "-" and "_" before using it as a
    # directory name, and an empty result becomes "unknown"
    # (ChatThreadArchive.swift:32-33). Mirror it, or a uid with any other
    # character would point at a directory the app never writes.
    safe = "".join(c for c in uid if c.isalnum() or c in "-_")
    return safe or "unknown"


def resolve_account_dir(uid=None, root=None, env=None):
    """--uid, else $CODEPET_SMOKE_UID, else the ONE account dir there is.

    More than one account dir with no uid given is an error rather than a
    guess: reading the wrong founder's transcript would report on the wrong
    account and look perfectly healthy.
    """
    root = root or ACCOUNTS_ROOT
    env = os.environ if env is None else env
    uid = uid or env.get(UID_ENV)
    if uid:
        path = os.path.join(root, _safe_uid(uid))
        if not os.path.isdir(path):
            raise TranscriptMissing("no account directory at %s" % path)
        return path
    try:
        dirs = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
    except OSError:
        raise TranscriptMissing("no accounts directory at %s" % root)
    if len(dirs) != 1:
        raise TranscriptMissing(
            "%d account directories under %s; pass --uid or set %s"
            % (len(dirs), root, UID_ENV))
    return os.path.join(root, dirs[0])


@dataclass
class Message:
    from_founder: bool
    text: str


@dataclass
class Thread:
    id: str
    messages: list = field(default_factory=list)


def reply_needle(token):
    """The token in capitals. Matched case-sensitively, so it is absent from
    the probe, which carries the token in lower case.

    It was the token reversed until 1 Oct, when a real round trip came back
    `7595e048f0d` for `7595e0f48f0d`: the chat worked and the model dropped a
    character reversing hex, so the check read a working build as FAIL.
    Upper-casing is a copy, which models do not get wrong.
    """
    return token.upper()


@dataclass
class Transcript:
    threads: list = field(default_factory=list)

    def contains(self, needle):
        """Any message, either side, any thread."""
        if not needle:
            raise ValueError("an empty needle matches everything")
        return any(needle in m.text for t in self.threads for m in t.messages)

    def probe_seen(self, token):
        """A FOUNDER message carrying the token -- our keystrokes reached the chat."""
        return any(m.from_founder and token in m.text
                   for t in self.threads for m in t.messages)

    def reply_seen(self, token):
        """A founder message with the token, then LATER in the same thread a
        companion message with reply_needle(token).

        Same thread and later, because a needle sitting in some other
        conversation, or before our probe, is not a reply to it.
        """
        needle = reply_needle(token)
        for t in self.threads:
            asked = False
            for m in t.messages:
                if m.from_founder and token in m.text:
                    asked = True
                elif asked and not m.from_founder and needle in m.text:
                    return True
        return False


def _parse(raw):
    if not isinstance(raw, list):
        raise TranscriptUnreadable("top level is %s, not a thread list" % type(raw).__name__)
    threads = []
    for t in raw:
        if not isinstance(t, dict) or not isinstance(t.get("messages"), list):
            raise TranscriptUnreadable("a thread without a messages list")
        messages = []
        for m in t["messages"]:
            # StoredMessage.fromFounder: Bool and .text: String are both
            # non-optional (ChatThreadArchive.swift:99, :101), so a message
            # missing either is not something the app wrote.
            if (not isinstance(m, dict) or not isinstance(m.get("fromFounder"), bool)
                    or not isinstance(m.get("text"), str)):
                raise TranscriptUnreadable("a message without fromFounder/text")
            messages.append(Message(m["fromFounder"], m["text"]))
        threads.append(Thread(str(t.get("id", "")), messages))
    return Transcript(threads)


def load(account_dir):
    """The transcript as it is on disk now.

    Safe to call while the app runs: every save is `data.write(options: .atomic)`
    (ChatThreadArchive.swift:55), so a read sees the old file or the new one,
    never half of one. But saves are queued async (:52), so the VERDICT read
    happens after the app has quit.

    No file is an empty transcript: an account that has never chatted has no
    file yet (it is created on first save, :54).
    """
    path = os.path.join(account_dir, FILENAME)
    try:
        with open(path, "rb") as f:
            data = f.read()
    except FileNotFoundError:
        return Transcript([])
    except OSError as e:
        raise TranscriptMissing("could not read %s: %s" % (path, e))
    try:
        raw = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e:
        raise TranscriptUnreadable("%s is not JSON: %s" % (path, e))
    return _parse(raw)


# The exact probe smoke/checks/chat.py types (probe_text), token captured and required to
# repeat. Exact on purpose: scrub() deletes what this matches from a founder's real
# transcript, so a founder who happened to write "smoke test" must never match.
PROBE_RE = re.compile(
    r"^smoke test ([0-9a-f]{8,32}) -- reply with this code in capital letters, "
    r"nothing else: \1$")


def is_probe(text):
    return bool(PROBE_RE.match(text))


def _scrub_threads(raw):
    """(threads without smoke turns, how many messages went).

    A smoke turn is a founder message that is a probe, plus every companion message after
    it up to the next founder message -- the reply, and anything the app attached to it.
    A thread left with no messages is dropped, so RECENT loses its "smoke test ..." row.
    Everything else is passed through untouched, field for field.
    """
    kept, removed = [], 0
    for t in raw:
        messages, skipping = [], False
        for m in t.get("messages", []):
            if m.get("fromFounder") is True:
                skipping = is_probe(m.get("text", ""))
            if skipping:
                removed += 1
            else:
                messages.append(m)
        if messages:
            kept.append(dict(t, messages=messages) if len(messages) != len(t["messages"]) else t)
    return kept, removed


def scrub(account_dir):
    """Remove every smoke turn from the account's transcript; return how many messages went.

    Build 6 end-to-end test, bug #11: every smoke run left a "smoke test ..." chat in the
    founder's RECENT list, on the founder's real account.

    Call ONLY with the app quit. The app holds its threads in memory and re-saves the
    whole list (ChatThreadArchive.save), so a scrub under a running app is overwritten by
    its next save. The write is atomic (temp file + rename), like the app's own (:55).
    Leftovers from earlier runs match too, so the first scrub also clears those.
    """
    path = os.path.join(account_dir, FILENAME)
    try:
        with open(path, "rb") as f:
            raw = json.loads(f.read().decode("utf-8"))
    except FileNotFoundError:
        return 0
    except (OSError, UnicodeDecodeError, ValueError) as e:
        raise TranscriptMissing("could not read %s: %s" % (path, e))
    _parse(raw)  # refuse to rewrite a file that is not the shape the app writes
    kept, removed = _scrub_threads(raw)
    if not removed:
        return 0
    fd, tmp = tempfile.mkstemp(dir=account_dir, prefix=".company_chats.", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(kept, f, ensure_ascii=False)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return removed
