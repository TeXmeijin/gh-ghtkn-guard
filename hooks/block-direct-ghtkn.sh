#!/usr/bin/env bash
# PreToolUse(Bash) hook: block a coding agent from invoking `ghtkn` directly.
#
# Why: `gh` is wrapped by gh-ghtkn-guard's bin/gh, which calls `ghtkn get`
# itself and injects the token only into the real gh child process. An agent
# should therefore never need to type `ghtkn`. When it does, it is almost
# always one of two mistakes:
#
#   1. Trying to "authenticate" by running the device-flow command that the
#      wrapper printed. The agent should never run `ghtkn` itself — it drives
#      device flow THROUGH `gh` (extended wrapper timeout + background, see the
#      gh-runner skill). The human only types the one-time code; the agent waits
#      out the authorization and gets control back. Running bare `ghtkn` just
#      hits this block (and TLS, since `ghtkn` alone is not sandbox-excluded).
#   2. Running `ghtkn` outside the top-level `gh` context (in a loop, after a
#      variable assignment, backgrounded). That is non-top-level, so the OS
#      sandbox's `gh`/`gh *` excludedCommands entry does not apply and ghtkn
#      fails TLS verification (x509). This is NOT a sandbox misconfiguration.
#
# Blocking here turns both mistakes into a clear, early stop instead of a
# confusing hang or a misdiagnosed TLS error.
#
# Install: wire into PreToolUse(Bash) in settings.json. Owned by the
# gh-ghtkn-guard-setup skill.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool_name" = "Bash" ] || exit 0

command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Match `ghtkn` only in COMMAND position — i.e. as the executable being run,
# not as an argument or inside a string literal. Command position means: line
# start, or right after a command separator / pipe / subshell opener
# (`;` `&` `|` `(` backtick, which also covers `&&`, `||`, `$(`), optionally
# with a path prefix (e.g. /opt/homebrew/bin/ghtkn).
#
# Deliberately NOT matched (avoids false positives):
#   - `grep ghtkn file`, `echo "ghtkn"`  → preceded by a space/quote (argument)
#   - `__ghtkn_app_for_cwd`              → preceded by a word char, no `/`
# Tradeoff: `xargs ghtkn` / `sudo ghtkn` style wrappers slip through; those are
# contrived for an agent and caught by human review.
if printf '%s\n' "$command_text" | perl -0ne 'exit 2 if /(?:^|[;&|(`])\s*(?:[\/\w.-]*\/)?ghtkn\b/m; exit 0;'; then
  exit 0
else
  cat >&2 <<'MESSAGE'
Blocked: do not run `ghtkn` directly from Claude Code.

`gh` already wraps ghtkn. Call `gh ...` as a flat, top-level command and the
GitHub App User Access Token is injected automatically. You never need to run
ghtkn yourself.

If `gh` printed a device-flow one-time code, there is simply no cached token
for this ~8h window. You do NOT fix that by running `ghtkn` here, and you do NOT
hand it off to the human's terminal (their shell often lacks the wrapper on
PATH). Drive it yourself THROUGH `gh`:

  1. Re-run the SAME real `gh` command, but with an extended wrapper timeout and
     in the BACKGROUND, capturing stderr:

         GH_GHTKN_GUARD_GHTKN_TIMEOUT_SECONDS=300 gh <args> > out 2> err

  2. Read `err`, surface the one-time code + https://github.com/login/device to
     the human. They type the code and Authorize — that is their only step.
  3. The backgrounded `gh` waits out the authorization; on success ghtkn caches
     the token (~8h) and `gh` writes its real output. Then continue.

Do this ONCE (not in a loop). Full recipe: the gh-runner skill,
"First authentication in a session".

A `tls: ... x509` error from a direct ghtkn call is NOT a sandbox problem — it
is exactly this mistake (ghtkn run outside the top-level `gh` wrapper). Do not
disable sandboxing or retry in a loop.
MESSAGE
  exit 2
fi
