require "rubygems"
require "bundler"

Bundler.require

if ENV["redis_host"]
  $redis = Redis.new(:host=>ENV["redis_host"],
                     :port=>ENV["redis_port"],
                     :password=>ENV["redis_password"],
                     :db=>ENV["redis_db"])
elsif File.exists?("./redis.json")
  redis_conf = Hash[JSON.parse(File.read("./redis.json")).map do |k,v|
    [ k.to_sym, v ]
  end]
  $redis = Redis.new(redis_conf)
else
  raise "No Redis config found."
end

if ENV["tracker_config"]
  tracker_config = JSON.parse(ENV["tracker_config"])
elsif File.exists?("./tracker.json")
  tracker_config = JSON.parse(File.read("./tracker.json"))
else
  raise "No tracker config found."
end

require "./app"

use Rack::Static,
  :urls=>["/css", "/js"],
  :root=>"public"

App.set :tracker, tracker_config
run App

