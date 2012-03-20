require "rubygems"
require "bundler"

Bundler.require

require "./app"
require "./lib/fix_request_content_type"

$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)

use Rack::Static,
  :urls=>["/css", "/js"],
  :root=>"public"

use FixRequestContentType,
  :urls=>["/request", "/release", "/done", "/done+request"],
  :content_type=>"application/json"

UniversalTracker::App.set :tracker, tracker
run UniversalTracker::App

