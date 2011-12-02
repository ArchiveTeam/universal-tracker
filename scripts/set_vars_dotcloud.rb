require "rubygems"
require "json"

dotcloud_app = ARGV[0]
if dotcloud_app.nil?
  puts "Usage: set_vars_dotcloud.rb NAME-OF-DOTCLOUD-APP [ENVIRONMENT]"
  exit
end

environment = ARGV[1] || ENV["RACK_ENV"] || "production"

REDIS_CONFIG_PATH = File.expand_path("../../config/redis.json", __FILE__)
redis_conf = JSON.parse(File.read(REDIS_CONFIG_PATH))

env_vars = {}
redis_conf[environment].each do |key, value|
  env_vars["redis_#{ key }"] = value
end

system("dotcloud", "var", "set", dotcloud_app,
       *env_vars.map{ |key,value| "#{key}=#{value}" })

