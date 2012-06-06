require "rubygems"
require "bundler"

Bundler.require

require "./app"
require "./lib/fix_request_content_type"

redis = UniversalTracker::RedisConnection.connection
tracker_manager = UniversalTracker::TrackerManager.new(redis)

use Rack::Static,
  :urls=>["/css", "/js"],
  :root=>"public"

use FixRequestContentType,
  :urls=>[/^\/[-a-z0-9]+\/request$/,
          /^\/[-a-z0-9]+\/release$/,
          /^\/[-a-z0-9]+\/done$/,
          /^\/[-a-z0-9]+\/done\+request$/],
  :content_type=>"application/json"

UniversalTracker::App.set :redis, redis
UniversalTracker::App.set :tracker_manager, tracker_manager
run UniversalTracker::App

