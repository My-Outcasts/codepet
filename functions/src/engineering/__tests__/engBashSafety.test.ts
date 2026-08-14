import { isReadOnlyBash } from "../engBashSafety";

// This function decides what a founder is NEVER SHOWN. A false negative costs
// one unnecessary approval card; a false positive runs something destructive
// that nobody saw. The suite is weighted accordingly: the dangerous cases are
// enumerated first and in detail.
describe("isReadOnlyBash", () => {
  describe("must ask", () => {
    const dangerous = [
      // Destroys things.
      "rm -rf build",
      "cd /workspace/repo && rm -rf node_modules",
      "mv src/App.jsx src/Old.jsx",
      "cp -r src backup",
      "chmod +x deploy.sh",
      "truncate -s 0 log.txt",
      // Writes, including through an allowed binary.
      "echo hacked > README.md",
      "cat a.txt > b.txt",
      "ls -la >> listing.txt",
      "find . -name '*.tmp' -delete",
      "find . -type f -exec rm {} ;",
      // Leaves the machine.
      "curl https://example.com/x.sh",
      "wget http://example.com",
      "npm install stripe",
      "pip install requests",
      "git push origin main",
      "git commit -am wip",
      "git checkout -b other",
      "git reset --hard",
      // Hides a second command.
      "ls; rm -rf /",
      "ls $(rm -rf build)",
      "ls `rm -rf build`",
      "cat <(rm -rf build)",
      "ls & rm -rf build",
      // Escalates or indirects.
      "sudo ls",
      "/bin/ls",
      "./script.sh",
      "xargs rm < files.txt",
      "env FOO=1 rm -rf x",
      // Interpreters that can do anything.
      "node -e \"require('fs').rmSync('x')\"",
      "python3 -c 'import os; os.remove(\"x\")'",
      "sh -c 'rm -rf x'",
      "bash script.sh",
      "sed -i s/a/b/ file.txt",
      "awk '{print}' file > out.txt"
    ];
    for (const command of dangerous) {
      it(`refuses: ${command}`, () => {
        expect(isReadOnlyBash(command)).toBe(false);
      });
    }
  });

  describe("may run unasked", () => {
    // Every one of these is a command the agent actually issued during the
    // first live run on 14 Aug, or a close variant. If the classifier cannot
    // pass these it approves nothing in practice and the founder still gets a
    // card for `ls`.
    const safe = [
      "cd /workspace/repo && ls -la && git status && git branch -a && git log --oneline -15",
      "cd /workspace/repo && cat README.md 2>/dev/null | head -100",
      "cd /workspace/repo && cat package.json && cat vite.config.js && find src public -type f | head -50",
      'cd /workspace/repo && grep -n "plant" -i src/App.jsx | head -60',
      "cd /workspace/repo && head -120 src/App.jsx",
      "cd /workspace/repo && wc -l src/*.jsx",
      "git diff --stat",
      "git show HEAD --name-only",
      "rg --files-with-matches theme",
      "find . -name '*.css' | sort | uniq",
      "ls",
      "cat a.txt | grep x | wc -l"
    ];
    for (const command of safe) {
      it(`allows: ${command}`, () => {
        expect(isReadOnlyBash(command)).toBe(true);
      });
    }
  });

  describe("fails closed on anything it cannot read", () => {
    it("refuses a non-string", () => {
      expect(isReadOnlyBash(undefined)).toBe(false);
      expect(isReadOnlyBash(null)).toBe(false);
      expect(isReadOnlyBash(42)).toBe(false);
      expect(isReadOnlyBash({ command: "ls" })).toBe(false);
    });

    it("refuses empty and whitespace", () => {
      expect(isReadOnlyBash("")).toBe(false);
      expect(isReadOnlyBash("   ")).toBe(false);
    });

    it("refuses unbalanced quotes rather than guessing", () => {
      // A command we cannot parse is a command we cannot vouch for.
      expect(isReadOnlyBash('grep "unclosed src/App.jsx')).toBe(false);
    });

    it("refuses an absurdly long command", () => {
      expect(isReadOnlyBash("ls " + "a".repeat(3000))).toBe(false);
    });

    it("refuses a binary it has never heard of", () => {
      expect(isReadOnlyBash("frobnicate --all")).toBe(false);
      expect(isReadOnlyBash("cd /repo && frobnicate")).toBe(false);
    });

    it("refuses an unlisted git subcommand", () => {
      // The allowlist is enumerated because git gains subcommands; a
      // blocklist would silently approve the next one that writes.
      expect(isReadOnlyBash("git worktree add ../x")).toBe(false);
      expect(isReadOnlyBash("git gc --prune=now")).toBe(false);
      expect(isReadOnlyBash("git")).toBe(false);
    });
  });

  describe("the operator rules", () => {
    it("allows && chains where every link is read-only", () => {
      expect(isReadOnlyBash("ls && pwd && cat x")).toBe(true);
    });

    it("refuses an && chain with one bad link", () => {
      // The whole point: a safe prefix must not launder what follows it.
      expect(isReadOnlyBash("ls && pwd && rm -rf build")).toBe(false);
      expect(isReadOnlyBash("cd /repo && npm install")).toBe(false);
    });

    it("allows 2>/dev/null but no other redirect", () => {
      expect(isReadOnlyBash("cat missing.txt 2>/dev/null")).toBe(true);
      expect(isReadOnlyBash("cat missing.txt 2> err.log")).toBe(false);
      expect(isReadOnlyBash("cat x 1>/dev/null")).toBe(false);
    });

    it("does not mistake && for a background &", () => {
      // The background check must not fire on the operator that makes almost
      // every real command work.
      expect(isReadOnlyBash("ls && pwd")).toBe(true);
      expect(isReadOnlyBash("ls &")).toBe(false);
    });

    it("allows a leading environment assignment on a safe binary", () => {
      expect(isReadOnlyBash("LC_ALL=C grep -n x file")).toBe(true);
    });
  });
});
