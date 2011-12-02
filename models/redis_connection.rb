require "json"
require "active_support/core_ext/hash"
require "redis/connection/hiredis"
require "redis"

REDIS_CONFIG_PATH = File.expand_path("../../config/redis.json", __FILE__)

module UniversalTracker
  class RedisConnection
    class << self
      def connection
        @redis ||= Redis.new(config)
      end

      def load_config(environment=ENV["RACK_ENV"])
        @config = if ENV["redis_host"]
          {
            :host=>ENV["redis_host"],
            :port=>ENV["redis_port"],
            :password=>ENV["redis_password"],
            :db=>ENV["redis_db"]
          }

        elsif File.exists?(REDIS_CONFIG_PATH)
          configs = JSON.parse(File.read(REDIS_CONFIG_PATH))
          configs.symbolize_keys!
          if not configs.has_key?(environment.to_sym)
            raise "No Redis configuration for the #{environment} environment."
          end
          configs[environment.to_sym].symbolize_keys!

        else
          raise "Missing Redis configuration."
        end
      end

      def config
        @config || load_config
      end
    end
  end
end

