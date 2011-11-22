require "rubygems"
require "bundler"

Bundler.require

require "./app"

$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)

use Rack::Static,
  :urls=>["/css", "/js"],
  :root=>"public"

UniversalTracker::App.set :tracker, tracker
run UniversalTracker::App

