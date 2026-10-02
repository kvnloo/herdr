#!/usr/bin/env bash
# Idempotent bootstrap for the hermes / oh-my-pi ("omp") toolchain, layered on
# top of .cursor/install.sh. Mirrors the environment used in the SoL-Pi / omp
# work: Node 22.22.2 (via nvm), Bun, and the global `pi` + `omp` CLIs. Python's
# system interpreter (>=3.10) already covers kerdoios, which is stdlib-only.
# Every step is guarded, so re-runs are no-ops.
set -euo pipefail

NODE_VERSION="22.22.2"
PI_VERSION="0.84.2"
OMP_VERSION="18.1.17"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

log() { printf '\n=== %s ===\n' "$*"; }

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  SUDO="sudo"
fi

ensure_bun() {
  command -v bun >/dev/null 2>&1 && return
  log "installing bun"
  local dir="$HOME/.bun"
  BUN_INSTALL="$dir" bash -c 'curl -fsSL https://bun.sh/install | bash' >/dev/null 2>&1
}

ensure_nvm() {
  if [ -s "$NVM_DIR/nvm.sh" ]; then return; fi
  log "installing nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
}

ensure_node() {
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  if [ ! -x "$NVM_DIR/versions/node/v${NODE_VERSION}/bin/node" ]; then
    log "installing node ${NODE_VERSION} via nvm"
    nvm install "$NODE_VERSION" >/dev/null 2>&1
  fi
  NODE_BIN="$NVM_DIR/versions/node/v${NODE_VERSION}/bin"
  export PATH="$NODE_BIN:$HOME/.bun/bin:$PATH"
}

ensure_global_cli() {
  # ensure_global_cli <binary> <spec> <expected-version-substring>
  local bin="$1" spec="$2" want="$3"
  if command -v "$bin" >/dev/null 2>&1 && "$bin" --version 2>/dev/null | grep -q "$want"; then
    return
  fi
  log "installing $bin ($spec)"
  npm install --global --ignore-scripts "$spec"
}

wire_path() {
  # Make agent shells resolve node ${NODE_VERSION} and bun ahead of the base
  # image's older node. profile.d covers login shells; ~/.bashrc covers
  # interactive non-login shells.
  local line="export PATH=\"$NVM_DIR/versions/node/v${NODE_VERSION}/bin:\$HOME/.bun/bin:\$PATH\""
  local profile="/etc/profile.d/hermes-omp.sh"
  if [ -n "$SUDO" ]; then
    printf '%s\n%s\n' "export NVM_DIR=\"$NVM_DIR\"" "$line" | $SUDO tee "$profile" >/dev/null
    $SUDO chmod 0644 "$profile"
  fi
  local bashrc="$HOME/.bashrc"
  if [ -f "$bashrc" ] && ! grep -qF "versions/node/v${NODE_VERSION}/bin" "$bashrc"; then
    printf '\n# hermes/omp toolchain\n%s\n' "$line" >> "$bashrc"
  fi
}

main() {
  ensure_bun
  ensure_nvm
  ensure_node
  ensure_global_cli pi "@earendil-works/pi-coding-agent@${PI_VERSION}" "$PI_VERSION"
  ensure_global_cli omp "@oh-my-pi/pi-coding-agent@${OMP_VERSION}" "$OMP_VERSION"
  wire_path

  log "hermes/omp toolchain versions"
  node --version
  bun --version
  python3 --version
  pi --version
  omp --version

  log "hermes/omp bootstrap complete"
}

main "$@"
