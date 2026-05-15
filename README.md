# gh-sandbox-proxy

`gh-sandbox-proxy` is a drop-in-ish `gh` wrapper that runs the official GitHub
CLI inside a disposable Docker container.

The goal is practical:

- keep GitHub CLI auth state out of the host OS
- make `gh auth token` return nothing useful on the host
- keep most `gh` command interfaces unchanged
- expire the authenticated environment after a short TTL, default `1h`

The Docker image pins GitHub CLI release asset SHA256 checksums for supported
Linux architectures.

It is not a perfect defense against arbitrary local code execution. While the
sandbox container is alive, anything that can run commands in that container can
use the container-local GitHub CLI session.

## Install

For most users:

```zsh
./install.sh
```

Add the printed PATH line to your shell config if `~/.local/bin` is not already
on PATH:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new shell, then verify:

```zsh
which gh
gh --help
gh auth token
```

`which gh` should point at the installed wrapper symlink. `gh auth token` should
be blocked by the wrapper.

For Claude Code or other agents that do not reliably read shell startup files,
install a system-level symlink:

```zsh
./install.sh --system-link
```

This backs up the existing `/usr/local/bin/gh` once and replaces it with a
symlink to this wrapper. The official Homebrew `gh` remains available at paths
such as `/opt/homebrew/bin/gh`.

To uninstall:

```zsh
./uninstall.sh
```

## Agent Setup

This repository also includes a Claude Code Skill at:

```text
skills/gh-sandbox-proxy-installer/SKILL.md
```

Use it when asking an agent to install, verify, troubleshoot PATH issues, or
uninstall the wrapper on another machine. The Skill delegates the actual machine
changes to `install.sh` / `uninstall.sh`, so human and agent installs follow the
same deterministic path.

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
inside a Docker volume attached to the sandbox, not in the host GitHub CLI
config. The volume is removed on TTL expiry or `gh sandbox cleanup`.

## Sandbox Controls

```zsh
gh sandbox status
gh sandbox cleanup
gh sandbox build
gh sandbox config
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
container_name: gh-sandbox-proxy
workdir_mount: true
auto_auth: true
auth_hostname: github.com
blocked:
  - ["auth", "token"]
  - ["auth", "status", "--show-token"]
```

The YAML parser is intentionally tiny. Keep the config in the same simple shape
as `config.example.yml`.

## Security Model

This wrapper protects against accidentally or casually exposing a long-lived host
GitHub CLI token:

- host `gh auth token` is blocked
- host `gh auth status --show-token` is blocked
- official `gh` auth files are stored only in the Docker container
- official `gh` auth files are kept in a Docker volume for the active sandbox
  session
- the container and auth volume are recreated after `ttl`, default `1h`
- `gh sandbox cleanup` removes the authenticated container and auth volume
  immediately

This wrapper does not protect against every local threat:

- Docker administrators can inspect or exec into containers
- Docker administrators can inspect Docker volumes
- commands run inside the container can use the active GitHub session
- GitHub-issued OAuth tokens are not revoked automatically when a container is
  deleted
- mounting the current working directory means container commands can read and
  write that directory

For stricter use, set `workdir_mount: false` and run commands with explicit
`--repo OWNER/REPO` arguments where possible.

On Docker Desktop for Mac, the current directory mount can fail if the path is
not listed in Docker file sharing settings. In that case, the wrapper retries
without mounting `/work`. Repo-local commands may then need `--repo OWNER/REPO`.

When you run `gh` from a different repository, the wrapper recreates the
container with that repository mounted at `/work` while keeping the active auth
volume until the TTL expires.

## License

MIT
