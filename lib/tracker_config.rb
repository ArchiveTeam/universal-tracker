module UniversalTracker
  class TrackerConfig
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
      TrackerConfig.new(JSON.parse(redis.get("tracker_config") || "{}"))
    end

    def save_to(redis)
      redis.set("tracker_config", JSON.dump(settings))
    end


    config_field :title,
                 :type=>:string,
                 :label=>"Tracker title",
                 :default=>"My tracker"
    config_field :item_type,
                 :type=>:string,
                 :label=>"Item tracked (users, profiles, things)",
                 :default=>"items"
    config_field :domains,
                 :type=>:map,
                 :label=>"Domains",
                 :default=>{"data"=>"data"}
    config_field :redis_pubsub_channel,
                 :type=>:string,
                 :label=>"Redis Pub/Sub channel",
                 :default=>"tracker-log"
    config_field :live_log_host,
                 :type=>:string,
                 :label=>"Live logging host",
                 :default=>""
    config_field :live_log_channel,
                 :type=>:string,
                 :label=>"Live logging channel",
                 :default=>""
    config_field :valid_item_regexp,
                 :type=>:regexp,
                 :label=>"Valid item regexp",
                 :default=>"[-_.A-Za-z0-9]{2,50}"
    config_field :moving_average_interval,
                 :type=>:integer,
                 :label=>"Moving average interval (minutes)",
                 :default=>120
    config_field :history_length,
                 :type=>:integer,
                 :label=>"Number of historical data points",
                 :default=>1000

    def initialize(settings = {})
      @settings = @@defaults.clone.merge(Hash[settings.map{ |k,v| [ k.to_sym, v ] }])
    end

    def []=(a,b)
      @settings[a] = b
    end

    def each_field
      @@config_fields.each do |field|
        yield({ :value=>send(field[:name]) }.merge(field))
      end
    end

    def valid_item_regexp_object
      @regexp ||= Regexp.new("(#{ @settings["valid_item_regexp"] })")
    end
  end
end

