require "time"
require "json"
require "active_support/ordered_hash"
require_relative "../lib/array_systematic_sample"
require_relative "tracker_config"
require_relative "tracker/statistics"
require_relative "tracker/transactions"

module UniversalTracker
  class Tracker
    include Statistics
    include Transactions

    attr_accessor :redis
    attr_accessor :config

    def initialize(redis, config = nil)
      @redis = redis
      @config = config || TrackerConfig.load_from(redis)
    end

    def admin_password
      redis.get("admin_password")
    end
  end
end

