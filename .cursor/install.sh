#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for herdr.
# Installs the toolchain herdr needs to build the vendored libghostty-vt and
# run the test suite, then warms the cargo build. Safe to run repeatedly: every
# tool step is guarded by a presence/version check, so on a snapshot that already
# contains the tools these steps become no-ops.
set -euo pipefail

ZIG_VERSION="0.16.0"
ARCH="$(uname -m)"

log() { printf '\n=== %s ===\n' "$*"; }

# Prefer sudo when a privileged install location is needed; degrade gracefully
# when it is unavailable (e.g. already-root snapshots).
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

ensure_apt_packages() {
  local missing=()
  for pkg in build-essential cmake ninja-build pkg-config; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log "installing apt packages: ${missing[*]}"
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq "${missing[@]}"
  fi
}

ensure_zig() {
  if command -v zig >/dev/null 2>&1 && [ "$(zig version 2>/dev/null)" = "$ZIG_VERSION" ]; then
    return
  fi
  case "$ARCH" in
    x86_64) zig_arch="x86_64" ;;
    aarch64|arm64) zig_arch="aarch64" ;;
    *) echo "unsupported arch for zig: $ARCH" >&2; exit 1 ;;
  esac
  log "installing zig ${ZIG_VERSION}"
  local url="https://ziglang.org/download/${ZIG_VERSION}/zig-${zig_arch}-linux-${ZIG_VERSION}.tar.xz"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/zig.tar.xz"
  $SUDO rm -rf /opt/zig
  $SUDO mkdir -p /opt/zig
  $SUDO tar -xf "$tmp/zig.tar.xz" -C /opt/zig --strip-components=1
  $SUDO ln -sf /opt/zig/zig /usr/local/bin/zig
  rm -rf "$tmp"
}

ensure_cargo_tool() {
  # ensure_cargo_tool <binary> <installer-command...>
  local bin="$1"; shift
  command -v "$bin" >/dev/null 2>&1 && return
  log "installing $bin"
  "$@"
}

ensure_nextest() {
  command -v cargo-nextest >/dev/null 2>&1 && return
  log "installing cargo-nextest"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL https://get.nexte.st/latest/linux -o "$tmp/nextest.tar.gz"
  tar -xzf "$tmp/nextest.tar.gz" -C "${CARGO_HOME:-$HOME/.cargo}/bin"
  rm -rf "$tmp"
}

ensure_just() {
  command -v just >/dev/null 2>&1 && return
  log "installing just"
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
    | bash -s -- --to "${CARGO_HOME:-$HOME/.cargo}/bin"
}

ensure_rust() {
  # herdr pins its toolchain in rust-toolchain.toml; rustup materializes it on
  # first cargo invocation. Only bootstrap rustup when cargo is entirely absent.
  command -v cargo >/dev/null 2>&1 && return
  log "installing rustup (toolchain version comes from rust-toolchain.toml)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain none --profile minimal
  # shellcheck disable=SC1090
  . "${CARGO_HOME:-$HOME/.cargo}/env"
}

ensure_bun() {
  command -v bun >/dev/null 2>&1 && return
  log "installing bun"
  local dir="/opt/bun"
  if [ -n "$SUDO" ]; then
    $SUDO mkdir -p "$dir"
    $SUDO chown -R "$(id -u):$(id -g)" "$dir"
  else
    dir="$HOME/.bun"
  fi
  BUN_INSTALL="$dir" bash -c 'curl -fsSL https://bun.sh/install | bash' >/dev/null 2>&1
  if [ -n "$SUDO" ]; then
    $SUDO ln -sf "$dir/bin/bun" /usr/local/bin/bun
  fi
}

main() {
  cd "$(dirname "$0")/.."

  ensure_rust
  ensure_apt_packages
  ensure_zig
  ensure_nextest
  ensure_just
  ensure_bun

  log "toolchain versions"
  rustc --version
  cargo --version
  zig version
  just --version
  cargo nextest --version | head -1
  bun --version

  log "fetching and building herdr (debug)"
  cargo fetch --locked
  cargo build --locked

  log "herdr bootstrap complete"
}

main "$@"
