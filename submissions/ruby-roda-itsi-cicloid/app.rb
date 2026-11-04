# frozen_string_literal: true

require "roda"
require_relative "conduit"

# One Conduit per worker process, opened on the first request: Postgres connections must be made after
# Itsi forks, inside its fiber scheduler (the pipelined client runs a reader and a flusher fiber per
# connection). The mutex is fiber-aware, so concurrent first requests wait for the one that connects.
module Backend
  LOCK = Mutex.new
  # Per worker. WORKERS x PG_CONNECTIONS must stay at 95 or below.
  PG_CONNECTIONS = Integer(ENV.fetch("PG_CONNECTIONS", "1"))

  def self.conduit
    @conduit || LOCK.synchronize do
      @conduit ||= begin
        db = DB.new(ENV.fetch("DATABASE_URL"), PG_CONNECTIONS, SQL::STATEMENTS, setup: SQL::SETUP)
        db.start
        Conduit.new(db, ENV.fetch("JWT_SECRET"))
      end
    end
  end
end

# The routes, as a Roda routing tree. Each endpoint hands the request's parts to Conduit and sets the
# status from its answer; the document is already JSON (built by Postgres for almost every endpoint).
class App < Roda
  plugin :all_verbs # r.put and r.delete
  plugin :default_headers, "content-type" => "application/json"
  plugin :unescape_path # path segments (usernames, slugs) arrive percent-decoded
  plugin :not_found do
    Conduit::NOT_FOUND[1]
  end

  route do |r|
    c = Backend.conduit
    auth = env["HTTP_AUTHORIZATION"]

    r.on "api" do
      r.is "tags" do
        r.get { reply { c.tags } }
      end

      r.is "user" do
        r.get { reply { c.current_user(auth) } }
        r.put { reply { c.update_user(auth, body) } }
      end

      r.on "users" do
        r.is { r.post { reply { c.register(body) } } }
        r.is("login") { r.post { reply { c.login(body) } } }
      end

      r.on "profiles", String do |username|
        r.is { r.get { reply { c.profile(username, auth) } } }
        r.is "follow" do
          r.post { reply { c.follow(:follow, username, auth) } }
          r.delete { reply { c.follow(:unfollow, username, auth) } }
        end
      end

      r.on "articles" do
        r.is do
          r.get { reply { c.list(env["QUERY_STRING"], auth) } }
          r.post { reply { c.create_article(auth, body) } }
        end
        r.get("feed") { reply { c.feed(env["QUERY_STRING"], auth) } }

        r.on String do |slug|
          r.is do
            r.get { reply { c.article(slug, auth) } }
            r.put { reply { c.update_article(slug, auth, body) } }
            r.delete { reply { c.delete_article(slug, auth) } }
          end
          r.is "favorite" do
            r.post { reply { c.favorite(:favorite, slug, auth) } }
            r.delete { reply { c.favorite(:unfavorite, slug, auth) } }
          end
          r.on "comments" do
            r.is do
              r.get { reply { c.comments(slug, auth) } }
              r.post { reply { c.create_comment(slug, auth, body) } }
            end
            r.is(String) { |id| r.delete { reply { c.delete_comment(slug, id, auth) } } }
          end
        end
      end
    end
  end

  private

  # Runs a handler and turns its [status, document] into the response.
  def reply
    status, document = Conduit.guard { yield }
    response.status = status
    document
  end

  def body
    input = env["rack.input"] or return nil
    data = input.read
    data.nil? || data.empty? ? nil : data
  end
end
