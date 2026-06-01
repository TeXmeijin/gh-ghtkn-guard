---
name: gh-runner
description: Day-to-day rules for invoking `gh` from a coding agent (Claude Code, Codex, or similar) on a machine where `gh` is overridden by `gh-ghtkn-guard`. Covers the wrapper's runtime semantics (per-call ghtkn token injection, blocked write-likely `gh api`, blocked `gh auth token`), the agent OS sandbox interaction (top-level-`gh` rule for `excludedCommands`), authenticated multi-line body submission for `gh issue comment` / `gh pr comment` / `gh pr review`, and the supported 3-step flow for downloading images embedded in an Issue or PR body/comment via the rendered `body_html` and its JWT-signed `private-user-images.githubusercontent.com` URLs. Also documents when (and when not) to extend the wrapper with a new subcommand. Setup, install, and PATH wiring belong to the `gh-ghtkn-guard-setup` skill — this skill assumes the wrapper is already installed. Trigger when the agent is about to call `gh` for the first time in a session, when `gh api` was blocked, when `gh auth status` shows `The token in GH_TOKEN is invalid`, when needing to comment / review / fetch images on an Issue or PR, or when a `gh ...` invocation failed with a TLS / certificate error.
---

# gh-runner

How to use `gh` from a coding agent when `gh` is overridden by
`gh-ghtkn-guard` (the wrapper that ships in this repository).

Setup, install, and PATH wiring are owned by the **gh-ghtkn-guard-setup**
skill. This skill is for *using* the wrapper day-to-day.

## Assumptions

Before applying this skill, confirm:

- `which gh` resolves to `gh-ghtkn-guard/bin/gh` (not the real `gh`).
- `GHTKN_APP_NAME=<owner>/<app>` is set in the current shell (typically via
  direnv at the owner directory level, or shell init).
- The real `gh` (e.g., `/opt/homebrew/bin/gh` on macOS) is **not logged in**.
- The agent runtime's OS sandbox has `gh` / `gh *` listed in its
  `excludedCommands` (or equivalent). Without that, `ghtkn` will hit TLS
  failures inside the sandbox.

If any of those is unclear, run the self-diagnostic at the bottom first.

**Judge from the AGENT shell, not a human terminal.** The wrapper's PATH prepend
is gated to agent shells (and to `GHTKN_APP_NAME` being set at shell startup). In
a human's own interactive shell `which gh` usually resolves the *real*, logged-out
gh **by design** — that is not a broken setup, and a manual `gh` / `gh auth status`
test there tells you nothing about the agent.

## First authentication in a session (no cached token)

ghtkn caches a User Access Token for ~8h. The FIRST `gh` call after that
window expires triggers a GitHub **device flow**: `gh` prints a one-time code
(`Copy your one-time code: XXXX-XXXX`) and ghtkn blocks until someone authorizes
it at https://github.com/login/device.

**The agent CAN drive this to completion.** The only human action is typing the
code and clicking Authorize; the agent triggers the flow, surfaces the code,
waits out the authorization, and gets control back with a cached token. Do NOT
retreat to "please run `ghtkn get` in your own terminal" — that is usually the
wrong instruction (see traps below).

### Why the naive flow fails (and why "ask the human to run it" is wrong)

- **A plain FOREGROUND `gh` call blocks your whole turn.** With no cached token,
  ghtkn runs device flow and waits for authorization up to the wrapper's
  `DEFAULT_GHTKN_TIMEOUT_SECONDS` (now 300s, in `bin/gh`). A foreground call hangs
  that long and you cannot surface the code until it returns. Run it in the
  BACKGROUND so you can read the code from stderr while `gh` keeps polling. (If
  you ever see `gh-ghtkn-guard: timed out while waiting for ghtkn token`, the
  timeout is too short for this case — raise it, see "Overriding the timeout".)
