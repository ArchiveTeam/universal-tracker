require File.expand_path('../../../app', __FILE__)

require 'rack/test'
require 'redis'
require 'rspec'

REDIS_CONFIG_PATH = File.expand_path('../redis_conf.rb', __FILE__)

World do
  Class.new do
    include Rack::Test::Methods

    def app
      App
    end
  end.new
end

AfterConfiguration do
  conf = if File.exists?(REDIS_CONFIG_PATH)
           eval(File.read(REDIS_CONFIG_PATH))
         else
           { :host => 'localhost', :port => 6379, :db => 1 }
         end

  $redis = Redis.new(conf)
end

Before do
  $redis.flushall
end

at_exit do
  $redis.quit
end
