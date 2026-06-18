import Foundation
import Combine
import AppKit

/// One-click installer for Claude Code reflection hooks.
/// Creates ~/.codepet/hooks/ scripts and merges config into ~/.claude/settings.json.
///
/// Because the app runs in a macOS sandbox container, it cannot write to the
/// real home directory. Instead, the install button copies a self-contained
/// bash command to the clipboard. The user pastes it in Terminal and presses Enter.
final class HookInstaller: ObservableObject {

    enum Status: Equatable {
        case notInstalled
        case installing   // "command copied" state
        case installed
        case failed(String)
    }

    @Published var status: Status = .notInstalled

    // MARK: - Public

    /// Check if hooks are already installed by looking for a marker
    /// the install script writes into the app container.
    func checkInstallation() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let markerPath = Self.containerMarkerPath
            let isInstalled = FileManager.default.fileExists(atPath: markerPath)
            DispatchQueue.main.async {
                self.status = isInstalled ? .installed : .notInstalled
            }
        }
    }

    /// Copy the install command to clipboard.
    func install() {
        let command = Self.buildInstallCommand()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        status = .installing  // Shows "copied" UI state
    }

    /// User confirms they ran the command — verify and update status.
    func verifyInstallation() {
        // Write marker so future launches remember
        let markerPath = Self.containerMarkerPath
        let dir = (markerPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: markerPath, contents: nil)
        status = .installed
    }

    /// Reset to allow re-install
    func resetStatus() {
        status = .notInstalled
    }

    // MARK: - Marker file (in the container, so we can read/write it)

    private static var containerMarkerPath: String {
        return "\(RealHome.url.path)/.codepet/hooks-installed-marker"
    }

    // MARK: - Build the clipboard command

    /// Build a single bash command that installs everything.
    private static func buildInstallCommand() -> String {
        let promptB64 = logPromptScript.data(using: .utf8)!.base64EncodedString()
        let toolB64 = logToolScript.data(using: .utf8)!.base64EncodedString()
        let summaryB64 = logSummaryScript.data(using: .utf8)!.base64EncodedString()
        let sessionEndB64 = logSessionEndScript.data(using: .utf8)!.base64EncodedString()

        // Build the hooks JSON blob as base64 to avoid all quoting issues
        let hooksJSON = """
        {
          "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/.codepet/hooks/log-prompt.sh"}]}],
          "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "~/.codepet/hooks/log-tool.sh"}]}],
          "Stop": [{"hooks": [{"type": "command", "command": "~/.codepet/hooks/log-summary.sh"}]}],
          "SessionEnd": [{"hooks": [{"type": "command", "command": "~/.codepet/hooks/log-session-end.sh"}]}]
        }
        """
        let hooksB64 = hooksJSON.data(using: .utf8)!.base64EncodedString()

        // The merge script is also base64-encoded to avoid quoting hell.
        // Swift interpolation embeds hooksB64 as a literal string before encoding.
        let mergeScript = """
        #!/bin/bash
        SETTINGS="$HOME/.claude/settings.json"
        mkdir -p "$HOME/.claude"
        if [ ! -f "$SETTINGS" ]; then echo '{}' > "$SETTINGS"; fi
        if grep -q "codepet/hooks" "$SETTINGS" 2>/dev/null; then
          echo "✓ Hooks already in settings"
          exit 0
        fi
        HOOKS_JSON=$(echo "\(hooksB64)" | base64 -d)
        if command -v python3 >/dev/null 2>&1; then
          python3 -c "
        import json, sys
        with open(sys.argv[1]) as f: s = json.load(f)
        h = json.loads(sys.argv[2])
        hooks = s.setdefault('hooks', {})
        for k, v in h.items():
        if k not in hooks:
        hooks[k] = v
        with open(sys.argv[1], 'w') as f: json.dump(s, f, indent=2)
        " "$SETTINGS" "$HOOKS_JSON"
        elif command -v jq >/dev/null 2>&1; then
          jq --argjson nh "$HOOKS_JSON" '.hooks = ($nh + (.hooks // {}))' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
        else
          echo "⚠ Neither python3 nor jq found. Please install one and retry."
          exit 1
        fi
        echo "✓ Hooks added to settings"
        """
        let mergeB64 = mergeScript.data(using: .utf8)!.base64EncodedString()

        return """
        bash -c '
        set -e
        mkdir -p ~/.codepet/hooks
        touch ~/.codepet/events.jsonl
        touch ~/.codepet/session_ends.jsonl
        mkdir -p ~/Library/Containers/app.murror.codepet/Data/.codepet
        echo "\(promptB64)" | base64 -d > ~/.codepet/hooks/log-prompt.sh
        echo "\(toolB64)" | base64 -d > ~/.codepet/hooks/log-tool.sh
        echo "\(summaryB64)" | base64 -d > ~/.codepet/hooks/log-summary.sh
        echo "\(sessionEndB64)" | base64 -d > ~/.codepet/hooks/log-session-end.sh
        chmod +x ~/.codepet/hooks/*.sh
        # Symlink from container path → real home so the app finds the files
        # regardless of which home directory macOS returns
        ln -sf ~/.codepet/events.jsonl ~/Library/Containers/app.murror.codepet/Data/.codepet/events.jsonl 2>/dev/null || true
        ln -sf ~/.codepet/session_ends.jsonl ~/Library/Containers/app.murror.codepet/Data/.codepet/session_ends.jsonl 2>/dev/null || true
        echo "\(mergeB64)" | base64 -d | bash
        echo ""
        echo "✅ CodePet hooks installed! Restart Claude Code to start capturing."
        '
        """
    }

    // MARK: - Embedded hook scripts

    // MARK: - Hook script design principles
    //
    // 1. NEVER drop prompt events. Prompts are the turn boundary signal —
    //    if we lose a prompt, all subsequent tool events get orphaned.
    // 2. Capture generously, filter in the app. The Swift-side TurnAssembler
    //    and NarrativeEnricher have `hasWriteEvents` / `isReadOnlyBash` to
    //    decide what's meaningful. Hooks should just feed data.
    // 3. Use a Bash DENYLIST (skip known-noisy commands) instead of an
    //    ALLOWLIST (only keep specific commands). An allowlist silently
    //    drops every new tool/language the user tries.
    // 4. Every script must be safe to fail — errors go to /dev/null,
    //    never block Claude Code.

    private static let logPromptScript = """
    #!/bin/bash
    # CRITICAL: Never filter prompts by length. Short prompts like "continue",
    # "go ahead", "yes", "ok" are valid turn boundaries. Dropping them causes
    # all subsequent tool events to be orphaned.
    INPUT=$(cat)
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
    if [ -z "$PROMPT" ]; then exit 0; fi

    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg t "$TIME" --arg s "$SESSION" --arg c "$CWD" --arg p "$PROMPT" \
            '{time:$t, type:"prompt", session_id:$s, cwd:$c, text:$p}' >> "$HOME/.codepet/events.jsonl"
    else
        echo "{\\"time\\":\\"$TIME\\",\\"type\\":\\"prompt\\",\\"session_id\\":\\"$SESSION\\",\\"cwd\\":\\"$CWD\\",\\"text\\":\\"$(echo "$PROMPT" | sed 's/"/\\\\"/g')\\"}" >> "$HOME/.codepet/events.jsonl"
    fi
    """

    private static let logToolScript = """
    #!/bin/bash
    INPUT=$(cat)
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Bash commands to SKIP — high-frequency read-only noise.
    # Everything else is captured. The app-side `isReadOnlyBash` does
    # fine-grained filtering; the hook just needs to avoid flooding.
    BASH_DENYLIST="^(cat |head |tail |less |more |wc |file |stat |pwd|echo |printf |which |whoami|type |man |help |true|false|:|test )"

    PATH_=""
    TEXT=""
    case "$TOOL" in
        Edit|Write|NotebookEdit)
            PATH_=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
            if [ -z "$PATH_" ]; then exit 0; fi
            TEXT="$TOOL $(basename "$PATH_")"
            ;;
        Bash)
            CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
            if [ -z "$CMD" ]; then exit 0; fi
            FIRST_CMD=$(echo "$CMD" | head -c 120)
            # Skip only known-noisy read-only commands
            if echo "$FIRST_CMD" | grep -qE "$BASH_DENYLIST"; then exit 0; fi
            TEXT="Bash: $(echo "$FIRST_CMD" | head -c 80)"
            ;;
        Read|Glob|Grep)
            # Read-only tools — capture lightly for context but the app
            # won't count them as "write events" for narrative purposes.
            PATH_=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // empty' 2>/dev/null)
            TEXT="$TOOL $(echo "$PATH_" | head -c 60)"
            ;;
        *)
            # Unknown/future tools — capture with tool name so nothing
            # is silently lost. The app can ignore what it doesn't need.
            TEXT="$TOOL"
            ;;
    esac

    if [ -z "$TEXT" ]; then exit 0; fi

    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg t "$TIME" --arg s "$SESSION" --arg c "$CWD" --arg tn "$TOOL" --arg p "$PATH_" --arg tx "$TEXT" \
            '{time:$t, type:"tool", session_id:$s, cwd:$c, tool_name:$tn, path:$p, text:$tx}' >> "$HOME/.codepet/events.jsonl"
    else
        echo "{\\"time\\":\\"$TIME\\",\\"type\\":\\"tool\\",\\"session_id\\":\\"$SESSION\\",\\"text\\":\\"$(echo "$TEXT" | sed 's/"/\\\\"/g')\\"}" >> "$HOME/.codepet/events.jsonl"
    fi
    """

    private static let logSummaryScript = """
    #!/bin/bash
    INPUT=$(cat)
    SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [ -z "$SESSION" ]; then exit 0; fi

    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg t "$TIME" --arg s "$SESSION" \
            '{time:$t, type:"summary", session_id:$s, text:""}' >> "$HOME/.codepet/events.jsonl"
    else
        echo "{\\"time\\":\\"$TIME\\",\\"type\\":\\"summary\\",\\"session_id\\":\\"$SESSION\\",\\"text\\":\\"\\"}" >> "$HOME/.codepet/events.jsonl"
    fi
    """

    private static let logSessionEndScript = """
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
        echo "{\\"session_id\\":\\"$SESSION\\",\\"time\\":\\"$TIME\\"}" >> "$SESSION_ENDS"
    fi
    """
}
