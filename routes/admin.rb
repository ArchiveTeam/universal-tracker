require "time"

module UniversalTracker
  class App < Sinatra::Base
    before "/:slug/admin/*" do
      protected!
    end

    get "/:slug/admin" do |slug|
      redirect "/#{ slug }/admin/"
    end

    get "/:slug/admin/" do
      @admin_page = "/admin/"
      erb :admin_index, :layout=>:admin_layout
    end

    get "/:slug/admin/queues" do
      @admin_page = "/admin/queues"
      erb :admin_queues, :layout=>:admin_layout
    end

    post "/:slug/admin/queues" do
      if request.content_type =~ /text\/plain/
        items_from_file = request.body.read
      elsif params["items-file"] and params["items-file"][:tempfile]
        items_from_file = params["items-file"][:tempfile].read
      else
        items_from_file = ""
      end
      items_from_form = params["items"].to_s
      items = items_from_file.scan(/\S+/) + items_from_form.scan(/\S+/)

      number_of_items = items.size

      if params[:check] == "yes"
        items = tracker.unknown_items(items)
      end

      if params[:queue] == "todo"
        added_items = tracker.add_items!(items)
        result = "Processed items: #{ number_of_items }, added to main queue: #{ added_items.size }"
      elsif not params[:downloader].to_s.strip.empty?
        downloader = params[:downloader].to_s.strip
        added_items = tracker.add_items_for_downloader!(downloader, items)
        result = "Processed items: #{ number_of_items }, added for #{ downloader }: #{ added_items.size }"
      else
        queue = nil
        result = "Invalid queue."
      end

      if request.content_type =~ /text\/plain/
        content_type :text
        result + "\n"
      else
        redirect "/#{ tracker.slug }/admin/queues?add_result=#{ CGI::escape(result) }"
      end
    end

    post "/:slug/admin/queues/destroy" do
      if params[:destroy_id] and params[:confirm]
        tracker.destroy_queue(params[:destroy_id])
      end
      redirect "/#{ tracker.slug }/admin/queues"
    end

    get "/:slug/admin/claims" do
      @admin_page = "/admin/claims"
      erb :admin_claims, :layout=>:admin_layout
    end

    post "/:slug/admin/claims/release" do
      regexp = params[:regexp] ? Regexp.new(params[:regexp]) : nil
      if params[:before]
        before = Time.xmlschema(params[:before])
        tracker.release_stale(before, regexp)
      elsif params[:hours]
        before = Time.now - params[:hours].to_i * 3600
        tracker.release_stale(before, regexp)
      elsif params[:downloader]
        tracker.release_by_downloader(params[:downloader], regexp)
      elsif params[:item]
        tracker.release_item(params[:item])
      end
      tracker.recalculate_budgets
      redirect "/#{ tracker.slug }/admin/claims"
    end

    post "/:slug/admin/recalculate_budgets" do
      tracker.recalculate_budgets
      redirect "/#{ tracker.slug }/admin/claims"
    end

    get "/:slug/admin/limits" do
      @admin_page = "/admin/limits"
      erb :admin_limits, :layout=>:admin_layout
    end

    post "/:slug/admin/limits" do
      if params[:requests_per_minute].to_s=~/[0-9]+/
        tracker.requests_per_minute = params[:requests_per_minute].strip.to_i
      else
        tracker.requests_per_minute = nil
      end
      if params[:max_budget].to_s=~/[0-9]+/
        tracker.min_downloader_budget = -(params[:max_budget].strip.to_i)
      else
        tracker.min_downloader_budget = nil
      end
      redirect "/#{ tracker.slug }/admin/limits"
    end

    get "/:slug/admin/blocked" do
      @admin_page = "/admin/blocked"
      erb :admin_blocked, :layout=>:admin_layout
    end

    post "/:slug/admin/blocked" do
      id = params[:id].to_s.strip
      tracker.block_downloader(id) unless id.empty?
      redirect "/#{ tracker.slug }/admin/blocked"
    end

    post "/:slug/admin/blocked/remove" do
      id = params[:id].to_s.strip
      tracker.unblock_downloader(id) unless id.empty?
      redirect "/#{ tracker.slug }/admin/blocked"
    end

    get "/:slug/admin/upload_targets" do
      @admin_page = "/admin/upload_targets"
      erb :admin_upload_targets, :layout=>:admin_layout
    end

    post "/:slug/admin/upload_targets" do
      url = params[:url].to_s.strip
      tracker.add_upload_target(url) unless url.empty?
      redirect "/#{ tracker.slug }/admin/upload_targets"
    end

    post "/:slug/admin/upload_targets/:action" do
      url = params[:url].to_s.strip

      unless url.empty?
        case params[:action]
        when "remove"
          tracker.remove_upload_target(url)
        when "activate"
          tracker.activate_upload_target(url)
        when "deactivate"
          tracker.deactivate_upload_target(url)
        end
      end

      redirect "/#{ tracker.slug }/admin/upload_targets"
    end

    post "/:slug/admin/upload_targets/remove" do
      url = params[:url].to_s.strip
      tracker.remove_upload_target(url) unless url.empty?
      redirect "/#{ tracker.slug }/admin/upload_targets"
    end

    get "/:slug/admin/logs" do
      @admin_page = "/admin/logs"
      erb :admin_logs, :layout=>:admin_layout
    end

    post "/:slug/admin/logs/archive" do
      if params[:destroy_id]
        tracker.destroy_log(params[:destroy_id]) if params[:confirm]
      else
        tracker.archive_log
      end
      redirect "/#{ tracker.slug }/admin/logs"
    end

    get "/:slug/admin/logs/:timestamp" do
      content_type "text/plain"
      attachment "log-#{ tracker.slug }-#{ params[:timestamp] }.log"
      tracker.log_to_str(params[:timestamp]=="current" ? nil : params[:timestamp])
    end

    get "/:slug/admin/config" do
      @admin_page = "/admin/config"
      erb :admin_config, :layout=>:admin_layout
    end

    post "/:slug/admin/config" do
      UniversalTracker::TrackerConfig.config_fields.each do |field|
        case field[:type]
        when :string, :regexp
          tracker.config[field[:name]] = params[field[:name]].strip if params[field[:name]]
        when :integer
          tracker.config[field[:name]] = params[field[:name]].strip.to_i if params[field[:name]]
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
            tracker.config[field[:name]] = new_map
          end
        end
      end

      tracker.config.save_to(tracker.redis)
      @admin_page = "/#{ tracker.slug }/admin/config"
      erb :admin_config_thanks, :layout=>:admin_layout
    end
  end
end

