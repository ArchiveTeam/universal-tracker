require "time"
require "json"

module UniversalTracker
  class Tracker
    module Transactions
      def ip_block_log
        redis.lrange("blocked-log", 0, -1)
      end

      def add_log
        redis.lrange("add-log", 0, -1)
      end

      def log_added_items(items, request_ip)
        redis.rpush("add-log", "#{ request_ip } #{ items.join(",") }")
      end

      def block_ip(request_ip, invalid_done_hash=nil)
        redis.pipelined do
          redis.sadd("blocked", request_ip)
          redis.rpush("blocked-log", JSON.dump(invalid_done_hash)) if invalid_done_hash
        end
      end

      def ip_blocked?(request_ip)
        redis.sismember("blocked", request_ip)
      end

      def random_item
        redis.srandmember("todo")
      end

      def item_status(item)
        replies = redis.pipelined do
          redis.sismember("todo", item)
          redis.sismember("todo:secondary", item)
          redis.hexists("claims", item)
          redis.sismember("done", item)
        end
        if replies[0] == 1 or resp[1] == 1
          :todo
        elsif replies[2] == 1
          :out
        elsif replies[3] == 1
          :done
        else
          nil
        end
      end

      def item_known?(item)
        not item_status.nil?
      end

      def item_todo?(item)
        redis.sismember("todo", item) or redis.sismember("todo:secondary", item)
      end

      def item_done?(item)
        redis.sismember("done", item)
      end

      def item_claimed?(item)
        not redis.zscore("out", item).nil?
      end

      def item_claimant(item)
        if ip_downloader = redis.hget("claims", item)
          ip_downloader.split(" ")[1]
        end
      end

      def unknown_items(items)
        replies = redis.pipelined do
          items.each do |item|
            redis.sismember("todo", item)
            redis.sismember("todo:secondary", item)
            redis.hexists("claims", item)
            redis.sismember("done", item)
          end
        end

        to_add = []
        replies.each_slice(4).each_with_index do |response, idx|
          if response==[0,0,0,0]
            to_add << items[idx]
          end
        end
        to_add
      end

      # Add the items to the todo queue, after checking which items are
      # already in the queue, claimed or done.
      # Returns the items that have been added to the queue.
      def add_items(items)
        add_items!(unknown_items(items))
      end

      # Add the items to the todo queue, without checking if these
      # items are already claimed or done.
      def add_items!(items)
        add_items_to_queue!(:todo, items)
      end

      def add_items_to_queue!(queue, items)
        return [] if items.empty?

        added = []
        replies = redis.pipelined do
          items.each do |item|
            redis.sadd(queue, item)
          end
        end
        replies.each_with_index do |reply, idx|
          added << items[idx] if reply==1
        end
        added
      end
      private :add_items_to_queue!

      def add_items_for_redoing!(items)
        add_items_to_queue!("todo:redo", items)
      end

      def add_items_for_downloader!(downloader, items)
        add_items_to_queue!("todo:d:#{ downloader }", items)
      end

      def request_item(request_ip, downloader)
        item = redis.spop("todo:d:#{ downloader }") || redis.spop("todo") || redis.spop("todo:secondary")

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

      def release_items!(items)
        redis.pipelined do
          items.each do |item|
            redis.sadd("todo", item)
            redis.zrem("out", item)
            redis.hdel("claims", item)
          end
        end
      end
      private :release_items!

      def release_item(item)
        if redis.zscore("out", item) or redis.hexists("claims", item)
          release_items!([item])
          true
        else
          false
        end
      end

      def release_stale(time)
        out = redis.zrangebyscore("out", 0, time.to_i)
        release_items!(out)
        out
      end

      def release_by_downloader(downloader)
        out = claims_per_downloader[downloader].map { |claim| claim[:item] }
        release_items!(out)
        out
      end

      def mark_item_done(downloader, item, bytes, done_hash)
        if prev_status = item_status(item)
          total_bytes = 0
          bytes.values.each do |b| total_bytes += b.to_i end

          msg = { "downloader"=>downloader,
                  "item"=>item,
                  "megabytes"=>(total_bytes.to_f / (1024*1024)),
                  "domain_bytes"=>bytes,
                  "version"=>done_hash["version"].to_s,
                  "log_channel"=>config.live_log_channel,
                  "is_duplicate"=>(prev_status==:done) }

          redis.pipelined do
            redis.srem("todo", item)
            redis.srem("todo:secondary", item)
            redis.zrem("out", item)
            redis.hdel("claims", item)

            redis.sadd("done", item)
            redis.rpush("log", JSON.dump(done_hash))

            redis.hset("downloader_version", downloader, done_hash["version"].to_s)
            redis.publish(config.redis_pubsub_channel, JSON.dump(msg))
          end
          
          # we don't count items twice
          unless prev_status==:done
            update_stats_when_done(downloader, bytes)
          end

          true
        else
          false
        end
      end

      private

      # After an item has been marked done, this function should be called
      # to update the statistics.
      def update_stats_when_done(downloader, bytes)
        timestamp = Time.now.utc.to_i
        total_bytes = bytes.values.inject(0) { |sum,b| sum + b }

        resp = redis.pipelined do
          redis.hincrby("downloader_bytes", downloader, total_bytes)
          redis.hincrby("downloader_count", downloader, 1)
          redis.scard("done")

          bytes.each do |domain, b|
            redis.hincrby("domain_bytes", domain, b.to_i)
          end
        end

        downloader_bytes = resp[0]
        downloader_count = resp[1]
        done_count = resp[2]

        redis.pipelined do
          redis.rpush("downloader_chartdata:#{ downloader }", "[#{ timestamp },#{ downloader_bytes }]")
          if done_count % 10 == 0
            redis.rpush("items_done_chartdata", "[#{ timestamp },#{ done_count }]")
          end
        end
      end
    end
  end
end

