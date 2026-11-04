#!/usr/bin/env bash
# Runs as a normal user: installs the pinned gems (Gemfile.lock) into vendor/bundle. pg and ffi compile
# from source against the box's libraries.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/ruby/bin:$PATH"
bundle config set --local deployment true
bundle config set --local path vendor/bundle
bundle install --jobs 4
