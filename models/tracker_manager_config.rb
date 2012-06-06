require "active_support/core_ext/hash"

module UniversalTracker
  class TrackerManagerConfig
    def self.config_field(name, options = {})
      class_eval %{
        def #{ name } ; @settings[:#{ name }] ; end
      }
      @@defaults ||= {}
      @@defaults[name.to_sym] = options[:default]
      (@@config_fields ||= []) << { :name=>name.to_sym }.merge(options)
    end

    def self.config_fields
      @@config_fields
    end

    def self.load_from(redis)
      TrackerManagerConfig.new(JSON.parse(redis.get("tracker_manager_config") || "{}"))
    end

    def save_to(redis)
      redis.set("tracker_manager_config", JSON.dump(@settings))
    end


    config_field :redis_pubsub_channel,
                 :type=>:string,
                 :label=>"Redis Pub/Sub channel",
                 :default=>"tracker-log"
    config_field :live_log_host,
                 :type=>:string,
                 :label=>"Live logging host",
                 :default=>""

    def initialize(settings = {})
      @settings = @@defaults.clone.merge(Hash[settings.map{ |k,v| [ k.to_sym, v ] }])
      @settings.symbolize_keys!
    end

    def []=(a,b)
      @settings[a] = b
    end

    def each_field
      @@config_fields.each do |field|
        yield({ :value=>send(field[:name]) }.merge(field))
      end
    end
  end
end

