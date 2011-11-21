require "sinatra"
require "time"
require "lib/array_systematic_sample"
require "lib/tracker"
require "lib/tracker_config"

module UniversalTracker
  class App < Sinatra::Base
    set :erb, :escape_html => true

    helpers do
      def tracker_config
        settings.tracker_config
      end

      def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Tracker admin")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        admin_password = $redis.get("admin_password")
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['admin', admin_password] && admin_password && !admin_password.empty?
      end
    end

    def process_done(request, data)
      downloader = data["downloader"]
      user = data["user"]
      bytes = data["bytes"]

      if downloader.is_a?(String) and
         user.is_a?(String) and
         bytes.is_a?(Hash) and
         bytes.all?{|k,v|k.is_a?(String) and v.is_a?(Fixnum)}

        done_hash = { "user"=>user,
                      "by"=>downloader,
                      "ip"=>request.ip,
                      "at"=>Time.now.utc.xmlschema,
                      "bytes"=>bytes }
        if data["version"].is_a?(String)
          done_hash["version"] = data["version"]
        end
        if data["id"].is_a?(String)
          done_hash["id"] = data["id"]
        end

        tries = 3
        begin
          if bytes.keys.sort != settings.tracker_config.domains.keys.sort
            p "Hey, strange data: #{ done_hash.inspect }"
            $redis.sadd("todo", user) if $redis.zrem("out", user)
            $redis.pipelined do
              $redis.sadd("blocked", request.ip)
              $redis.rpush("blocked_log", JSON.dump(done_hash))
              $redis.hdel("claims", user)
            end
            "OK\n"
          else
            resp = $redis.pipelined do
              $redis.sismember("done", user)
              $redis.zrem("out", user)
              $redis.srem("todo", user)

              $redis.scard("done")
              $redis.hget("downloader_bytes", downloader)
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
                      "username"=>user,
                      "megabytes"=>(total_bytes.to_f / (1024*1024)),
                      "domain_bytes"=>bytes,
                      "version"=>done_hash["version"].to_s,
                      "log_channel"=>settings.tracker_config.live_log_channel,
                      "is_duplicate"=>done_before }

              done_count_new = done_count_cur + 1
              downloader_bytes_new = downloader_bytes_cur + total_bytes.to_i

              $redis.pipelined do
                $redis.hdel("claims", user)
                $redis.sadd("done", user)
                $redis.rpush("log", JSON.dump(done_hash))
                $redis.hset("downloader_version", downloader, done_hash["version"].to_s)
                
                unless done_before
                  bytes.each do |domain, b|
                    $redis.hincrby("domain_bytes", domain, b.to_i)
                  end
                  $redis.hincrby("downloader_bytes", downloader, total_bytes.to_i)
                  $redis.hincrby("downloader_count", downloader, 1)
                  $redis.rpush("downloader_chartdata:#{downloader}", "[#{ time_i },#{ downloader_bytes_new }]")
                  if done_count_new % 10 == 0
                    $redis.rpush("users_done_chartdata", "[#{ time_i },#{ done_count_new }]")
                  end
                end

                $redis.publish(settings.tracker_config.redis_pubsub_channel, JSON.dump(msg))
              end

              "OK\n"
            else
              "Invalid user."
            end
          end
        rescue Timeout::Error
          tries -= 1
          retry if tries > 0
        end
      else
        raise "Invalid input."
      end
    end

    def process_request(request, data)
      downloader = data["downloader"]

      if downloader.is_a?(String)
        if $redis.sismember("blocked", request.ip)
          p "Hey, blocked: #{ request.ip }"
          $redis.srandmember("todo")
        else
          username = $redis.spop("todo:d:#{ downloader }") || $redis.spop("todo")

          if username.nil?
            username = $redis.spop("todo:redo")
            if username and $redis.hget("claims", username).to_s.split(" ").last==downloader
              $redis.sadd("todo:redo", username)
              username = nil
            end
          end

          if username
            $redis.pipelined do
              $redis.zadd("out", Time.now.to_i, username)
              $redis.hset("claims", username, "#{ request.ip } #{ downloader }")
            end
            username
          else
            raise Sinatra::NotFound
          end
        end
      else
        raise "Invalid input."
      end
    end


    not_found do
      ""
    end

    get "/" do
      erb :index,
          :locals=>{ :version=>File.mtime("./app.rb").to_i }
    end

    get "/stats.json" do
      resp = $redis.pipelined do
        $redis.hgetall("domain_bytes")
        $redis.hgetall("downloader_bytes")
        $redis.hgetall("downloader_count")
        $redis.scard("done")
        $redis.scard("todo")
        $redis.lrange("users_done_chartdata", 0, -1)
      end

      domain_bytes = Hash[*resp[0]]
      downloader_bytes = Hash[*resp[1]]
      downloader_count = Hash[*resp[2]]
      total_users_done = resp[3]
      total_users = resp[3].to_i + resp[4].to_i
      users_done_chart = (resp[5] || []).systematic_sample(settings.tracker_config.history_length).map do |item|
        JSON.parse(item)
      end

      downloaders = downloader_bytes.keys
      downloader_fields = downloaders.map{|d|"downloader_chartdata:#{ d }"}

      unless downloader_fields.empty?
        resp = $redis.pipelined do
          downloader_fields.each do |fieldname|
            $redis.lrange(fieldname, 0, -1)
          end
        end.map do |list|
          (list || []).systematic_sample(settings.tracker_config.history_length).map do |item|
            JSON.parse(item)
          end
        end
        downloader_chart = Hash[downloaders.zip(resp)]
      else
        downloader_chart = {}
      end

      total_bytes = 0
      domain_bytes.each do |d, bytes|
        total_bytes += bytes.to_i
      end

      stats = {
        "domain_bytes"=>Hash[domain_bytes.map{ |k,v| [k, v.to_i] }],
        "downloader_bytes"=>Hash[downloader_bytes.map{ |k,v| [k, v.to_i] }],
        "downloader_count"=>Hash[downloader_count.map{ |k,v| [k, v.to_i] }],
        "downloader_chart"=>downloader_chart,
        "users_done_chart"=>users_done_chart,
        "downloaders"=>downloader_count.keys,
        "total_users_done"=>total_users_done.to_i,
        "total_users"=>total_users.to_i,
        "total_bytes"=>total_bytes
      }

      content_type :json
      expires 1, :public, :must_revalidate
      JSON.dump(stats)
    end

    get "/update-status.json" do
      resp = $redis.pipelined do
        $redis.hgetall("downloader_version")
        $redis.get("current_version")
        $redis.get("current_version_update_message")
      end
      data = {
        "downloader_version"=>Hash[*(resp[0] || [])],
        "current_version"=>resp[1],
        "current_version_update_message"=>resp[2]
      }

      content_type :json
      expires 60, :public, :must_revalidate
      JSON.dump(data)
    end

    get "/rescue-me" do
      erb :rescue_me,
          :locals=>{ :version=>File.mtime("./app.rb").to_i }
    end

    post "/rescue-me" do
      usernames = params[:usernames].to_s.downcase.scan(settings.tracker_config.valid_username_regexp_object).map do |match|
        match[0]
      end.uniq
      if usernames.size > 100
        "Too many usernames."
      else
        new_usernames = 0

        replies = $redis.pipelined do
          usernames.each do |username|
            $redis.sismember("todo", username)
            $redis.sismember("done", username)
            $redis.hexists("claims", username)
          end
        end

        to_add = []
        usernames.each_with_index do |username, idx|
          if replies[idx*3, 3]==[0,0,0]
            to_add << username
          end
        end

        unless to_add.empty?
          $redis.pipelined do
            to_add.each do |username|
              $redis.sadd("todo", username)
            end
            $redis.rpush("add-log", "#{ request.ip } #{ to_add.join(",") }")
          end
        end

        erb :rescue_me_thanks, :locals=>{ :version=>File.mtime("./app.rb").to_i,
                                          :new_usernames=>to_add }
      end
    end

    get "/admin" do
      protected!
      @tracker = Tracker.new
      erb :admin_index,
          :locals=>{ :version=>File.mtime("./app.rb").to_i,
                     :request=>request }
    end

    get "/admin/claims" do
      protected!
      @tracker = Tracker.new
      erb :admin_claims,
          :locals=>{ :version=>File.mtime("./app.rb").to_i,
                     :request=>request }
    end

    get "/admin/config" do
      protected!
      @tracker = Tracker.new
      @tracker_config = TrackerConfig.load_from_redis
      erb :admin_config,
          :locals=>{ :version=>File.mtime("./app.rb").to_i,
                     :request=>request }
    end

    post "/admin/config" do
      protected!
      @tracker = Tracker.new
      @tracker_config = TrackerConfig.load_from_redis
      TrackerConfig.config_fields.each do |field|
        case field[:type]
        when :string, :regexp
          @tracker_config[field[:name]] = params[field[:name]].strip if params[field[:name]]
        when :integer
          @tracker_config[field[:name]] = params[field[:name]].strip.to_i if params[field[:name]]
        when :map
          if params["#{ field[:name] }-0-key"]
            i = 0
            new_map = {}
            while params["#{ field[:name] }-#{ i }-key"]
              if not params["#{ field[:name] }-#{ i }-key"].strip.empty? and not params["#{ field[:name ]}-#{ i }-value"].strip.empty?
                new_map[params["#{ field[:name] }-#{ i }-key"].strip] = params["#{ field[:name ]}-#{ i }-value"].strip
              end
              i += 1
            end
            @tracker_config[field[:name]] = new_map
          end
        end
      end

      @tracker_config.save_to_redis
      erb :admin_config_thanks,
          :locals=>{ :version=>File.mtime("./app.rb").to_i,
                     :request=>request }
    end

    post "/request" do
      process_request(request, JSON.parse(request.body.read))
    end

    post "/release" do
      content_type :text
      data = JSON.parse(request.body.read)
      user = data["user"]
      if $redis.zscore("out", user) or $redis.hexists("claims", user)
        $redis.pipelined do
          $redis.sadd("todo", user)
          $redis.zrem("out", user)
          $redis.hdel("claims", user)
        end
        "Released OK.\n"
      else
        "Invalid user.\n"
      end
    end

    post "/done" do
      content_type :text
      process_done(request, JSON.parse(request.body.read))
    end

    post "/done+request" do
      content_type :text
      data = JSON.parse(request.body.read)
      process_done(request, data)
      process_request(request, data)
    end
  end
end

