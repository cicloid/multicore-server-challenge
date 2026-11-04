#!/usr/bin/env bash
# Runs once as root on a clean Ubuntu 24.04. Builds from pinned, checksummed sources:
#   Ruby 4.0 (YJIT, jemalloc) under /opt/ruby and libsodium 1.0.22 under /usr/local. libpq-dev comes from
#   the PGDG repo the box already uses for Postgres 18 (libpq 18), so pg compiles against the same libpq.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential curl ca-certificates pkg-config \
  libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev libjemalloc-dev rustc \
  libpq-dev libcrypt1 libclang-dev
# libcrypt1: bcrypt (auth.rb). libclang-dev: bindgen, for Itsi's Rust build.

# Tune for the CPU it is built on (the benchmark droplet is x86_64). On arm64 -march=native combines
# with Ruby's pointer-authentication flags into binaries that crash under some VMs, so skip it there.
NATIVE=""
[ "$(uname -m)" = x86_64 ] && NATIVE="-march=native"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fetch() { # fetch <url> <sha256> <file>
  curl -fsSL --retry 3 "$1" -o "$work/$3"
  echo "$2  $work/$3" | sha256sum -c -
}

# libsodium: HMAC-SHA256 for JWT verification, loaded by rbnacl through FFI.
SODIUM=1.0.22
if ! grep -q "$SODIUM" /usr/local/lib/pkgconfig/libsodium.pc 2>/dev/null; then
  fetch "https://download.libsodium.org/libsodium/releases/libsodium-$SODIUM.tar.gz" \
    adbdd8f16149e81ac6078a03aca6fc03b592b89ef7b5ed83841c086191be3349 sodium.tar.gz
  tar -xzf "$work/sodium.tar.gz" -C "$work"
  (cd "$work/libsodium-$SODIUM" && CFLAGS="-O3 $NATIVE" ./configure --disable-static \
    && make -j"$(nproc)" && make install)
  ldconfig
fi

# Rust, for building Itsi from source (build.sh): rustup-init 1.29.3 (checksummed) installs exactly
# Rust 1.99.1 under /opt/rustup and /opt/cargo, readable by the build user.
RUSTUP=1.29.3
RUST=1.99.1
if [ "$(RUSTUP_HOME=/opt/rustup /opt/cargo/bin/rustc --version 2>/dev/null | cut -d' ' -f2)" != "$RUST" ]; then
  case "$(uname -m)" in
    x86_64) triple=x86_64-unknown-linux-gnu; sum=b1c8cb14e30889e7e2999e6b69e62d9e9b9ffc0f4df8180564d306d9680e6c55 ;;
    aarch64) triple=aarch64-unknown-linux-gnu; sum=9f608c142e0e38a78957d0661ba1dfaf0b6fb37184cfaa4b9a0aa57af6184282 ;;
    *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
  esac
  fetch "https://static.rust-lang.org/rustup/archive/$RUSTUP/$triple/rustup-init" "$sum" rustup-init
  chmod +x "$work/rustup-init"
  RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo "$work/rustup-init" -y --no-modify-path --profile minimal \
    --default-toolchain "$RUST"
  chmod -R a+rX /opt/rustup /opt/cargo
fi

RUBY_VERSION=4.0.7
RUBY_SHA256=911ace20f90d068ca0e4dda6d0e4f0f81e52e52f2dd4f4004c721e253412e82d
if [ "$(/opt/ruby/bin/ruby -e 'print RUBY_VERSION' 2>/dev/null)" != "$RUBY_VERSION" ]; then
  fetch "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-$RUBY_VERSION.tar.gz" "$RUBY_SHA256" ruby.tar.gz
  cd "$work"
  tar -xzf ruby.tar.gz
  cd "ruby-$RUBY_VERSION"
  ./configure --prefix=/opt/ruby --enable-yjit --with-jemalloc --disable-install-doc --disable-install-rdoc \
    cflags="$NATIVE"
  make -j"$(nproc)"
  make install
fi
/opt/ruby/bin/ruby --yjit -e 'abort "YJIT unavailable" unless RubyVM::YJIT.enabled?; puts RUBY_DESCRIPTION'
