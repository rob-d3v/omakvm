#!/usr/bin/env bash
# Builds the omakvm fork of Mickey in containers:
#   build-fork.sh <x86_64|armv7|aarch64> [commit]        (default: the commit below)
# Leaves dist/mickey-fork-linux-<arch>.tar.gz.
#   x86_64: Ubuntu 22.04, so glibc 2.35 or newer, like Mickey's own release.
#   aarch64: Debian bookworm, so glibc 2.36 or newer (NIVA, Pi OS 64-bit).
#   armv7:  Debian buster (hard float), so glibc 2.28 or newer: a Raspberry Pi
#           with a 32-bit system.
set -euo pipefail
arch="${1:?x86_64, armv7 or aarch64}"
# The commit of https://github.com/rob-d3v/mickey (branch omakvm) this builds.
ref="${2:-eea7bbb3818186967941647818fa5c265f327776}"
# rustup's installer, checked against this hash before it runs.
RUSTUP_VERSION="1.28.2"
RUSTUP_SHA256="20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c"
here="$(cd "$(dirname "$0")" && pwd)"
work="${XDG_CACHE_HOME:-$HOME/.cache}/omakvm/build-fork"; mkdir -p "$work"; src="$work/fork-$arch"
rm -rf "$src"
git clone -q https://github.com/rob-d3v/mickey.git "$src"
git -C "$src" checkout -q --detach "$ref"
mkdir -p "$work/cargo-registry" "$here/../dist"
owner="$(id -u):$(id -g)"

case "$arch" in
  x86_64)
    image=ubuntu:22.04; target=x86_64-unknown-linux-gnu; strip=strip
    prepare='apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates build-essential pkg-config libpulse-dev >/dev/null'
    env=''
    ;;
  armv7)
    image=debian:buster; target=armv7-unknown-linux-gnueabihf; strip=arm-linux-gnueabihf-strip
    prepare='printf "deb http://archive.debian.org/debian buster main\ndeb http://archive.debian.org/debian-security buster/updates main\n" > /etc/apt/sources.list
dpkg --add-architecture armhf
apt-get -o Acquire::Check-Valid-Until=false update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates gcc libc6-dev gcc-arm-linux-gnueabihf libc6-dev-armhf-cross pkg-config libpulse-dev:armhf >/dev/null'
    env='export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig'
    ;;
  aarch64)
    image=debian:bookworm; target=aarch64-unknown-linux-gnu; strip=aarch64-linux-gnu-strip
    prepare='dpkg --add-architecture arm64
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates gcc libc6-dev gcc-aarch64-linux-gnu libc6-dev-arm64-cross pkg-config libpulse-dev:arm64 >/dev/null'
    env='export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig'
    ;;
  *) echo "unknown arch $arch" >&2; exit 2 ;;
esac

docker rm -f "omakvm-fork-$arch" >/dev/null 2>&1 || true
docker run --rm --name "omakvm-fork-$arch" -v "$src:/src" -v "$work/cargo-registry:/root/.cargo/registry" -w /src "$image" bash -c "
set -eu
$prepare
curl -sSfo /tmp/rustup-init https://static.rust-lang.org/rustup/archive/$RUSTUP_VERSION/x86_64-unknown-linux-gnu/rustup-init
echo \"$RUSTUP_SHA256  /tmp/rustup-init\" | sha256sum -c - >/dev/null
chmod +x /tmp/rustup-init
/tmp/rustup-init -y -q --profile minimal --target $target >/dev/null
. /root/.cargo/env
$env
cargo build --release --workspace --locked --target $target
$strip target/$target/release/mickey target/$target/release/mickey-ui
chown -R $owner /src/target /root/.cargo/registry
"

out="$here/../dist/mickey-fork-linux-$arch"
rm -rf "$out"; mkdir -p "$out"
cp "$src/target/$target/release/mickey" "$src/target/$target/release/mickey-ui" "$out/"
( cd "$src/packaging/linux" && cp install.sh uninstall.sh mickey.service 99-mickey-uinput.rules mickey-autostart.desktop mickey-settings.desktop mickey.png "$out/" )
cp "$src/LICENSE" "$out/"
git -C "$src" rev-parse HEAD >"$out/SOURCE-COMMIT"
echo "https://github.com/rob-d3v/mickey (branch omakvm): Mickey v0.4.5 plus the changes in that branch" >"$out/SOURCE"
tar -C "$here/../dist" -czf "$here/../dist/mickey-fork-linux-$arch.tar.gz" "mickey-fork-linux-$arch"
sha256sum "$here/../dist/mickey-fork-linux-$arch.tar.gz"
echo "BUILD-OK $arch"
