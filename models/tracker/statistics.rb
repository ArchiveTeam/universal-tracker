require "time"
require "json"
require "active_support/ordered_hash"
require File.expand_path("../../../lib/array_systematic_sample", __FILE__)

module UniversalTracker
  class Tracker
    module Statistics
      def queues
        resp = redis.pipelined do
          redis.keys("#{ prefix }todo:d:*")
          redis.scard("#{ prefix }todo")
          redis.scard("#{ prefix }todo:secondary")
        end
        
        queues = []
        queues << { :key=>"todo",
                    :title=>"Main queue",
                    :length=>(resp[1].to_i + resp[2].to_i) }

        if resp[0].size > 0
          keys = resp[0].sort
          resp = redis.pipelined do
            keys.each do |queue|
              redis.scard(queue)
            end
          end.each_with_index do |length, index|
            if keys[index]=~/^#{ prefix }todo:d:(.+)$/
              queues << { :key=>keys[index][prefix.size, 10000],
                          :title=>"Queue for #{ $1 }",
                          :length=>length.to_i }
            end
          end
        end

        queues
      end

      def requests_per_minute_history
        minutes = redis.keys("#{ prefix }requests_processed:*")
        replies = redis.pipelined do
          minutes.each do |key|
            redis.get(key)
          end
        end
        minutes.zip(replies || []).map do |minute, requests|
          [ minute[/[0-9]+$/], requests ]
        end.sort_by do |minute, requests|
          minute.to_i
        end
      end

      def requests_granted_per_minute_history
        minutes = redis.keys("#{ prefix }requests_granted:*")
        replies = redis.pipelined do
          minutes.each do |key|
            redis.get(key)
          end
        end
        minutes.zip(replies || []).map do |minute, requests|
          [ minute[/[0-9]+$/], requests ]
        end.sort_by do |minute, requests|
          minute.to_i
        end
      end

      def number_of_claims
        redis.zcard("#{ prefix }out")
      end

      def claims_per_downloader(regexp=nil)
        claims = redis.hgetall("#{ prefix }claims")
        out = redis.zrange("#{ prefix }out", 0, -1, :with_scores=>true)
        claims_per_downloader = ActiveSupport::OrderedHash.new{ |h,k| h[k] = [] }

        out.each do |item, time|
          if claims[item]
            ip, downloader = claims[item].split(" ", 2)
          else
            ip, downloader = "unknown", "unknown"
          end
          if regexp.nil? or item=~regexp
            claims_per_downloader[downloader] << { :item=>item,
                                                   :ip=>ip,
                                                   :since=>Time.at(time.to_i).utc }
          end
        end
        claims_per_downloader
      end

      def done_per_downloader
        redis.hgetall("#{ prefix }downloader_count")
      end

      def budget_per_downloader
        redis.hgetall("#{ prefix }downloader_budget")
      end

      def downloader_update_status
        resp = redis.pipelined do
          redis.hgetall("#{ prefix }downloader_version")
          redis.get("#{ prefix }current_version")
          redis.get("#{ prefix }current_version_update_message")
        end
        data = {
          "downloader_version"=>Hash[*(resp[0] || [])],
          "current_version"=>resp[1],
          "current_version_update_message"=>resp[2]
        }
      end

      def process_chart_data(list)
        list_parsed = []
        if list
          list.scan(/([0-9]+)=([0-9a-zA-Z]+)/) do |t,v|
            list_parsed << [ Time.utc(t[0,4], t[4,2], t[6,2], t[8,2], t[10,2]).to_i, v.to_i(16) ]
          end
        end
        list_parsed
      end

      def charts
        # chart data
        resp = redis.pipelined do
          redis.hkeys("#{ prefix }downloader_bytes")     # 0
          redis.get("#{ prefix }chart:total_items")      # 1
          redis.get("#{ prefix }chart:total_bytes")      # 2
          redis.lrange("#{ prefix }chart:previous_chart_data_urls", 0, -1)   # 3
        end

        downloaders = resp[0]
        items_done_chart = process_chart_data(resp[1])
        bytes_done_chart = process_chart_data(resp[2])
        previous_chart_data_urls = resp[3]

        downloader_chart_fields = downloaders.map{|d|"#{ prefix }chart:downloader_bytes:#{ d }"}

        unless downloader_chart_fields.empty?
          resp = redis.pipelined do
            downloader_chart_fields.each do |fieldname|
              redis.get(fieldname)
            end
          end.map do |list|
            process_chart_data(list)
          end
          downloader_chart = Hash[downloaders.zip(resp)]
        else
          downloader_chart = {}
        end

        stats = {
          # chart data
          "downloader_chart"=>downloader_chart,
          "items_done_chart"=>items_done_chart,
          "bytes_done_chart"=>bytes_done_chart,
          "previous_chart_data_urls"=>previous_chart_data_urls
        }
      end

      def archive_charts
        downloaders = redis.hkeys("#{ prefix }downloader_bytes")
        downloader_chart_fields = downloaders.map{|d|"#{ prefix }chart:downloader_bytes:#{ d }"}

        redis.multi do
          redis.renamenx("#{ prefix }chart:total_items", "#{ prefix }chart:total_items:archive")
          redis.renamenx("#{ prefix }chart:total_bytes", "#{ prefix }chart:total_bytes:archive")
          downloader_chart_fields.each do |fieldname|
            redis.renamenx(fieldname, fieldname+":archive")
          end
        end

        timestamp = Time.now.utc.xmlschema

        # chart data
        resp = redis.pipelined do
          redis.get("#{ prefix }chart:total_items:archive")      # 0
          redis.get("#{ prefix }chart:total_bytes:archive")      # 1
        end

        items_done_chart = process_chart_data(resp[0])
        bytes_done_chart = process_chart_data(resp[1])

        downloader_chart_fields = downloaders.map{|d|"#{ prefix }chart:downloader_bytes:#{ d }:archive"}

        unless downloader_chart_fields.empty?
          resp = redis.pipelined do
            downloader_chart_fields.each do |fieldname|
              redis.get(fieldname)
            end
          end.map do |list|
            process_chart_data(list)
          end
          downloader_chart = Hash[downloaders.zip(resp)]
        else
          downloader_chart = {}
        end

        stats = {
          # chart data
          "downloader_chart"=>downloader_chart,
          "items_done_chart"=>items_done_chart,
          "bytes_done_chart"=>bytes_done_chart
        }

        archive_file = File.expand_path("../../../charts-archive/#{ prefix }#{ timestamp }.json", __FILE__)
        File.open(archive_file, "w") do |f|
          JSON.dump(stats, f)
        end
        system("gzip -c #{ archive_file } > #{ archive_file }.gz")

        redis.lpush("#{ prefix }chart:previous_chart_data_urls", "/charts-archive/#{ prefix }#{ timestamp }.json")

        redis.multi do
          redis.del("#{ prefix }chart:total_items", "#{ prefix }chart:total_items:archive")
          redis.del("#{ prefix }chart:total_bytes", "#{ prefix }chart:total_bytes:archive")
          downloader_chart_fields.each do |fieldname|
            redis.del(fieldname, fieldname+":archive")
          end
        end
      end

      def stats
        # simple statistics
        resp = redis.pipelined do
          redis.hgetall("#{ prefix }domain_bytes")       # 0
          redis.hgetall("#{ prefix }downloader_bytes")   # 1
          redis.hgetall("#{ prefix }downloader_count")   # 2
          redis.get("#{ prefix }done_counter")           # 3
          redis.scard("#{ prefix }todo")                 # 4
          redis.scard("#{ prefix }todo:secondary")       # 5
          redis.zcard("#{ prefix }out")                  # 6
        end

        domain_bytes = resp[0]
        downloader_bytes = resp[1]
        downloader_count = resp[2]
        total_items_done = resp[3].to_i
        total_items_todo = resp[4].to_i + resp[5].to_i
        total_items_out = resp[6].to_i
        total_items = total_items_done + total_items_todo + total_items_out

        total_bytes = 0
        domain_bytes.each do |d, bytes|
          total_bytes += bytes.to_i
        end

        downloaders = downloader_bytes.keys

        stats = {
          # simple stats
          "domain_bytes"=>Hash[domain_bytes.map{ |k,v| [k, v.to_i] }],
          "downloader_bytes"=>Hash[downloader_bytes.map{ |k,v| [k, v.to_i] }],
          "downloader_count"=>Hash[downloader_count.map{ |k,v| [k, v.to_i] }],
          "downloaders"=>downloader_count.keys,
          "total_items_done"=>total_items_done.to_i,
          "total_items"=>total_items.to_i,
          "counts"=>{ "todo"=>total_items_todo, "out"=>total_items_out, "done"=>total_items_done },
          "total_items_out"=>total_items_out.to_i,
          "total_bytes"=>total_bytes
        }
      end

      def log_length
        redis.llen("#{ prefix }log")
      end

      def logs
        log_keys = ["#{ prefix }log"] + redis.keys("#{ prefix }log:*")
        replies = redis.pipelined do
          log_keys.each do |log_key|
            redis.llen(log_key)
          end
        end
        Hash[log_keys.map{|key|key[prefix.size,1000]}.zip(replies)]
      end

      def archive_log
        redis.rename("#{ prefix }log", "#{ prefix }log:#{ Time.now.utc.xmlschema }")
      end

      def destroy_log(timestamp)
        redis.del("#{ prefix }log:#{ timestamp }")
      end

      def log_to_str(timestamp=nil)
        log_key = timestamp ? "#{ prefix }log:#{ timestamp }" : "#{ prefix }log"
        redis.lrange(log_key, 0, -1).join("\n")
      end
    end
  end
end

