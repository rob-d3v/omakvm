#!/usr/bin/env bash
# Builds Mickey for ARM64 Linux from its unchanged source, in a container:
#   packaging/build-aarch64.sh [tag]          (default: v0.4.5)
# Leaves dist/mickey-linux-aarch64.tar.gz and dist/SHA256SUMS.
# Needs docker and git. Debian bookworm, so the result runs on glibc 2.36 or newer.
set -euo pipefail
tag="${1:-v0.4.5}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${XDG_CACHE_HOME:-$HOME/.cache}/omakvm/build-aarch64"
rm -rf "$work/src" "$work/pkg"
mkdir -p "$work/cargo-registry" "$work/pkg/mickey-linux-aarch64" "$here/dist"
git clone -q --depth 1 --branch "$tag" https://github.com/EduardoMG12/mickey.git "$work/src"

docker run --rm -v "$work/src:/src" -v "$work/cargo-registry:/usr/local/cargo/registry" -w /src rust:1-bookworm bash -c '
set -eu
dpkg --add-architecture arm64
apt-get update -qq
apt-get install -y -qq gcc-aarch64-linux-gnu libc6-dev-arm64-cross libpulse-dev:arm64 pkg-config >/dev/null
rustup target add aarch64-unknown-linux-gnu
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
cargo build --release --workspace --locked --target aarch64-unknown-linux-gnu
aarch64-linux-gnu-strip target/aarch64-unknown-linux-gnu/release/mickey target/aarch64-unknown-linux-gnu/release/mickey-ui
chown -R '"$(id -u):$(id -g)"' /src/target /usr/local/cargo/registry
'

out="$work/pkg/mickey-linux-aarch64"
cp "$work/src/target/aarch64-unknown-linux-gnu/release/mickey" "$work/src/target/aarch64-unknown-linux-gnu/release/mickey-ui" "$out/"
( cd "$work/src/packaging/linux" && cp install.sh uninstall.sh mickey.service 99-mickey-uinput.rules mickey-autostart.desktop mickey-settings.desktop mickey.png "$out/" )
cp "$work/src/LICENSE" "$out/"
git -C "$work/src" rev-parse HEAD >"$out/SOURCE-COMMIT"
tar -C "$work/pkg" -czf "$here/dist/mickey-linux-aarch64.tar.gz" mickey-linux-aarch64
( cd "$here/dist" && sha256sum mickey-linux-aarch64.tar.gz >SHA256SUMS && cat SHA256SUMS )
