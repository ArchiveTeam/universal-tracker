require "time"
require "json"
require "active_support/ordered_hash"
require File.join(File.dirname(__FILE__), "../array_systematic_sample")

module UniversalTracker
  class Tracker
    module Transactions
      def block_ip(request_ip, invalid_done_hash=nil)
        redis.pipelined do
          redis.sadd("blocked", request_ip)
          redis.rpush("blocked_log", JSON.dump(invalid_done_hash)) if invalid_done_hash
        end
      end

      def ip_blocked?(request_ip)
        redis.sismember("blocked", request_ip)
      end

      def random_item
        redis.srandmember("todo")
      end

      def item_done?(item)
        redis.sismember("done", item)
      end

      def item_claimed?(item)
        redis.zscore("out", item)
      end

      def item_claimant(item)
        if ip_downloader = redis.hget("claims", item)
          ip_downloader.split(" ")[1]
        end
      end

      def add_items(items, request_ip=nil)
        replies = redis.pipelined do
          items.each do |item|
            redis.sismember("todo", item)
            redis.sismember("done", item)
            redis.hexists("claims", item)
          end
        end

        to_add = []
        items.each_slice(3).each_with_index do |response, idx|
          if response==[0,0,0]
            to_add << item
          end
        end

        unless to_add.empty?
          redis.pipelined do
            to_add.each do |item|
              redis.sadd("todo", item)
            end
            if request_ip
              redis.rpush("add-log", "#{ request_ip } #{ to_add.join(",") }")
            end
          end
        end

        to_add
      end

      def request_item(request_ip, downloader)
        item = redis.spop("todo:d:#{ downloader }") || redis.spop("todo")

        if item.nil?
          item = redis.spop("todo:redo")
          if item and redis.hget("claims", item).to_s.split(" ").last==downloader
            redis.sadd("todo:redo", item)
            item = nil
          end
        end

        if item
          redis.pipelined do
            redis.zadd("out", Time.now.to_i, item)
            redis.hset("claims", item, "#{ request_ip } #{ downloader }")
          end
        end

        item
      end

      def release_item(item)
        if redis.zscore("out", item) or redis.hexists("claims", item)
          redis.pipelined do
            redis.sadd("todo", item)
            redis.zrem("out", item)
            redis.hdel("claims", item)
          end
          true
        else
          false
        end
      end

      def mark_item_done(downloader, item, bytes, done_hash)
        tries_left = 3

        resp = redis.pipelined do
          redis.sismember("done", item)
          redis.zrem("out", item)
          redis.srem("todo", item)

          redis.scard("done")
          redis.hget("downloader_bytes", downloader)
        end
        done_before = resp[0].to_i==1
        rem_from_out = resp[1].to_i==1
        rem_from_todo = resp[2].to_i==1
        done_count_cur = resp[3].to_i
        downloader_bytes_cur = (resp[4] || 0).to_i

        if rem_from_out or rem_from_todo or done_before
          total_bytes = 0
          bytes.values.each do |b| total_bytes += b.to_i end
          time_i = Time.now.utc.to_i

          msg = { "downloader"=>downloader,
                  "itemname"=>item,
                  "megabytes"=>(total_bytes.to_f / (1024*1024)),
                  "domain_bytes"=>bytes,
                  "version"=>done_hash["version"].to_s,
                  "log_channel"=>config.live_log_channel,
                  "is_duplicate"=>done_before }

          done_count_new = done_count_cur + 1
          downloader_bytes_new = downloader_bytes_cur + total_bytes.to_i

          redis.pipelined do
            redis.hdel("claims", item)
            redis.sadd("done", item)
            redis.rpush("log", JSON.dump(done_hash))
            redis.hset("downloader_version", downloader, done_hash["version"].to_s)
            
            unless done_before
              bytes.each do |domain, b|
                redis.hincrby("domain_bytes", domain, b.to_i)
              end
              redis.hincrby("downloader_bytes", downloader, total_bytes.to_i)
              redis.hincrby("downloader_count", downloader, 1)
              redis.rpush("downloader_chartdata:#{downloader}", "[#{ time_i },#{ downloader_bytes_new }]")
              if done_count_new % 10 == 0
                redis.rpush("items_done_chartdata", "[#{ time_i },#{ done_count_new }]")
              end
            end

            redis.publish(config.redis_pubsub_channel, JSON.dump(msg))
          end

          true
        else
          false
        end

      rescue Timeout::Error
        tries -= 1
        if tries > 0
          retry
        else
          raise $!
        end
      end
    end
  end
end

