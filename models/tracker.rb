require "time"
require "json"
require "active_support/ordered_hash"
require File.expand_path("../../lib/array_systematic_sample", __FILE__)
require File.expand_path("../tracker_config", __FILE__)
require File.expand_path("../tracker/statistics", __FILE__)
require File.expand_path("../tracker/transactions", __FILE__)

module UniversalTracker
  class Tracker
    include Statistics
    include Transactions

    attr_accessor :redis
    attr_accessor :tracker_manager
    attr_accessor :config

    def initialize(redis, tracker_manager, config = nil)
      @redis = redis
      @tracker_manager = tracker_manager
      @config = config
    end

    def slug
      @config.slug
    end

    def prefix
      "#{ slug }:"
    end

    def admins
      redis.smembers("#{ prefix }tracker_admins")
    end

    def admins=(new_admins)
      redis.del("#{ prefix }tracker_admins")
      new_admins.each do |username|
        add_admin(username)
      end
    end

    def add_admin(username)
      redis.sadd("#{ prefix }tracker_admins", username)
    end

    def remove_admin(username)
      redis.srem("#{ prefix }tracker_admins", username)
    end

    def destroy
      keys = %w{ tracker_admins log out downloader_count todo done blocked items_done_chartdata claims downloader_version downloader_bytes downloader_budget requests_per_minute min_downloader_budget http_upload_target upload_target inactive_upload_target domain_bytes blocked-log }.map{|k| "#{ prefix }#{ k }" }
      %w{ downloader_chartdata:* log:* todo:* requests_processed:* }.map do |k|
        keys.push(*redis.keys("#{ prefix }#{ k }"))
      end
      keys.each do |key|
        redis.del(key)
      end
      redis.hdel("trackers", slug)
    end
  end
end

