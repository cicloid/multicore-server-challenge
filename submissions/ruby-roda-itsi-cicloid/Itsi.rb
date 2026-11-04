# frozen_string_literal: true

# Itsi (Rust: hyper on tokio) owns the sockets and HTTP/1.1; Ruby runs the Roda app. One worker process
# per core (Ruby runs one thread at a time per process), each a single Ruby thread running Itsi's fiber
# scheduler, so a request waiting on Postgres doesn't hold up the others.
require "etc"

workers Integer(ENV.fetch("WORKERS", Etc.nprocessors.to_s))
threads 1
fiber_scheduler true
preload true # load the app once in the master; workers fork from it
bind "http://#{ENV.fetch("HOST", "127.0.0.1")}:#{ENV.fetch("PORT", "3000")}"
listen_backlog 65_535 # the kernel caps it at net.core.somaxconn
# hyper times out a connection that sends no request head within this long, idle keep-alive connections
# included. Virtual users think for ~7 s between pages and Nginx (if used) keeps idle upstreams for 60 s.
header_read_timeout 75.0
# Requests waiting for the Ruby thread. The default (30 x threads) answers 503 past it under a burst.
ruby_thread_request_backlog_size 100_000
log_level ENV.fetch("ITSI_LOG", "warn").to_sym
rackup_file "config.ru"
