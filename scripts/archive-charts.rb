require "rubygems"
require "bundler"
Bundler.setup

require File.expand_path("../../app.rb", __FILE__)

slug = ARGV[0] or raise "No slug given."
env = ARGV[1] || "production"

UniversalTracker::RedisConnection.load_config(env)
redis = UniversalTracker::RedisConnection.connection
tracker_manager = UniversalTracker::TrackerManager.new(redis)

tracker = tracker_manager.tracker_for_slug(slug)
tracker.archive_charts

