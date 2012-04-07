# Clears the log and prints the log lines to STDOUT.
#
# Use this to free some Redis memory.
#
# Example:
#   ruby script/drain-log.rb > current.log
#

require "rubygems"
require File.expand_path("../../app.rb", __FILE__)

env = ARGV[0] || "production"

UniversalTracker::RedisConnection.load_config(env)
$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)

loop do
  resp = $redis.pipelined do
    1000.times do |i|
      $redis.lpop("log")
    end
  end.compact
  puts resp
  break if resp.empty?
end

