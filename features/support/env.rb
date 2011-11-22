$LOAD_PATH.unshift(File.expand_path('../../..', __FILE__))

ENV['RACK_ENV'] = 'test'

require 'app'

require 'rack/test'
require 'rspec'

World do
  Class.new do
    include Rack::Test::Methods
    set :environment, :test

    ##
    # Work items made available in setup steps.
    attr_accessor :available_items

    def app
      UniversalTracker::App
    end

    def tracker
      $tracker
    end
  end.new
end

AfterConfiguration do
  $redis = UniversalTracker::RedisConnection.connection

  config = UniversalTracker::TrackerConfig.new
  $tracker = UniversalTracker::Tracker.new($redis, config)

  UniversalTracker::App.set :tracker, $tracker
  UniversalTracker::App.enable :raise_errors
end

Before do
  $redis.flushall
  self.available_items = []
end

at_exit do
  $redis.quit
end
