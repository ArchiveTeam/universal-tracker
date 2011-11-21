require "time"
require "json"
require "active_support/ordered_hash"
require File.join(File.dirname(__FILE__), "array_systematic_sample")
require File.join(File.dirname(__FILE__), "tracker_config")
require File.join(File.dirname(__FILE__), "tracker/statistics")
require File.join(File.dirname(__FILE__), "tracker/transactions")

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
  end
end

