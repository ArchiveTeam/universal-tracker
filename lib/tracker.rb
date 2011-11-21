require "time"
require "active_support/ordered_hash"

module UniversalTracker
  class Tracker
    def queues
      resp = $redis.pipelined do
        $redis.keys("todo:d:*")
        $redis.scard("todo")
      end
      
      queues = []
      queues << { :key=>"todo",
                  :title=>"Main queue",
                  :length=>resp[1].to_i }

      if resp[0].size > 0
        keys = resp[0].sort
        resp = $redis.pipelined do
          keys.each do |queue|
            $redis.scard(queue)
          end
        end.each_with_index do |length, index|
          if queue=~/^todo:d:(.+)$/
            queues << { :key=>keys[index],
                        :title=>"Queue for #{ keys[index] }",
                        :length=>length.to_i }
          end
        end
      end

      queues
    end

    def number_of_claims
      $redis.zcard("out")
    end

    def claims_per_downloader
      claims = $redis.hgetall("claims")
      out = $redis.zrange("out", 0, -1, :with_scores=>true)
      claims_per_downloader = ActiveSupport::OrderedHash.new{ |h,k| h[k] = [] }
      out.each_slice(2) do |username, time|
        if claims[username]
          ip, downloader = claims[username].split(" ", 2)
        else
          ip, downloader = "unknown", "unknown"
        end
        claims_per_downloader[downloader] << { :username=>username,
                                               :ip=>ip,
                                               :since=>Time.at(time.to_i).utc }
      end
      claims_per_downloader
    end
  end
end

