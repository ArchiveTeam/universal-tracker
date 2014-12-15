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

  UniversalTracker::App.set :redis, $redis
  UniversalTracker::App.enable :raise_errors
  
  $tracker_manager = UniversalTracker::TrackerManager.new($redis)
  UniversalTracker::App.set :tracker_manager, $tracker_manager
end

Before do
  $redis.flushdb
  self.available_items = []
end

at_exit do
  $redis.quit
end
