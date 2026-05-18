# gh-sandbox-proxy

[日本語](README.ja.md) | English

`gh-sandbox-proxy` is a drop-in-ish `gh` wrapper that runs the official GitHub
CLI inside a disposable Docker container.

It is primarily for developers who let coding agents such as Claude Code,
Codex, or similar tools run local shell commands. The aim is to keep day-to-day
`gh` workflows usable while making host-side GitHub CLI token harvesting less
straightforward for automated or opportunistic processes.

## Why

Recent package supply-chain incidents have made a practical risk more visible:
developer machines, especially agent-assisted ones, often keep GitHub CLI
authentication in predictable local locations, and a single command can expose a
usable token to a process running on that machine.

This project does not claim to solve endpoint compromise. Its goal is narrower:
reduce the value of the host OS as a place to harvest GitHub CLI credentials,
while preserving the day-to-day ergonomics of `gh` as much as possible. It is a
friction layer, not a guarantee.

The design target is practical:

- keep GitHub CLI auth state out of the host OS
- make `gh auth token` return nothing useful on the host
- keep most `gh` command interfaces unchanged
- expire the authenticated environment after a short TTL, default `1h`

The Docker image pins GitHub CLI release asset SHA256 checksums for supported
Linux architectures.

It is not a perfect defense against arbitrary local code execution. While the
sandbox container is alive, anything that can run commands in that container can
use the container-local GitHub CLI session.

## Setup

This project does not provide a one-shot setup script. Setup is intentionally
agent-assisted and approval-driven because it touches shell startup files,
symlinks, Docker resources, and repository mount configuration.

Use the bundled Claude Code / Codex Skill:

```text
skills/gh-sandbox-proxy-setup/SKILL.md
```

The skill first inspects shell startup files, existing `gh` resolution, and
repository root candidates. It then asks for approval with the exact files,
symlink, Docker resources, and `workspace_mounts` it plans to use before making
changes.

To uninstall, inspect what will be removed and then run:

```zsh
./uninstall.sh
```

## Usage

Use `gh` normally:

```zsh
gh issue view 123
gh pr list
gh pr create -B develop -d
gh workflow run "Deploy" --ref "$(git branch --show-current)"
```

Commands that open a browser, such as `gh pr list -w`, are also proxied. The
Linux `gh` process writes the target URL to a container-local hook, then the
wrapper opens that URL on the macOS host.

For tests, override the host opener:

```zsh
GH_SANDBOX_OPEN=/bin/echo gh pr list -w
```

The first authenticated command starts a container and runs:

```zsh
gh auth login -h github.com --web
```

inside the container. Follow the printed browser/device flow. The token is stored
inside a tmpfs mount attached to the sandbox, not in the host GitHub CLI config
or a Docker volume. The tmpfs disappears when the sandbox container exits.

## Sandbox Controls

```zsh
gh sandbox status
gh sandbox cleanup
gh sandbox build
gh sandbox config
gh sandbox suggest-mounts
```

`cleanup` removes the current container immediately.

## Config

Default config path:

```text
~/.config/gh-sandbox-proxy/config.yml
```

Override:

```zsh
export GH_SANDBOX_CONFIG=/path/to/config.yml
```

Important fields:

```yaml
image: gh-sandbox-proxy:latest
ttl: 1h
active_window_enabled: false
active_window_timezone: Asia/Tokyo
active_window_start: "10:00"
active_window_end: "19:00"
auth_storage: tmpfs
auth_tmpfs_size: 16m
workspace_mounts:
  - ~/ghq
  - ~/Documents/src
container_name: gh-sandbox-proxy
auto_auth: true
auth_hostname: github.com
blocked:
  - ["auth", "token"]
  - ["auth", "status", "--show-token"]
```

The YAML parser is intentionally tiny. Keep the config in the same simple shape
as `config.example.yml`.

`workspace_mounts` should contain stable ancestor directories that hold your git
repositories. The wrapper mounts these roots once and maps the host current
directory to the matching container path when running `gh`. This lets
repo-aware commands read `.git`, remotes, and the current branch without
recreating the sandbox each time you `cd` between repositories.

If your current directory is not under any configured workspace mount, commands
that depend on local git context may fail. Use `--repo OWNER/REPO` for those
commands, or add an appropriate ancestor directory to `workspace_mounts`.

To keep a sandbox for a normal workday in Japan while retaining `ttl` as the
fallback outside that window:

```yaml
ttl: 1h
active_window_enabled: true
active_window_timezone: Asia/Tokyo
active_window_start: "10:00"
active_window_end: "19:00"
```

This is enforced by the wrapper and the container lifecycle, not by a Docker
volume TTL feature. When the sandbox starts, the wrapper calculates the lifetime
and starts the container with `--rm`, a tmpfs auth directory, and `sleep
<seconds>` as the main process. When sleep exits, Docker removes the container
and the tmpfs auth data disappears.

## Security Model

This wrapper protects against accidentally or casually exposing a long-lived host
GitHub CLI token:

- host `gh auth token` is blocked
- host `gh auth status --show-token` is blocked
- official `gh` auth files are stored only in the sandbox tmpfs
- the container exits after the configured expiry policy
  (`ttl` by default, or the active window when enabled)
- `gh sandbox cleanup` removes the authenticated container immediately

This wrapper does not protect against every local threat:

- Docker administrators can inspect or exec into containers
- commands run inside the container can use the active GitHub session
- GitHub-issued OAuth tokens are not revoked automatically when a container is
  deleted
- mounted workspace directories can be read and written by commands running
  inside the container

## License

MIT
