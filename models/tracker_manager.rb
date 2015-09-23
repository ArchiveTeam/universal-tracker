require "json"
require "bcrypt"
require "active_support/ordered_hash"
require File.expand_path("../tracker_manager_config", __FILE__)
module UniversalTracker
  class TrackerManager
    attr_accessor :redis
    attr_accessor :config

    def initialize(redis, config = nil)
      @redis = redis
      @config = config || TrackerManagerConfig.load_from(redis)
    end

    def create_tracker(slug)
      slug = slug.downcase.delete("^a-z0-9-")
      config = TrackerConfig.new(slug)
      config.save_to(redis)
      Tracker.new(redis, self, config)
    end

    def tracker_for_slug(slug)
      config = TrackerConfig.load_from(redis, slug)
      config && Tracker.new(redis, self, config)
    end

    def trackers
      (redis.hgetall("trackers") || {}).map do |slug, config_json|
        Tracker.new(redis, self, TrackerConfig.new(slug, JSON.parse(config_json)))
      end
    end

    def admins
      redis.smembers("admins").sort
    end

    def add_admin(username)
      redis.sadd("admins", username)
    end

    def remove_admin(username)
      redis.srem("admins", username)
    end

    def users
      redis.hkeys("users").sort
    end

    def users_with_password
      Hash[redis.hgetall("users").map do |username, password|
        [ username, BCrypt::Password.new(password) ]
      end]
    end

    def update_password(username, password)
      add_user(username, password)
    end

    def add_user(username, password)
      username = username.downcase.delete("^a-z0-9-")
      password = password.strip
      unless username.empty? or password.empty?
        password = BCrypt::Password.create(password)
        redis.hset("users", username, password)
      end
    end

    def destroy_user(username)
      username = username.downcase.delete("^a-z0-9-")
      trackers.each do |tracker|
        tracker.remove_admin(username)
      end
      redis.hdel("users", username)
      redis.srem("admins", username)
    end
  end
end

