require "rubygems"
require "bundler"

Bundler.require

require "./app"
require "./lib/rack_parse_post"

$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)

use Rack::Static,
  :urls=>["/css", "/js"],
  :root=>"public"

UniversalTracker::App.set :tracker, tracker
run UniversalTracker::App

