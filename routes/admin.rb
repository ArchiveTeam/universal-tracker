require "time"

module UniversalTracker
  class App < Sinatra::Base
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

    post "/admin/claims/release" do
      protected!
      @tracker = Tracker.new($redis)
      if params[:before]
        before = Time.xmlschema(params[:before])
        @tracker.release_stale(before)
      elsif params[:downloader]
        @tracker.release_by_downloader(params[:downloader])
      elsif params[:item]
        @tracker.release_item(params[:item])
      end
      redirect "/admin/claims"
    end

    get "/admin/limits" do
      protected!
      @tracker = Tracker.new($redis)
      erb :admin_limits
    end

    post "/admin/limits" do
      protected!
      @tracker = Tracker.new($redis)
      if params[:requests_per_minute].to_s=~/[0-9]+/
        @tracker.requests_per_minute = params[:requests_per_minute].strip.to_i
      else
        @tracker.requests_per_minute = nil
      end
      redirect "/admin/limits"
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
  end
end

