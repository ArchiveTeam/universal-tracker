require "time"

class App < Sinatra::Base
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
        if bytes.keys.sort != settings.tracker["domains"].keys.sort
          p "Hey, strange data: #{ done_hash.inspect }"
          $redis.sadd("todo", user) if $redis.zrem("out", user)
          $redis.pipelined do
            $redis.sadd("blocked", request.ip)
            $redis.rpush("blocked_log", JSON.dump(done_hash))
            $redis.hdel("claims", user)
          end
          "OK\n"
        else
          done_before = $redis.sismember("done", user)
          if $redis.zrem("out", user) or $redis.srem("todo", user) or done_before
            total_bytes = 0
            bytes.values.each do |b| total_bytes += b.to_i end
            bytes_str = "[#{ Time.now.utc.to_i }000,#{ total_bytes }],"

            msg = { "downloader"=>downloader,
                    "username"=>user,
                    "megabytes"=>(total_bytes.to_f / (1024*1024)),
                    "domain_bytes"=>bytes,
                    "version"=>done_hash["version"].to_s,
                    "log_channel"=>settings.tracker["log_channel"] }

            $redis.pipelined do
              $redis.hdel("claims", user)
              $redis.sadd("done", user)
              $redis.rpush("log", JSON.dump(done_hash))
              
              unless done_before
                bytes.each do |domain, b|
                  $redis.hincrby("domain_bytes", domain, b.to_i)
                end
                $redis.hincrby("downloader_bytes", downloader, total_bytes.to_i)
                $redis.hincrby("downloader_count", downloader, 1)
                $redis.append("downloader_chart:#{downloader}", bytes_str)
              end

              $redis.publish(settings.tracker["redis_pubsub_channel"], JSON.dump(msg))
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
        username = $redis.spop("todo")

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
    erb :index, :locals=>{ :version=>File.mtime("./app.rb").to_i,
                           :tracker=>settings.tracker }
  end

  get "/stats.json" do
    resp = $redis.pipelined do
      $redis.hgetall("domain_bytes")
      $redis.hgetall("downloader_bytes")
      $redis.hgetall("downloader_count")
      $redis.scard("done")
      $redis.scard("todo")
    end

    domain_bytes = Hash[*resp[0]]
    downloader_bytes = Hash[*resp[1]]
    downloader_count = Hash[*resp[2]]
    total_users_done = resp[3]
    total_users = resp[3].to_i + resp[4].to_i

    downloaders = downloader_bytes.keys
    downloader_fields = downloaders.map{|d|"downloader_chart:#{ d }"}

    unless downloader_fields.empty?
      resp = $redis.mget(*downloader_fields)
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
      "downloader_chart"=>Hash[downloader_chart.map do |k,v|
        total = 0
        [k,
         JSON.parse("["+v.gsub(/^,|,$/,"")+"]").map do |a|
           [a[0], (total += a[1]).to_f/(1024*1024*1024)]
         end]
      end],
      "downloaders"=>downloader_count.keys,
      "total_users_done"=>total_users_done.to_i,
      "total_users"=>total_users.to_i,
      "total_bytes"=>total_bytes
    }

    content_type :json
    expires 1, :public, :must_revalidate
    JSON.dump(stats)
  end

  get "/rescue-me" do
    erb :rescue_me, :locals=>{ :version=>File.mtime("./app.rb").to_i,
                               :tracker=>settings.tracker }
  end

  post "/rescue-me" do
    usernames = params[:usernames].to_s.downcase.scan(Regexp.new(settings.tracker["valid_usernames"])).map do |match|
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
                                        :tracker=>settings.tracker,
                                        :new_usernames=>to_add }
    end
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