- **The human's interactive shell often does NOT have the wrapper on PATH.**
  direnv may export `GHTKN_APP_NAME` without prepending the wrapper bin, so in
  the human's terminal `which gh` is the real, logged-out gh and `gh auth status`
  returns a meaningless "please run gh auth login". The wrapper is active in the
  AGENT's PATH, not necessarily the human's — so the agent must drive auth itself,
  and a manual test in the human's shell proves nothing.
- A device-flow code means "no cached token THIS 8h window" — NOT "permanently
  unauthenticated" and NOT "the human must fix it in their terminal".
- **Do not assert the code "expired" from memory.** A printed code is valid
  ~15 min; you do not know the wall-clock time.

### Working recipe (agent-driven)

1. Run the real `gh` command IN THE BACKGROUND, capturing stderr so you can read
   the device code while the call keeps waiting:

   ```
   gh issue view <url> --json ... > "$TMPDIR/gh.out" 2> "$TMPDIR/gh.err"
   ```
   (`run_in_background: true`. No env prefix needed — the wrapper default of 300s
   already covers human authorization, and `gh` stays the first token so the
   sandbox `gh`/`gh *` exclusion always applies.)

2. After ~6s, read `$TMPDIR/gh.err`:
   - `Copy your one-time code: XXXX-XXXX` → surface that code AND
     https://github.com/login/device to the human. That is their only step.
   - `tls: ... x509` instead → the sandbox `gh` exclusion didn't apply; you are
     not running `gh` as the first token (loop / function / leading assignment).

3. The backgrounded `gh` keeps polling for up to 300s. When the human authorizes,
   ghtkn caches the token (~8h), `gh` completes and writes real output to
   `$TMPDIR/gh.out`. You are notified when the background task ends — read the
   output file then.

4. Subsequent flat `gh` calls this session now succeed with no device flow. Run
   each ONCE — do not loop.

### Overriding the timeout

The default lives in one place: `DEFAULT_GHTKN_TIMEOUT_SECONDS = 300` in `bin/gh`.
The timeout only matters when there is no cached token (device flow); with a
token, ghtkn returns instantly regardless. To override for one call, prefix
`GH_GHTKN_GUARD_GHTKN_TIMEOUT_SECONDS=N gh ...` (verified to run unsandboxed even
as a leading assignment), or set it in Claude Code `settings.json` `env`. Lower
it (e.g. 20) when you want a no-token call to fail fast instead of waiting for a
human.

Still applies: **do not run bare `ghtkn` yourself** (a PreToolUse hook blocks it,
and sandboxed it hits TLS), and **do not loop** the call.

## Wrapper semantics (recap)

- Every `gh ...` invocation re-runs `ghtkn get "$GHTKN_APP_NAME"` and injects
  `GH_TOKEN` / `GITHUB_TOKEN` only into the real `gh` child process.
- The token is never exported into the long-lived agent shell. `echo
  "${GH_TOKEN+set}"` should print empty.
- `gh auth token` and `gh auth status --show-token` are blocked.
- Write-likely `gh api` calls are blocked: any non-`GET`/`HEAD`/`OPTIONS`
  method, `--input`, REST `-F` / `-f` / `--field` / `--raw-field`, and
  GraphQL `query=...mutation...`.

## Sandbox-outside execution: the top-level-`gh` rule

Agent OS sandboxes typically restrict TLS / Security framework access for
processes started inside the sandbox. The wrapper sidesteps this by relying
on the sandbox's `excludedCommands` (or `allowedCommands`) entry for
`gh` / `gh *`.

For that to match, the **top-level** command must start with `gh`. The
following commonly do **not** match:

```
for n in 1 2 3; do gh issue view "$n" ...; done   # top-level is `for`
OUT=/tmp/x.png gh issue view 123 -o "$OUT"        # leading variable assignment (but see device-flow recipe: GH_GHTKN_GUARD_* prefix verified working)
/abs/path/to/gh-ghtkn-guard/bin/gh repo view ...  # full path bypasses `gh *`
cmd1 | gh issue view -                            # pipe RHS is a separate process
```

Rewrite each `gh` call so it starts the line:

```
gh issue view 123 > "$TMPDIR/issue.json"
gh api repos/<owner>/<repo>/issues/123 --jq .title
```

