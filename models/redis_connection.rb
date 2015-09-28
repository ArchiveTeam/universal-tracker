require "json"
require "active_support/core_ext/hash"
require "redis/connection/hiredis"
require "redis"

REDIS_CONFIG_PATH = File.expand_path("../../config/redis.json", __FILE__)
WARRIOR_REDIS_CONFIG_PATH = File.expand_path("../../config/warrior_redis.json", __FILE__)

module UniversalTracker
  class ConfigError < StandardError
  end

  class RedisConnection
    class << self
      def connection
        @redis ||= Redis.new(config)
      end

      def load_config(environment=ENV["RACK_ENV"], config_path=REDIS_CONFIG_PATH)
        @config = if ENV["redis_host"]
          {
            :host=>ENV["redis_host"],
            :port=>ENV["redis_port"],
            :password=>ENV["redis_password"],
            :db=>ENV["redis_db"]
          }

        elsif File.exists?(config_path)
          configs = JSON.parse(File.read(config_path))
          configs.symbolize_keys!
          if not configs.has_key?(environment.to_sym)
            raise ConfigError.new("No Redis configuration for the #{environment} environment.")
          end
          configs[environment.to_sym].symbolize_keys!

        else
          raise ConfigError.new("Missing Redis configuration.")
        end
      end

      def config
        @config || load_config
      end
    end
  end

  class WarriorHQRedisConnection < RedisConnection
    class << self
      def connection
        begin
          @redis ||= Redis.new(config)
        rescue ConfigError
          puts "Warrior HQ not configured"
        end
      end

      def load_config(environment=ENV["RACK_ENV"], config_path=WARRIOR_REDIS_CONFIG_PATH)
        super(environment, config_path)
      end
    end
  end
end

