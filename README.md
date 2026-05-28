# gh-sandbox-proxy

[日本語](README.ja.md) | English

`gh-sandbox-proxy` is a small host-side `gh` wrapper for developers who let
coding agents such as Claude Code, Codex, or similar tools run local shell
commands.

It uses [`ghtkn`](https://github.com/suzuki-shunsuke/ghtkn) to obtain a GitHub
App User Access Token for each `gh` invocation, injects that token only into the
real GitHub CLI child process, and blocks token-printing commands on the wrapper
interface.

## Why

Agent-assisted development increases the chance that arbitrary project scripts,
package lifecycle hooks, or generated shell commands run on the same machine as
your GitHub CLI setup.

The goal is narrow:

- keep `GH_TOKEN` out of the long-lived agent shell environment
- keep host `gh auth token` from printing the injected token
- preserve normal `gh` ergonomics for day-to-day commands
- rely on GitHub App permissions and short-lived User Access Tokens for scope
  control

This is a friction layer, not a complete defense against arbitrary local code
execution. A process that can directly run `ghtkn get "$GHTKN_APP_NAME"` may
still obtain a valid GitHub App User Access Token.

## Requirements

- macOS or another environment where `ghtkn` can access its credential store
- GitHub CLI installed at `/opt/homebrew/bin/gh`, or set `GH_SANDBOX_REAL_GH`
- `ghtkn` installed at `/opt/homebrew/bin/ghtkn`, or set `GH_SANDBOX_GHTKN_BIN`
- `GHTKN_APP_NAME` set in the current environment

Example:

```zsh
export GHTKN_APP_NAME=your-org/your-ghtkn-app
```

For multi-owner `ghq` layouts, use `direnv` or shell startup files at the owner
directory level:

```text
~/ghq/github.com/your-org/.envrc
~/ghq/github.com/your-user/.envrc
```

If a child repository has its own `.envrc`, add `source_up` to include the owner
directory configuration.

## Setup

Put this repository's `bin` directory before the real GitHub CLI in PATH for
agent shells:

```zsh
export PATH="/path/to/gh-sandbox-proxy/bin:$PATH"
```

Then verify:

```zsh
which gh
gh api /user --jq .login
gh auth token
```

Expected:

- `which gh` resolves to this repository's `bin/gh`
- `gh api /user` works when `GHTKN_APP_NAME` is set
- `gh auth token` is blocked by the wrapper

## Usage

Use `gh` normally:

```zsh
gh issue view 123
gh pr list
gh pr create -B develop -d
gh workflow run "Deploy" --ref "$(git branch --show-current)"
```

The wrapper runs:

```text
ghtkn get "$GHTKN_APP_NAME"
GH_TOKEN=<token> GITHUB_TOKEN=<token> /opt/homebrew/bin/gh ...
```

The token is scoped to the real `gh` child process. It is not exported into the
parent shell.

## Security Model

The wrapper protects against accidental or casual host-side GitHub token
exposure:

- `gh auth token` is blocked
- `gh auth status --show-token` is blocked
- `GH_TOKEN` is not stored in the agent shell environment
- `gh api` defaults to read-like methods only (`GET`, `HEAD`, `OPTIONS`)

To allow write-likely `gh api` calls for one shell session:

```zsh
export GH_SANDBOX_ALLOW_WRITE=1
```

The wrapper does not protect against every local threat:

- a process that can run `ghtkn get "$GHTKN_APP_NAME"` can obtain a token
- a process that bypasses PATH and calls the real `gh` directly will not use the
  wrapper
- GitHub App User Access Tokens are controlled by GitHub's expiration policy,
  not by this wrapper

## License

MIT
