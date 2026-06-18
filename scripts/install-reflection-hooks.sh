#!/bin/bash
# install-reflection-hooks.sh
# Installs Claude Code hooks that capture decision moments to ~/.codepet/events.jsonl,
# which CodePet's Reflection tab reads.
#
# Run once. Safe to re-run — overwrites the hook scripts but never touches
# ~/.claude/settings.json (you paste that snippet manually).

set -euo pipefail

CODEPET_DIR="$HOME/.codepet"
HOOKS_DIR="$CODEPET_DIR/hooks"
EVENTS_FILE="$CODEPET_DIR/events.jsonl"

mkdir -p "$HOOKS_DIR"
touch "$EVENTS_FILE"

cat > "$HOOKS_DIR/log-prompt.sh" <<'PROMPT_EOF'
#!/bin/bash
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ] || [ ${#PROMPT} -lt 10 ]; then exit 0; fi

SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg t "$TIME" --arg s "$SESSION" --arg c "$CWD" --arg p "$PROMPT" \
        '{time:$t, type:"prompt", session_id:$s, cwd:$c, text:$p}' >> "$HOME/.codepet/events.jsonl"
else
    echo "{\"time\":\"$TIME\",\"type\":\"prompt\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\",\"text\":\"$(echo "$PROMPT" | sed 's/"/\\"/g')\"}" >> "$HOME/.codepet/events.jsonl"
fi
PROMPT_EOF

cat > "$HOOKS_DIR/log-tool.sh" <<'TOOL_EOF'
#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

BASH_ALLOWLIST="^(git commit|git push|git merge|git rebase|git tag|npm install|npm run|pip install|brew install|xcodebuild|swift build|swift test|fastlane|rm |mv |mkdir |make |docker |kubectl )"

PATH_=""
TEXT=""
case "$TOOL" in
    Edit|Write|NotebookEdit)
        PATH_=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if [ -z "$PATH_" ]; then exit 0; fi
        TEXT="$TOOL $(basename "$PATH_")"
        ;;
    Read)
        PATH_=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        if [ -z "$PATH_" ]; then exit 0; fi
        TEXT="Read $(basename "$PATH_")"
        ;;
    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        if [ -z "$CMD" ]; then exit 0; fi
        if ! echo "$CMD" | grep -qE "$BASH_ALLOWLIST"; then exit 0; fi
        TEXT="Bash: $(echo "$CMD" | head -c 80)"
        ;;
    *)
        exit 0
        ;;
esac

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg t "$TIME" --arg s "$SESSION" --arg c "$CWD" --arg tn "$TOOL" --arg p "$PATH_" --arg tx "$TEXT" \
        '{time:$t, type:"tool", session_id:$s, cwd:$c, tool_name:$tn, path:$p, text:$tx}' >> "$HOME/.codepet/events.jsonl"
else
    echo "{\"time\":\"$TIME\",\"type\":\"tool\",\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\",\"tool_name\":\"$TOOL\",\"path\":\"$PATH_\",\"text\":\"$(echo "$TEXT" | sed 's/"/\\"/g')\"}" >> "$HOME/.codepet/events.jsonl"
fi
TOOL_EOF

cat > "$HOOKS_DIR/log-summary.sh" <<'SUMMARY_EOF'
#!/bin/bash
# Stop hook — fires when Claude Code finishes responding to one prompt.
# Writes a `summary` event so TurnAssembler can close the in-flight turn.
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ -z "$SESSION" ]; then exit 0; fi

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg t "$TIME" --arg s "$SESSION" \
        '{time:$t, type:"summary", session_id:$s, text:""}' >> "$HOME/.codepet/events.jsonl"
else
    echo "{\"time\":\"$TIME\",\"type\":\"summary\",\"session_id\":\"$SESSION\",\"text\":\"\"}" >> "$HOME/.codepet/events.jsonl"
fi
SUMMARY_EOF

cat > "$HOOKS_DIR/log-session-end.sh" <<'SESSIONEND_EOF'
#!/bin/bash
SESSION_ENDS="$HOME/.codepet/session_ends.jsonl"
mkdir -p "$HOME/.codepet"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
if [ -z "$SESSION" ]; then exit 0; fi

if command -v jq >/dev/null 2>&1; then
    jq -nc --arg s "$SESSION" --arg t "$TIME" \
        '{session_id:$s, time:$t}' >> "$SESSION_ENDS"
else
    echo "{\"session_id\":\"$SESSION\",\"time\":\"$TIME\"}" >> "$SESSION_ENDS"
fi
SESSIONEND_EOF

chmod +x "$HOOKS_DIR/log-prompt.sh" "$HOOKS_DIR/log-tool.sh" "$HOOKS_DIR/log-summary.sh" "$HOOKS_DIR/log-session-end.sh"

cat <<'INSTRUCTIONS'

✓ Hook scripts installed at ~/.codepet/hooks/
✓ Events will be appended to ~/.codepet/events.jsonl
✓ Session ends will be appended to ~/.codepet/session_ends.jsonl

To activate, paste the following into ~/.claude/settings.json under the
top-level "hooks" key (merge with any existing hooks you already have):

  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [
        { "type": "command", "command": "~/.codepet/hooks/log-prompt.sh" }
      ]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [
        { "type": "command", "command": "~/.codepet/hooks/log-tool.sh" }
      ]
    }],
    "Stop": [{
      "hooks": [
        { "type": "command", "command": "~/.codepet/hooks/log-summary.sh" }
      ]
    }],
    "SessionEnd": [{
      "hooks": [
        { "type": "command", "command": "~/.codepet/hooks/log-session-end.sh" }
      ]
    }]
  }

Restart Claude Code after editing settings.json. Then open CodePet and
go to the Reflection tab — your decision moments will appear there.
Session summaries will be auto-generated when sessions go idle (30 min)
or when Claude Code ends a session.

INSTRUCTIONS
