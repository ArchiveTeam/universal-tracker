require File.expand_path('../../../app', __FILE__)

require 'rack/test'
require 'redis'
require 'rspec'

REDIS_CONFIG_PATH = File.expand_path('../redis_conf.rb', __FILE__)

World do
  Class.new do
    include Rack::Test::Methods

    ##
    # Work items made available in setup steps.
    attr_accessor :available_items

    def app
      UniversalTracker::App
    end
  end.new
end

AfterConfiguration do
  UniversalTracker::App.enable :raise_errors

  configuration = UniversalTracker::TrackerConfig.new

  UniversalTracker::App.set :tracker_config, configuration

  redis_conf = if File.exists?(REDIS_CONFIG_PATH)
                 eval(File.read(REDIS_CONFIG_PATH))
               else
                 { :host => 'localhost', :port => 6379, :db => 1 }
               end

  $redis = Redis.new(redis_conf)
end

Before do
  $redis.flushall
  self.available_items = []
end

at_exit do
  $redis.quit
end
