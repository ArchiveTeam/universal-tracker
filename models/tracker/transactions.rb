require "time"
require "json"

module UniversalTracker
  class Tracker
    module Transactions
      def ip_block_log
        redis.lrange("#{ prefix }blocked-log", 0, -1)
      end

      def add_log
        redis.lrange("#{ prefix }add-log", 0, -1)
      end

      def log_added_items(items, request_ip)
        redis.rpush("#{ prefix }add-log", "#{ request_ip } #{ items.join(",") }")
      end

      def log_upload(request_ip, uploader, item, server)
        uploaded_hash = { "uploader"=>uploader,
                          "user"=>item,
                          "server"=>server,
                          "ip"=>request_ip,
                          "at"=>Time.now.utc.xmlschema }

        tries = 10
        begin
          log_key = "#{ prefix }upload_log_#{ server }"
          redis.rpush(log_key, JSON.dump(uploaded_hash))
          true
        rescue Timeout::Error
          tries -= 1
          if tries > 0
            retry
          else
            raise Timeout::Error
          end
        end
      end

      def block_ip(request_ip, invalid_done_hash=nil)
        redis.pipelined do
          redis.sadd("#{ prefix }blocked", request_ip)
          redis.rpush("#{ prefix }blocked-log", JSON.dump(invalid_done_hash)) if invalid_done_hash
        end
      end

      def block_downloader(downloader)
        redis.sadd("#{ prefix }blocked", downloader)
      end

      def unblock_downloader(downloader)
        redis.srem("#{ prefix }blocked", downloader)
      end

      def ip_blocked?(request_ip)
        redis.sismember("#{ prefix }blocked", request_ip)
      end

      def downloader_blocked?(downloader)
        redis.sismember("#{ prefix }blocked", downloader)
      end

      def blocked?(keys)
        redis.pipelined do
          keys.each do |key|
            redis.sismember("#{ prefix }blocked", key)
          end
        end.any?{|r|r.to_i==1}
      end

      def blocked
        redis.smembers("#{ prefix }blocked")
      end

      def requests_per_minute_monitor
        redis.get("#{ prefix }requests_per_minute:monitor")
      end

      def requests_per_minute
        redis.get("#{ prefix }requests_per_minute")
      end

      def requests_per_minute=(r)
        if r.nil?
          redis.del("#{ prefix }requests_per_minute")
        else
          redis.set("#{ prefix }requests_per_minute", r)
        end
      end

      def min_downloader_budget
        redis.get("#{ prefix }min_downloader_budget")
      end

      def min_downloader_budget=(r)
        if r.nil?
          redis.del("#{ prefix }min_downloader_budget")
        else
          redis.set("#{ prefix }min_downloader_budget", r)
        end
      end

      def check_version(version)
        if config.min_script_version.to_s.strip.empty?
          true
        elsif version.nil?
          false
        else
          version.to_s.strip >= config.min_script_version.to_s.strip
        end
      end

      def check_request_rate
        key = "#{ prefix }requests_processed:" + Time.now.strftime("%M")
        replies = redis.pipelined do
          redis.get("#{ prefix }requests_per_minute")
          redis.get("#{ prefix }requests_per_minute:monitor")
          redis.incr(key)
          redis.expire(key, 300)
        end
        limit = nil
        if replies[0] and replies[1]
          limit = [ replies[0].to_i, replies[1].to_i ].min
        elsif replies[0]
          limit = replies[0].to_i
        elsif replies[1]
          limit = replies[1].to_i
        else
          return true
        end
        limit >= replies[2].to_i
      end

      def check_not_blocked_and_request_rate_ok(request_ip, downloader)
        key = "#{ prefix }requests_processed:" + Time.now.strftime("%M")
        replies = redis.pipelined do
          redis.sismember("#{ prefix }blocked", request_ip)
          redis.sismember("#{ prefix }blocked", downloader)

          redis.hget("#{ prefix }downloader_budget", downloader)
          redis.get("#{ prefix }min_downloader_budget")

          redis.get("#{ prefix }requests_per_minute")
          redis.get("#{ prefix }requests_per_minute:monitor")
          redis.incr(key)
          redis.expire(key, 300)
        end
        limit = nil
        if replies[4] and replies[5]
          limit = [ replies[4].to_i, replies[5].to_i ].min
        elsif replies[4]
          limit = replies[4].to_i
        elsif replies[5]
          limit = replies[5].to_i
        end
        if replies[0] == 1 or replies[1] == 1
          redis.decr(key)
          :blocked
        elsif replies[2] and replies[3] and replies[2].to_i < replies[3].to_i
          :blocked
        elsif limit and limit.to_i < replies[6].to_i
          :rate_limit
        else
          :ok
        end
      end

      def random_upload_target
        redis.srandmember("#{ prefix }upload_target")
      end

      def upload_targets
        redis.smembers("#{ prefix }upload_target") || []
      end

      def add_upload_target(url)
        activate_upload_target(url) or redis.sadd("#{ prefix }upload_target", url)
      end

      def remove_upload_target(url)
        redis.srem("#{ prefix }upload_target", url)
        redis.srem("#{ prefix }inactive_upload_target", url)
      end

      def inactive_upload_targets
        redis.smembers("#{ prefix }inactive_upload_target") || []
      end

      def activate_upload_target(url)
        redis.smove("#{ prefix }inactive_upload_target", "#{ prefix }upload_target", url)
      end

      def deactivate_upload_target(url)
        redis.smove("#{ prefix }upload_target", "#{ prefix }inactive_upload_target", url)
      end

      def random_item
        redis.srandmember("#{ prefix }todo")
      end

      def item_status(item)
        replies = redis.pipelined do
          redis.sismember("#{ prefix }todo", item)
          redis.sismember("#{ prefix }todo:secondary", item)
          redis.hexists("#{ prefix }claims", item)
          redis.sismember("#{ prefix }done", item)
        end
        if replies[0] == 1 or replies[1] == 1
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
        redis.sismember("#{ prefix }todo", item) or redis.sismember("#{ prefix }todo:secondary", item)
      end

      def item_done?(item)
        redis.sismember("#{ prefix }done", item)
      end

      def item_claimed?(item)
        not redis.zscore("#{ prefix }out", item).nil?
      end

      def item_claimant(item)
        if ip_downloader = redis.hget("#{ prefix }claims", item)
          ip_downloader.split(" ")[1]
        end
      end

      def unknown_items(items)
        replies = redis.pipelined do
          items.each do |item|
            redis.sismember("#{ prefix }todo", item)
            redis.sismember("#{ prefix }todo:secondary", item)
            redis.hexists("#{ prefix }claims", item)
            redis.sismember("#{ prefix }done", item)
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
        queue_key = "#{ prefix }#{ queue }"
        replies = redis.pipelined do
          items.each do |item|
            redis.sadd(queue_key, item)
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

      def destroy_queue(queue)
        redis.del("#{ prefix }#{ queue }") if queue=~/^todo/
      end

      def request_item(request_ip, downloader)
        replies = redis.pipelined do
          redis.spop("#{ prefix }todo:d:#{ downloader }")
          redis.spop("#{ prefix }todo")
        end

        downloader_item = replies[0]
        todo_item = replies[1]
        item = downloader_item || todo_item
        
        if item.nil?
          item = redis.spop("#{ prefix }todo:secondary")
        end

        if item.nil?
          item = redis.spop("#{ prefix }todo:redo")
          if item and redis.hget("#{ prefix }claims", item).to_s.split(" ").last==downloader
            redis.sadd("#{ prefix }todo:redo", item)
            item = nil
          end
        end

        if item
          redis.pipelined do
            redis.sadd("#{ prefix }todo", todo_item) if downloader_item and todo_item
            redis.zadd("#{ prefix }out", Time.now.to_i, item)
            redis.hset("#{ prefix }claims", item, "#{ request_ip } #{ downloader }")
            redis.hincrby("#{ prefix }downloader_budget", downloader, -1)
          end
        end

        item
      end

      def release_items!(items)
        redis.pipelined do
          items.each do |item|
            redis.sadd("#{ prefix }todo", item)
            redis.zrem("#{ prefix }out", item)
            redis.hdel("#{ prefix }claims", item)
          end
        end
      end
      private :release_items!

      def release_item(item)
        if redis.zscore("#{ prefix }out", item) or redis.hexists("#{ prefix }claims", item)
          release_items!([item])
          true
        else
          false
        end
      end

      def release_stale(time, regexp=nil)
        out = redis.zrangebyscore("#{ prefix }out", 0, time.to_i)
        if regexp
          out = out.select do |item|
            item=~regexp
          end
        end
        release_items!(out)
        out
      end

      def release_by_downloader(downloader, regexp=nil)
        out = claims_per_downloader[downloader].map { |claim| claim[:item] }
        if regexp
          out = out.select do |item|
            item=~regexp
          end
        end
        release_items!(out)
        redis.hdel("#{ prefix }downloader_budget", downloader)
        out
      end

      def mark_item_done(downloader, item, bytes, done_hash)
        if prev_status = item_status(item)
          total_bytes = 0
          bytes.values.each do |b| total_bytes += b.to_i end

          msg = { "downloader"=>downloader,
                  "user_agent"=>done_hash["ua"].to_s,
                  "item"=>item,
                  "megabytes"=>(total_bytes.to_f / (1024*1024)),
                  "domain_bytes"=>bytes,
                  "version"=>done_hash["version"].to_s,
                  "log_channel"=>config.live_log_channel,
                  "is_duplicate"=>(prev_status==:done) }

          redis.pipelined do
            redis.srem("#{ prefix }todo", item)
            redis.srem("#{ prefix }todo:secondary", item)
            redis.zrem("#{ prefix }out", item)
            redis.hdel("#{ prefix }claims", item)
            redis.hincrby("#{ prefix }downloader_budget", downloader, 1)

            redis.sadd("#{ prefix }done", item)
            redis.rpush("#{ prefix }log", JSON.dump(done_hash))

            redis.hset("#{ prefix }downloader_version", downloader, done_hash["version"].to_s)

            redis.incr("#{ prefix }done_counter") unless prev_status==:done
          end

          counts = redis.pipelined do
            redis.scard("#{ prefix }todo")
            redis.zcard("#{ prefix }out")
            redis.get("#{ prefix }done_counter")
          end

          msg["counts"] = { "todo"=>counts[0].to_i, "out"=>counts[1].to_i, "done"=>counts[2].to_i }

          redis.publish(tracker_manager.config.redis_pubsub_channel, JSON.dump(msg))
          
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
        minute = Time.now.utc.strftime("%Y%m%d%H%M")
        sum_bytes = bytes.values.inject(0) { |sum,b| sum + b }

        resp = redis.pipelined do
          redis.hincrby("#{ prefix }downloader_bytes", downloader, sum_bytes)
          redis.hincrby("#{ prefix }downloader_count", downloader, 1)
          redis.get("#{ prefix }done_counter")

          bytes.each do |domain, b|
            redis.hincrby("#{ prefix }domain_bytes", domain, b.to_i)
          end
        end

        downloader_bytes = resp[0]
        downloader_count = resp[1]
        done_count = resp[2].to_i
        total_bytes = resp[3..100].inject(0) { |sum,b| sum + b.to_i }

        redis.eval(%{
            local prev_timestamp = nil
            local entry = nil

            -- downloader bytes chart
            prev_timestamp = redis.call('HGET', KEYS[1], ARGV[1]) or -1
            if tonumber(prev_timestamp) < tonumber(ARGV[2]) then
              entry = string.format('%s=%s ', ARGV[2], ARGV[3])
              redis.call('APPEND', KEYS[2], entry)
              redis.call('HSET', KEYS[1], ARGV[1], ARGV[2])
            end

            -- total items chart
            prev_timestamp = redis.call('HGET', KEYS[1], 'total items') or -1
            if tonumber(prev_timestamp) < tonumber(ARGV[2]) then
              entry = string.format('%s=%s ', ARGV[2], ARGV[4])
              redis.call('APPEND', KEYS[3], entry)
              redis.call('HSET', KEYS[1], 'total items', ARGV[2])
            end

            -- total bytes chart
            prev_timestamp = redis.call('HGET', KEYS[1], 'total bytes') or -1
            if tonumber(prev_timestamp) < tonumber(ARGV[2]) then
              entry = string.format('%s=%s ', ARGV[2], ARGV[5])
              redis.call('APPEND', KEYS[4], entry)
              redis.call('HSET', KEYS[1], 'total bytes', ARGV[2])
            end
          }, 4,
          "#{ prefix }chart:previous_timestamp",
          "#{ prefix }chart:downloader_bytes:#{ downloader }",
          "#{ prefix }chart:total_items",
          "#{ prefix }chart:total_bytes",
          downloader, minute,
          "%013x" % downloader_bytes,
          "%08x" % done_count,
          "%013x" % total_bytes)
      end
    end
  end
end