Redirection (`>`, `>>`) and post-fix piping to other commands (`gh ... | jq`)
are fine — what matters is the first token of the command.

If `ghtkn` fails with `tls: failed to verify certificate: x509: OSStatus
-26276` (or any other TLS error originating from `ghtkn`), almost always the
cause is a non-top-level invocation. Rewrite the command first; do not
disable sandboxing or wrapper guards.

## Token freshness

ghtkn-issued User Access Tokens (`ghu_...`) expire in ~8 hours. The wrapper
calls `ghtkn get` on every invocation, so renewal is implicit and usually
invisible.

If a call returns `HTTP 401 Bad credentials` or `gh auth status` says `The
token in GH_TOKEN is invalid`, just retry the command — the wrapper will
fetch a fresh token. If that still fails, refresh explicitly **once** for
the next batch:

```
export GH_TOKEN=$(ghtkn get "$GHTKN_APP_NAME")
gh <command-that-needs-the-fresh-token>
unset GH_TOKEN
```

Never log, paste, or commit the token. No `echo "$GH_TOKEN"` even for a
prefix sanity check unless absolutely necessary.

## Blocked `gh api` writes — use native subcommands first

The wrapper blocks write-likely `gh api` calls. **Do not unblock with
`GH_GHTKN_GUARD_ALLOW_WRITE=1`** as a workaround. The blocking is the point.

Prefer native subcommands:

| Goal | Native subcommand |
| --- | --- |
| New issue comment | `gh issue comment <n> --body-file -` |
| Edit your own latest issue/PR comment | `gh issue comment <n> --edit-last --body-file -` |
| Above, create if none exists | add `--create-if-none` |
| PR review (top-level) | `gh pr review <n> --approve\|--comment\|--request-changes --body-file -` |
| Same for PR comments | `gh pr comment <n> ...` (same flag set as `issue comment`) |

If you genuinely need a write that has no native equivalent (precise
comment-id edit, review dismiss, GraphQL mutation, inline diff review
comment), pause and ask the user. Do not override the wrapper to push
through.

## Multi-line / quoted body content

Inline `--body "..."` breaks on newlines, single quotes, double quotes, and
backticks. For anything beyond one short line, use stdin with a quoted
heredoc:

```
gh issue comment 1234 --body-file - <<'EOF'
## Heading

- bullet item
- `code spans` and ${shell-looking text} are safe inside 'EOF'
EOF
```

The single-quoted `'EOF'` delimiter prevents shell expansion of `$VAR`,
backticks, and `\`. If you forget the quotes, your `$VAR` text will be
expanded against the agent's environment.

When stdin isn't workable (e.g., reusing the same body across commands),
write the body to a file under a sandbox-writable directory and pass it:

```
gh issue comment 1234 --body-file .tmp/comment.md
```

Keep that file inside the workspace (or another writable allowlisted path);
absolute paths under `/tmp` may or may not be writable depending on the
agent's sandbox.

## Downloading images embedded in an Issue or PR

Markdown image attachments in an Issue or PR body/comment (URLs like
`https://github.com/user-attachments/assets/<uuid>`) are reachable only via
the rendered `body_html`, which rewrites them into JWT-signed,
~5-minute-lived `https://private-user-images.githubusercontent.com/...?jwt=...`
URLs. Those signed URLs work with plain `curl` and must not carry an
`Authorization` header (the signature is in the query string; adding
`Authorization` returns 400).

### Step 1 — Fetch the rendered body_html

```
# Issue body (or PR body — same endpoint)
gh api -H "Accept: application/vnd.github.html+json" \
  repos/<owner>/<repo>/issues/<n> > "$TMPDIR/body.json"

# Issue/PR conversation comment (comment_id is the number after
# #issuecomment- in the URL)
gh api -H "Accept: application/vnd.github.html+json" \
  repos/<owner>/<repo>/issues/comments/<comment_id> > "$TMPDIR/body.json"

# PR inline diff comment (URL fragment looks like #discussion_r<id>)
gh api -H "Accept: application/vnd.github.html+json" \
  repos/<owner>/<repo>/pulls/comments/<comment_id> > "$TMPDIR/body.json"
```

