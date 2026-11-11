#!/usr/bin/env bash
# Builds the omakvm fork of Mickey in containers:
#   build-fork.sh <x86_64|armv7> [git ref]       (default ref: omakvm)
# Leaves dist/mickey-fork-linux-<arch>.tar.gz.
#   x86_64: Ubuntu 22.04, so glibc 2.35 or newer, like Mickey's own release.
#   armv7:  Debian buster (hard float), so glibc 2.28 or newer: a Raspberry Pi
#           with a 32-bit system.
set -euo pipefail
arch="${1:?x86_64 or armv7}"
ref="${2:-omakvm}"
here="$(cd "$(dirname "$0")" && pwd)"
work="${XDG_CACHE_HOME:-$HOME/.cache}/omakvm/build-fork"; mkdir -p "$work"; src="$work/fork-$arch"
rm -rf "$src"
git clone -q --depth 1 --branch "$ref" https://github.com/rob-d3v/mickey.git "$src"
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
  *) echo "unknown arch $arch" >&2; exit 2 ;;
esac

docker rm -f "omakvm-fork-$arch" >/dev/null 2>&1 || true
docker run --rm --name "omakvm-fork-$arch" -v "$src:/src" -v "$here/cargo-registry:/root/.cargo/registry" -w /src "$image" bash -c "
set -eu
$prepare
curl -sSf https://sh.rustup.rs | sh -s -- -y -q --profile minimal --target $target >/dev/null
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
