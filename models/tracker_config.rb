require "active_support/core_ext/hash"

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

    def self.load_from(redis, slug)
      if config_str = redis.hget("trackers", slug)
        TrackerConfig.new(slug, JSON.parse(config_str))
      else
        nil
      end
    end

    def save_to(redis)
      redis.hset("trackers", @slug, JSON.dump(@settings))
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
    config_field :valid_item_regexp,
                 :type=>:regexp,
                 :label=>"Valid item regexp",
                 :default=>"[-_.A-Za-z0-9]{2,50}"
    config_field :min_script_version,
                 :type=>:string,
                 :label=>"Required version (>=)",
                 :default=>""
    config_field :moving_average_interval,
                 :type=>:integer,
                 :label=>"Moving average interval (minutes)",
                 :default=>120
    config_field :history_length,
                 :type=>:integer,
                 :label=>"Number of historical data points",
                 :default=>1000
    config_field :ignore_global_blocked,
                 :type=>:boolean,
                 :label=>"Ignore downloader global block list",
                 :default=>false

    def initialize(slug, settings = {})
      @slug = slug
      @settings = @@defaults.clone.merge(:title=>"#{ slug.capitalize } tracker").merge(Hash[settings.map{ |k,v| [ k.to_sym, v ] }])
      @settings.symbolize_keys!
    end

    def slug
      @slug
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
      @regexp ||= Regexp.new("(#{ @settings[:valid_item_regexp] })")
    end

    def live_log_channel
      "#{ @slug }-log"
    end
  end
end

