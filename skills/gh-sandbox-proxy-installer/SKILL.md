---
name: gh-sandbox-proxy-installer
description: Install, verify, update, or uninstall the gh-sandbox-proxy wrapper so GitHub CLI auth runs inside Docker and host `gh auth token` is blocked. Use when a user asks to set up the safer gh wrapper, distribute it to a machine, fix Claude Code PATH issues for gh, or revert the wrapper.
---

# gh-sandbox-proxy installer

Use this skill to install or maintain `gh-sandbox-proxy`, a wrapper that proxies
`gh` commands into a Docker sandbox while blocking host-side token printing.

## Default install workflow

1. Locate or clone the `gh-sandbox-proxy` repository.
2. Run:

```bash
./install.sh
```

3. Verify:

```bash
which gh
gh auth token
gh --version
```

Expected:

- `which gh` points to `~/.local/bin/gh` or another installed wrapper path.
- `gh auth token` is blocked by `gh-sandbox-proxy`.
- `gh --version` proxies to the official GitHub CLI inside Docker.

## Claude Code PATH issue

If Claude Code or another agent still resolves `/usr/local/bin/gh` or the
official `gh`, run:

```bash
./install.sh --system-link
```

This backs up the existing `/usr/local/bin/gh` once and replaces it with a
symlink to the wrapper. Use this when shell startup files are not reliably read.

## Uninstall

Run:

```bash
./uninstall.sh
```

This removes wrapper symlinks, restores the backed-up `/usr/local/bin/gh` when
present, and removes the active Docker sandbox container and auth volume.

## Safety notes

- Do not copy host `~/.config/gh` or host GitHub tokens into the sandbox.
- Do not bypass the wrapper by calling `gh auth token`.
- For complete GitHub-side OAuth revocation, instruct the user to revoke GitHub
  CLI access in GitHub application settings. Local logout alone is not revoke.
