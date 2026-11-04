#!/usr/bin/env bash
# Runs as a normal user: installs the pinned gems (Gemfile.lock) into vendor/bundle. pg and ffi compile
# from source against the box's libraries, and Itsi (itsi-server, itsi-scheduler) compiles from its Rust
# source with the toolchain install.sh put in /opt (its crates download into vendor/cargo).
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/ruby/bin:/opt/cargo/bin:$PATH"
export RUSTUP_HOME=/opt/rustup CARGO_HOME="$PWD/vendor/cargo"
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle install --jobs 4
