#!/usr/bin/env bash
# Runs the server in the foreground. Config: DATABASE_URL, JWT_SECRET, HOST, PORT.
# Optional: WORKERS (default: cores), PG_CONNECTIONS per worker (default 1).
set -euo pipefail
cd "$(dirname "$0")"
ulimit -Sn "$(ulimit -Hn)" 2>/dev/null || true
export PATH="/opt/ruby/bin:$PATH"
export RUBY_YJIT_ENABLE=1
export RUBY_GC_HEAP_0_INIT_SLOTS=600000 RUBY_GC_HEAP_1_INIT_SLOTS=200000
export RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO=0.40 RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO=0.60
export RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO=0.90
# One worker process per core (SO_REUSEPORT), each an Async reactor (--async-io) that runs requests on
# their connection's fiber (-t 0: no thread pool), so a request waiting on Postgres yields to the others.
# Idle keep-alive connections stay open 75 s: virtual users think ~7 s between pages.
exec bundle exec ruby --yjit --yjit-call-threshold=5 -rhyperion/async_pg -S hyperion \
  -w "${WORKERS:-$(nproc)}" -t 0 --async-io --no-log-requests --idle-keepalive 75 --log-level warn \
  -b "${HOST:-127.0.0.1}" -p "${PORT:-3000}" config.ru
