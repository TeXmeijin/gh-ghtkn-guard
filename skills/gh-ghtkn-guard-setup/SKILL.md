---
name: gh-ghtkn-guard-setup
description: Interactively set up, verify, update, or uninstall gh-ghtkn-guard for Claude Code, Codex, or similar coding-agent users so gh uses ghtkn-backed GitHub App User Access Tokens without exposing GH_TOKEN in the agent shell. Use when a user asks to set up the safer gh wrapper, distribute it to a machine, fix agent PATH issues for gh, or revert the wrapper.
---

# gh-ghtkn-guard setup

Use this skill to set up or maintain `gh-ghtkn-guard`, a host-side `gh`
wrapper for developers who let Claude Code, Codex, or similar coding agents run
local shell commands. It calls `ghtkn get "$GHTKN_APP_NAME"` and passes the
resulting token only to the real GitHub CLI child process while blocking
host-side token printing.

## Setup Workflow

This skill owns setup. There is no one-shot setup script. Setup must be
interactive because it changes shell startup files and PATH resolution.

1. Locate or clone the `gh-ghtkn-guard` repository.
2. Inspect the current machine without making changes:

```bash
pwd
command -v gh || true
type gh || true
command -v ghtkn || true
test -f ~/.zshenv && grep -n "gh-ghtkn-guard\\|gh wrapper\\|\\.local/bin" ~/.zshenv || true
```

3. Decide where `GHTKN_APP_NAME` should come from. Prefer per-owner `direnv`
   files for `ghq` layouts, for example:

```text
~/ghq/github.com/your-org/.envrc
~/ghq/github.com/your-user/.envrc
```

If a child repository has its own `.envrc`, add `source_up` so the owner-level
value is inherited.

4. Present a short setup proposal before editing anything. Include:

- Exact shell startup file that will add the wrapper to PATH, usually
  `~/.zshenv`
- Exact `GHTKN_APP_NAME` source, such as a direnv file or shell startup file
- Verification commands that will be run

Ask for explicit approval before changing files.

5. After approval, perform setup as individual, inspectable steps:

```bash
chmod +x bin/gh
```

6. Add or update this marker block in `~/.zshenv`, adjusted to the repository's
   absolute `bin` path. Scope it to coding-agent shells when possible:

```zsh
# >>> gh-ghtkn-guard PATH >>>
# Route coding-agent `gh` calls through the ghtkn-aware wrapper before Homebrew gh.
if [[ "$CODEX_SHELL" == "1" || "$__CFBundleIdentifier" == "com.openai.codex" ]]; then
  _gh_wrapper_bin='/absolute/path/to/gh-ghtkn-guard/bin'
  if [[ -d "$_gh_wrapper_bin" ]]; then
    path=("$_gh_wrapper_bin" "${(@)path:#$_gh_wrapper_bin}")
    export PATH
  fi
  unset _gh_wrapper_bin
fi
# <<< gh-ghtkn-guard PATH <<<
```

For Claude Code or a team machine that should always use the wrapper in project
shells, a broader shell startup rule is acceptable if the user explicitly wants
that behavior.

### When PATH prepend is not enough (mise / rbenv / asdf)

The prepend in step 6 runs once at shell startup. Tools that **rebuild PATH on
every prompt** — `mise`, `rbenv`, `asdf`, and similar — can silently drop the
prepended wrapper entry, because they reconstruct PATH from a snapshot captured
*before* the prepend ran (`mise` stores it in `__MISE_ORIG_PATH`). The symptom:
`command -v gh` resolves the wrapper right after sourcing startup files, but the
agent's actual shell (e.g. Claude Code's startup snapshot plus the mise precmd
hook) resolves the real gh, with only the wrapper's single PATH entry missing.
Setup looks done, yet every agent `gh` call hits the logged-out real gh.

The robust fix is to put the wrapper where PATH already points, instead of
fighting the rebuild. Symlink `bin/gh` into a directory that (a) the version
manager preserves (i.e. it is already in `__MISE_ORIG_PATH`) and (b) sits
**before** the real gh's directory (`/opt/homebrew/bin`) in PATH. `~/.local/bin`
is usually both:

```bash
ln -s /absolute/path/to/gh-ghtkn-guard/bin/gh ~/.local/bin/gh
```

The wrapper resolves real gh / ghtkn by absolute path and environment variables
and does **not** depend on its own location, so a symlink (or copy) placed
anywhere behaves identically. Confirm no earlier PATH directory already provides
a `gh` (e.g. `~/.opencode/bin/gh`, `~/.bun/bin/gh`) that would shadow it, then
verify in the agent shell that the wrapper wins even after a PATH rebuild:

