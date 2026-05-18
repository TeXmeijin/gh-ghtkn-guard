---
name: gh-sandbox-proxy-setup
description: Interactively set up, verify, update, or uninstall gh-sandbox-proxy for Claude Code, Codex, or similar coding-agent users so GitHub CLI auth runs inside Docker and host `gh auth token` is blocked. Use when a user asks to set up the safer gh wrapper, distribute it to a machine, fix agent PATH issues for gh, or revert the wrapper.
---

# gh-sandbox-proxy setup

Use this skill to set up or maintain `gh-sandbox-proxy`, a wrapper for
developers who let Claude Code, Codex, or similar coding agents run local shell
commands. It proxies `gh` commands into a Docker sandbox while blocking
host-side token printing.

## Setup Workflow

This skill owns setup. There is no one-shot setup script. Setup must be
interactive because it changes shell startup files, symlinks, Docker images, and
sandbox mount configuration.

1. Locate or clone the `gh-sandbox-proxy` repository.
2. Inspect the current machine without making changes:

```bash
pwd
command -v gh || true
type gh || true
test -f ~/.zshenv && grep -n "gh-sandbox-proxy\\|gh wrapper\\|\\.local/bin" ~/.zshenv || true
```

3. Inspect likely repository roots and choose stable ancestor directories for
   `workspace_mounts`. Prefer roots such as `~/ghq`, `~/Documents/src`, or
   another directory that contains many git repositories. Do not mount `$HOME`.
   If no safe shared root exists, propose the current project root and explain
   the limitation.
4. Present a short setup proposal before editing anything. Include:

- Exact files that will be changed, usually `~/.zshenv` and
  `~/.config/gh-sandbox-proxy/config.yml`
- Exact symlink that will be created, usually `~/.local/bin/gh`
- Docker image/container names that may be created
- Proposed `workspace_mounts`
- Verification commands that will be run

Ask for explicit approval before changing files, symlinks, or Docker resources.

5. After approval, perform the setup as individual, inspectable steps:

```bash
chmod +x bin/gh
mkdir -p ~/.local/bin ~/.config/gh-sandbox-proxy
ln -sfn "$PWD/bin/gh" ~/.local/bin/gh
test -f ~/.config/gh-sandbox-proxy/config.yml || cp config.example.yml ~/.config/gh-sandbox-proxy/config.yml
docker build -t gh-sandbox-proxy:latest .
```

6. Add or update this marker block in `~/.zshenv`, adjusted to the repository's
   absolute `bin` path:

```zsh
# >>> gh-sandbox-proxy PATH >>>
# Ensure coding-agent shells use gh-sandbox-proxy before Homebrew gh.
_gh_wrapper_bin='/absolute/path/to/gh-sandbox-proxy/bin'
if [[ -d "$_gh_wrapper_bin" ]]; then
  path=("$_gh_wrapper_bin" "${(@)path:#$_gh_wrapper_bin}")
  export PATH
fi
unset _gh_wrapper_bin
# <<< gh-sandbox-proxy PATH <<<
```

7. Edit `~/.config/gh-sandbox-proxy/config.yml` and set the approved roots:

```yaml
workspace_mounts:
  - ~/ghq
  - ~/Documents/src
```

8. Verify:

```bash
type gh
zsh -lc 'type gh; gh auth token'
gh auth token
gh --version
gh sandbox status
```

Expected:

- `type gh` and `zsh -lc 'type gh'` both resolve the wrapper path.
- `gh auth token` is blocked by `gh-sandbox-proxy`.
- `gh --version` proxies to the official GitHub CLI inside Docker.
- `gh sandbox status` shows a `container_workdir` when run under a configured
  workspace mount.

If `zsh -lc` resolves the official `gh`, treat setup as failed and inspect
`~/.zshenv`, shell startup files, and the agent process environment before
continuing. Do not leave a machine in a split state where terminal shells use the
wrapper but coding agents use the official `gh`.

## Uninstall

Run only after telling the user what it removes:

```bash
./uninstall.sh
```

This removes wrapper symlinks, restores the backed-up `/usr/local/bin/gh` when
present, removes gh-sandbox-proxy marker blocks from shell startup files, and
removes the active Docker sandbox container.

## Safety Notes

- Do not copy host `~/.config/gh` or host GitHub tokens into the sandbox.
- Do not bypass the wrapper by calling `gh auth token`.
- Keep `workspace_mounts` as narrow as practical. Mounting a broad ancestor
  improves convenience but also gives container commands read/write access to
  that tree.
- For complete GitHub-side OAuth revocation, instruct the user to revoke GitHub
  CLI access in GitHub application settings. Local logout alone is not revoke.