### Step 2 — Extract the signed URLs from body_html

```
python3 - "$TMPDIR/body.json" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
html = data.get("body_html") or ""
pattern = r'https://private-user-images\.githubusercontent\.com/[^\s"<>]+'
for url in sorted(set(re.findall(pattern, html))):
    print(url)
PY
```

### Step 3 — Download with plain curl

```
curl -fsSL "<signed-url>" -o "$TMPDIR/img.png"
file "$TMPDIR/img.png"     # e.g., PNG image data, 719 x 122, 8-bit/color RGBA
```

Read the file with the agent's multimodal file-read tool if you need to
verify the content visually.

### Constraints to remember

- **Signed URLs expire in ~5 minutes.** Run Steps 1–3 contiguously in one
  agent turn. If Step 3 returns 404, re-run Step 1 to get fresh signatures.
- **Output to a sandbox-writable path.** `$TMPDIR` and the workspace root
  are typically allowed; arbitrary `/tmp/...` paths may not be.
- **The top-level-`gh` rule applies to Step 1.** Don't put it after a
  variable assignment or inside a `for` loop.
- **`curl` to `*.githubusercontent.com`** must be on the agent's allowed-host
  list. Most agent sandboxes already permit GitHub user-content domains.

## When to extend the wrapper with a new subcommand

A new `gh <name>` subcommand on the wrapper is justified only when ALL of
the following hold:

1. The workflow needs the ghtkn token on the host side outside of `gh`
   itself (i.e., calling something other than the real `gh`, with a `Bearer`
   token).
2. The agent's OS sandbox forbids the direct command that would otherwise
   carry the token (e.g., arbitrary `curl` to a non-allowlisted host).
3. There is no equivalent flow using existing `gh` subcommands plus
   already-permitted host commands.

When adding a subcommand:

- Restrict the inputs (URL allowlist, argv shape) so the token cannot be
  silently sent to an attacker-controlled destination.
- Pass the token via stdin (`curl -H @-`), never via argv (which leaks via
  `ps` and process accounting).
- Update this skill in the same change. A subcommand that is not documented
  here is effectively invisible to future agent sessions.

If any condition is missing, document the multi-step recipe in this skill
instead of changing `bin/gh`.

## The real `gh` must stay logged out

`/opt/homebrew/bin/gh` (or the platform equivalent) must have **no logged-in
account**. After setup, run:

```
<real-gh-path> auth status
```

If it shows a host, log out:

```
<real-gh-path> auth logout
```

Direct calls to the real `gh` bypass the wrapper completely (token
injection, write blocking, token printing guard — all off). Never use the
real `gh` directly as a fallback when the wrapper misbehaves; fix the
wrapper or escalate.

## Self-diagnostic

All read-only; no token is printed:

```
which gh                                       # should resolve to gh-ghtkn-guard/bin/gh
ls -l /opt/homebrew/bin/gh 2>/dev/null         # is the real gh installed?
gh --version                                   # transparent pass-through to real gh
gh auth status                                 # token validity, no token printed
echo "GHTKN_APP_NAME=$GHTKN_APP_NAME"          # right app for the current owner?
echo "${GH_TOKEN+set}"                         # should be empty in the agent shell
```

Run these **in the agent shell**. If `which gh` does not point to
`gh-ghtkn-guard/bin/gh` *there*, the wrapper is not wired for the agent: invoke
the `gh-ghtkn-guard-setup` skill. (In a human's interactive shell the real gh is
expected — see Assumptions.) `gh --version` is a safe probe; it passes through to
the real gh without triggering ghtkn / Device Flow.

## See also

- `gh-ghtkn-guard-setup` skill — initial install, PATH wiring, ghtkn setup,
  GitHub App creation
- `gh-ghtkn-guard` repository — `bin/gh` source and the project README
- `ghtkn` (`suzuki-shunsuke/ghtkn`) — the underlying token broker
