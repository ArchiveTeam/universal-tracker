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

