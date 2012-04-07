# Sets the tracker admin password in Redis.
#
# Example:
#   ruby script/set-admin-password.rb
#

require "rubygems"
require File.expand_path("../../app.rb", __FILE__)

env = ARGV[0] || "production"

UniversalTracker::RedisConnection.load_config(env)
$redis = UniversalTracker::RedisConnection.connection

$stdout.sync = true
print "New password? "
password = gets

$redis.set("admin_password", password.strip)

