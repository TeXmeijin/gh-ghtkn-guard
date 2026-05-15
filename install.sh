#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_BIN="$ROOT_DIR/bin/gh"
CONFIG_SRC="$ROOT_DIR/config.example.yml"
CONFIG_DIR="${GH_SANDBOX_CONFIG_DIR:-$HOME/.config/gh-sandbox-proxy}"
CONFIG_FILE="${GH_SANDBOX_CONFIG:-$CONFIG_DIR/config.yml}"
LINK_DIR="${GH_SANDBOX_LINK_DIR:-$HOME/.local/bin}"
LINK_PATH="$LINK_DIR/gh"
INSTALL_SYSTEM_LINK="${GH_SANDBOX_INSTALL_SYSTEM_LINK:-0}"
SYSTEM_LINK_PATH="${GH_SANDBOX_SYSTEM_LINK_PATH:-/usr/local/bin/gh}"
SYSTEM_BACKUP_PATH="${SYSTEM_LINK_PATH}.original-before-gh-sandbox-proxy"
SKIP_DOCKER_BUILD="${GH_SANDBOX_SKIP_DOCKER_BUILD:-0}"
IMAGE_NAME="${GH_SANDBOX_IMAGE:-gh-sandbox-proxy:latest}"

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Options:
  --system-link       Also replace /usr/local/bin/gh with a symlink to this wrapper.
                      The existing file is backed up once.
  --skip-docker-build Do not build the Docker image.
  --link-dir DIR      Install gh symlink into DIR. Default: ~/.local/bin
  --help              Show this help.

Environment:
  GH_SANDBOX_LINK_DIR=/path
  GH_SANDBOX_INSTALL_SYSTEM_LINK=1
  GH_SANDBOX_SKIP_DOCKER_BUILD=1
  GH_SANDBOX_IMAGE=gh-sandbox-proxy:latest
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system-link)
      INSTALL_SYSTEM_LINK=1
      ;;
    --skip-docker-build)
      SKIP_DOCKER_BUILD=1
      ;;
    --link-dir)
      shift
      [[ $# -gt 0 ]] || { echo "missing value for --link-dir" >&2; exit 2; }
      LINK_DIR="$1"
      LINK_PATH="$LINK_DIR/gh"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd python3

chmod +x "$WRAPPER_BIN"

mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$CONFIG_SRC" "$CONFIG_FILE"
  echo "created config: $CONFIG_FILE"
else
  echo "kept existing config: $CONFIG_FILE"
fi

mkdir -p "$LINK_DIR"
ln -sfn "$WRAPPER_BIN" "$LINK_PATH"
echo "installed user gh symlink: $LINK_PATH -> $WRAPPER_BIN"

if [[ "$SKIP_DOCKER_BUILD" != "1" ]]; then
  docker build -t "$IMAGE_NAME" "$ROOT_DIR"
fi

if [[ "$INSTALL_SYSTEM_LINK" == "1" ]]; then
  if [[ -e "$SYSTEM_LINK_PATH" || -L "$SYSTEM_LINK_PATH" ]]; then
    current_target="$(readlink "$SYSTEM_LINK_PATH" 2>/dev/null || true)"
    if [[ "$current_target" != "$WRAPPER_BIN" ]]; then
      if [[ ! -e "$SYSTEM_BACKUP_PATH" && ! -L "$SYSTEM_BACKUP_PATH" ]]; then
        mv "$SYSTEM_LINK_PATH" "$SYSTEM_BACKUP_PATH"
        echo "backed up original gh: $SYSTEM_BACKUP_PATH"
      else
        rm -f "$SYSTEM_LINK_PATH"
        echo "removed existing $SYSTEM_LINK_PATH; backup already exists at $SYSTEM_BACKUP_PATH"
      fi
    fi
  fi
  ln -sfn "$WRAPPER_BIN" "$SYSTEM_LINK_PATH"
  echo "installed system gh symlink: $SYSTEM_LINK_PATH -> $WRAPPER_BIN"
fi

cat <<NEXT

Install complete.

Recommended shell setup:
  export PATH="$LINK_DIR:\$PATH"

Verify:
  which gh
  gh auth token
  gh --version

If Claude Code or another agent ignores shell startup files, rerun with:
  ./install.sh --system-link
NEXT
