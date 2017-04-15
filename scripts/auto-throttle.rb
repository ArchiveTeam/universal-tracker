# Change the value of requests_per_minute based
# on the response time of the host
#
# Meant to be run in cron
#
# To add to cron, run:
#   crontab -e
# Add this line to the crontab file:
#   "* * * * * /usr/bin/ruby /path/to/auto-throttle.rb"
#

require "rubygems"
require File.expand_path("../../app.rb", __FILE__)

env = ARGV[0] || "production"
# FIXME: This should come from somewhere in the config?
host = 'http://example.com/endpoint'

UniversalTracker::RedisConnection.load_config(env)
$redis = UniversalTracker::RedisConnection.connection
tracker = UniversalTracker::Tracker.new($redis)

response_time = 100
# FIXME: use the power of ruby to fetch host response time
# response_time = response_time_of(endpoint)

rpm = tracker.requests_per_minute
unless rpm.is_a? Fixnum
  rpm = 200
end

if response_time < 400 # ms
  new_rpm = rpm + 100
  tracker.requests_per_minute = new_rpm
elsif response_time > 600 # ms
  new_rpm = rpm - 200
  tracker.requests_per_minute = new_rpm
end