```bash
command -v gh   # must be the wrapper (e.g. ~/.local/bin/gh), not /opt/homebrew/bin/gh
```

7. Configure `GHTKN_APP_NAME`, for example:

```zsh
export GHTKN_APP_NAME=your-org/your-ghtkn-app
```

8. Verify:

```bash
type gh
echo "$GHTKN_APP_NAME"
gh api /user --jq .login
gh auth token
/opt/homebrew/bin/gh auth token
```

Expected:

- `type gh` resolves the wrapper path in the target agent shell.
- `GHTKN_APP_NAME` is set.
- `gh api /user` succeeds.
- `gh auth token` is blocked by `gh-ghtkn-guard`.
- Direct real `gh auth token` returns no token unless the user has separately
  authenticated the real `gh`.
- If the first `gh` command fails because no cached ghtkn token is available,
  run `ghtkn auth "$GHTKN_APP_NAME"` once in a normal interactive terminal and
  retry. Do not run `gh auth login`; the real `gh` is intentionally logged out.

If the target agent shell resolves the official `gh`, treat setup as failed and
inspect shell startup files and the agent process environment before continuing.

9. Install the companion skills (`gh-runner`, `gh-ghtkn-guard-setup`) into the
    agent's skills directory by symlinking or copying **from this repo**, which
    is their single source of truth. Do not hand-edit the installed copy — that
    is how the two diverge. For Claude Code:

    ```bash
    ln -snf "$PWD/skills/gh-runner" ~/.claude/skills/gh-runner
    ln -snf "$PWD/skills/gh-ghtkn-guard-setup" ~/.claude/skills/gh-ghtkn-guard-setup
    ```

## State check (doctor)

For a machine that already has (some of) the setup, run this **in the agent
shell** to see how far it has progressed. It is read-only and does not trigger
Device Flow (no `gh auth` call). In a human's own interactive terminal the
`wrapper on PATH` line will show the real gh **by design** — judge from the agent
shell.

```bash
printf 'wrapper on PATH  : %s\n' "$(command -v gh)"
printf 'real gh present  : %s\n' "$(ls /opt/homebrew/bin/gh 2>/dev/null || echo MISSING)"
printf 'ghtkn present    : %s\n' "$(command -v ghtkn || echo MISSING)"
printf 'GHTKN_APP_NAME   : %s\n' "${GHTKN_APP_NAME:-<unset>}"
printf 'GH_TOKEN in env  : %s\n' "${GH_TOKEN:+LEAKED - should be empty}${GH_TOKEN:-clean}"
grep -q gh-ghtkn-guard "$HOME/.zshenv" 2>/dev/null \
  && echo 'zshenv PATH block: present' || echo 'zshenv PATH block: MISSING (steps 5-6)'
for s in gh-runner gh-ghtkn-guard-setup; do
  p="$HOME/.claude/skills/$s"
  if [ -L "$p" ]; then echo "skill $s: symlink (good)"
  elif [ -d "$p" ]; then echo "skill $s: COPY (works but drifts - prefer symlink, step 9)"
  else echo "skill $s: NOT INSTALLED (step 9)"; fi
done
```

Interpretation:

- `wrapper on PATH` should be the repo's `bin/gh` in the agent shell. `ghtkn present`
  and a non-`<unset>` `GHTKN_APP_NAME` mean auth can resolve. `GH_TOKEN in env`
  must read `clean`. The two `skill` lines show whether step 9 was done (symlink),
  half-done (copy — drifts from the repo source), or skipped.
- To test live auth separately, run `gh --version` (safe pass-through) then a real
  read like `gh api user --jq .login`; the latter succeeds only when ghtkn has a
  cached token. If it fails, refresh with `ghtkn auth "$GHTKN_APP_NAME"` in a
  normal interactive terminal.

## Uninstall

Run only after telling the user what it removes:

```bash
./uninstall.sh
```

This removes wrapper symlinks, restores the backed-up `/usr/local/bin/gh` when
present, and removes gh-ghtkn-guard marker blocks from shell startup files.

## Safety Notes

- Do not export `GH_TOKEN` into long-lived agent shell environments.
- Do not bypass the wrapper by calling `gh auth token`.
- Do not add broad agent permission for direct `ghtkn` execution unless the user
  explicitly wants agents to perform setup or reauthorization themselves.
- `ghtkn` uses GitHub App User Access Tokens; GitHub controls their expiration.
- First authentication of a session is human-driven via `ghtkn auth`; the agent
  retries `gh` after the cache exists. The agent must not loop the call or ask
  for `gh auth login`. See the `gh-runner` skill, "First authentication in a
  session".
