#!/usr/bin/env ruby
#
# Removes log messages from Redis and writes them to a file:
#   logs/log-#{ tracker }-#{ date }.log
#

require "rubygems"
require "json"
require File.expand_path("../../app.rb", __FILE__)

env = ARGV[0] || "production"

UniversalTracker::RedisConnection.load_config(env)
UniversalTracker::RedisConnection.config[:timeout] = 60
$redis = UniversalTracker::RedisConnection.connection

log_dir = File.expand_path("../../logs/", __FILE__)

$interrupt = false

trap("INT") do
  puts "Shutting down."
  $interrupt = true
end

def keys_without_timeout(*args)
  $redis.keys(*args)
rescue Errno::EAGAIN
  puts $!
  retry
end

def lpop_without_timeout(*args)
  $redis.lpop(*args)
rescue Errno::EAGAIN
  puts $!
  retry
end

until $interrupt
  trackers = keys_without_timeout("*:log").map{|k|k.split(":").first}
  trackers.each do |tracker|
    while line = lpop_without_timeout("#{ tracker }:log")
      timestamp = JSON.parse(line)["at"]
      date = timestamp[/^[-0-9]+/]
      File.open("#{ log_dir }/log-#{ tracker }-#{ date }.log", "a") do |f|
        f.puts line
      end
    end
  end
  sleep 15 unless $interrupt
end

