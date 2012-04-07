# Reads items from STDIN (one per line) and adds them to the queue.
#
# Example:
#   cat users.txt | ruby script/enqueue.rb
#

require "rubygems"
require File.expand_path("../../app.rb", __FILE__)

env = ARGV[0] || "production"

UniversalTracker::RedisConnection.load_config(env)
$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)
p $redis

batch = []
while line = gets
  unless line.strip.empty?
    batch << line.strip

    if batch.size >= 10000
      tracker.add_items!(batch)
      batch = []
    end
  end
end

tracker.add_items!(batch) unless batch.empty?

