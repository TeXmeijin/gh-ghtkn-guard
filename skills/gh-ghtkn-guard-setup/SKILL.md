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
- If the first `gh` command times out while waiting for `ghtkn`, run
  `ghtkn get "$GHTKN_APP_NAME" >/dev/null` once in a normal interactive
  terminal and retry, or enter the one-time code printed above in the GitHub
  device page. The wrapper does not stream `ghtkn` stdout because stdout is
  reserved for the token, but `ghtkn` prints the Device Flow code to stderr.

If the target agent shell resolves the official `gh`, treat setup as failed and
inspect shell startup files and the agent process environment before continuing.

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
