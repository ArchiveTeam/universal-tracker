require "rubygems"
require "json"

heroku_app = ARGV[0]
if heroku_app.nil?
  puts "Usage: set_vars_heroku.rb <NAME OF HEROKU APP>"
  exit
end

redis_conf = JSON.parse(File.read("redis.json"))
tracker_conf = JSON.parse(File.read("tracker.json"))

env_vars = {}
redis_conf.each do |key, value|
  env_vars["redis_#{ key }"] = value
end
env_vars["tracker_config"] = JSON.dump(tracker_conf)

system("heroku", "config:add", "--app", heroku_app,
       *env_vars.map{ |key,value| "#{key}=#{value}" })

