require "sinatra"
require "time"
require "lib/array_systematic_sample"
require "lib/redis_connection"
require "lib/tracker"
require "lib/tracker_config"

module UniversalTracker
  class App < Sinatra::Base
    set :erb, :escape_html => true
    set :assets_version, File.mtime(__FILE__).to_i

    def tracker
      settings.tracker
    end

    def tracker_config
      settings.tracker.config
    end

    helpers do
      def tracker
        settings.tracker
      end

      def tracker_config
        settings.tracker.config
      end

      def assets_version
        settings.assets_version
      end

      def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Tracker admin")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        admin_password = tracker.admin_password
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)

        admin_password &&
        !admin_password.empty? &&
        @auth.provided? &&
        @auth.basic? &&
        @auth.credentials &&
        @auth.credentials == ['admin', admin_password]
      end
    end

    def process_done(request, data)
      downloader = data["downloader"]
      item = data["item"]
      bytes = data["bytes"]

      if downloader.is_a?(String) and
         item.is_a?(String) and
         bytes.is_a?(Hash) and
         bytes.all?{|k,v|k.is_a?(String) and v.is_a?(Fixnum)}

        done_hash = { "item"=>item,
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

        if bytes.keys.sort != tracker_config.domains.keys.sort
          p "Hey, strange data: #{ done_hash.inspect }"
          tracker.block_ip(request.ip, done_hash)
          tracker.release_item(item)
          "OK\n"
        else
          if tracker.mark_item_done(downloader, item, bytes, done_hash)
            "OK\n"
          else
            "Invalid item."
          end
        end
      else
        raise "Invalid input."
      end
    end

    def process_request(request, data)
      downloader = data["downloader"]

      if downloader.is_a?(String)
        if tracker.ip_blocked?(request.ip)
# TODO logging
#         p "Hey, blocked: #{ request.ip }"
          tracker.random_item
        else
          tracker.request_item(request.ip, downloader) or raise Sinatra::NotFound
        end
      else
        raise "Invalid input."
      end
    end


    not_found do
      ""
    end

    get "/" do
      erb :index
    end

    get "/stats.json" do
      stats = tracker.stats

      content_type :json
      expires 1, :public, :must_revalidate
      JSON.dump(stats)
    end

    get "/update-status.json" do
      data = tracker.downloader_update_status

      content_type :json
      expires 60, :public, :must_revalidate
      JSON.dump(data)
    end

    get "/rescue-me" do
      erb :rescue_me
    end

    post "/rescue-me" do
      items = params[:items].to_s.downcase.scan(tracker_config.valid_item_regexp_object).map do |match|
        match[0]
      end.uniq
      if items.size > 100
        "Too many items."
      else
        new_items = tracker.add_items(items)
        tracker.log_added_items(items, request.ip)

        erb :rescue_me_thanks, :locals=>{ :new_items=>new_items }
      end
    end

    get "/admin" do
      protected!
      @tracker = Tracker.new($redis)
      erb :admin_index
    end

    get "/admin/claims" do
      protected!
      @tracker = Tracker.new($redis)
      erb :admin_claims
    end

    get "/admin/config" do
      protected!
      @tracker_config = UniversalTracker::TrackerConfig.load_from(tracker.redis)
      erb :admin_config
    end

    post "/admin/config" do
      protected!
      @tracker_config = UniversalTracker::TrackerConfig.load_from(tracker.redis)
      UniversalTracker::TrackerConfig.config_fields.each do |field|
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

      @tracker_config.save_to(tracker.redis)
      erb :admin_config_thanks
    end

    post "/request" do
      process_request(request, JSON.parse(request.body.read))
    end

    post "/release" do
      content_type :text
      data = JSON.parse(request.body.read)
      if tracker.release_item(data["item"])
        "Released OK.\n"
      else
        "Invalid item.\n"
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

    get "/items/:item.json" do |item|
      content_type :json
      data = {
        :status=>tracker.item_status(item)
      }
      if data[:status]==:out
        data[:downloader] = tracker.item_claimant(item)
      end
      JSON.dump(data)
    end
  end
end

