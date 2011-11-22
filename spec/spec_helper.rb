$LOAD_PATH.unshift(File.expand_path("../..", __FILE__))

require "app"
require "rspec"

ENV["RACK_ENV"] ||= "test"

$redis = UniversalTracker::RedisConnection.connection

RSpec.configure do |c|
  c.before :each do
    $redis.flushdb
  end
end

