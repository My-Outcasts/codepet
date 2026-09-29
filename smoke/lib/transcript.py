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
        companion message with the token reversed.

        Same thread and later, because a reversed token sitting in some other
        conversation, or before our probe, is not a reply to it.
        """
        needle = token[::-1]
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
