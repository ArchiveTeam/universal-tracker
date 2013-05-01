# Release all claims by a downloader.
# 
# Usage:
#
#    ruby release-claims.rb SLUG DOWNLOADER
#
require "rubygems"
require "bundler"
Bundler.setup

require File.expand_path("../../app.rb", __FILE__)

slug = ARGV[0] or raise "No slug given."
downloader = ARGV[1] or raise "No downloader given."
env = ARGV[2] || "production"

UniversalTracker::RedisConnection.load_config(env)
redis = UniversalTracker::RedisConnection.connection
tracker_manager = UniversalTracker::TrackerManager.new(redis)

tracker = tracker_manager.tracker_for_slug(slug)
out = tracker.release_by_downloader(downloader)

puts "Released #{ out.size }"

