require "rubygems"
require "json"

redis_conf = JSON.parse(File.read("redis.json"))
tracker_conf = JSON.parse(File.read("tracker.json"))

env_vars = {}
redis_conf.each do |key, value|
  env_vars["redis_#{ key }"] = value
end
env_vars["tracker_config"] = JSON.dump(tracker_conf)

system("heroku", "config:add",
       *env_vars.map{ |key,value| "#{key}=#{value}" })

