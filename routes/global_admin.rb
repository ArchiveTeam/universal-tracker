module UniversalTracker
  class App < Sinatra::Base
    before "/global-admin/*" do
      protected!
    end

    get "/global-admin" do
      redirect "/global-admin/"
    end

    get "/global-admin/" do
      @global_admin_page = "/global-admin/"
      erb :global_admin_index, :layout=>:admin_layout
    end

    get "/global-admin/config" do
      @global_admin_page = "/global-admin/config"
      erb :global_admin_config, :layout=>:admin_layout
    end

    post "/global-admin/config" do
      UniversalTracker::TrackerManagerConfig.config_fields.each do |field|
        case field[:type]
        when :string, :regexp
          tracker_manager.config[field[:name]] = params[field[:name]].strip if params[field[:name]]
        end
      end

      tracker_manager.config.save_to(redis)
      @global_admin_page = "/global-admin/config"
      erb :admin_config_thanks, :layout=>:admin_layout
    end

    get "/global-admin/trackers" do
      @global_admin_page = "/global-admin/trackers"
      erb :global_admin_trackers, :layout=>:admin_layout
    end

    post "/global-admin/trackers" do
      slug = params[:slug].downcase.delete("^a-z0-9-")
      tracker = tracker_manager.create_tracker(slug)
      tracker.admins = (params[:admin] || {}).values
      redirect "/global-admin/trackers"
    end

    post "/global-admin/trackers/:slug/update-admins" do |slug|
      tracker_manager.tracker_for_slug(slug).admins = (params[:admin] || {}).values
      redirect "/global-admin/trackers"
    end

    post "/global-admin/trackers/:slug/destroy" do |slug|
      if params[:confirm]
        tracker_manager.tracker_for_slug(slug).destroy
      end
      redirect "/global-admin/trackers"
    end

    get "/global-admin/users" do
      @global_admin_page = "/global-admin/users"
      erb :global_admin_users, :layout=>:admin_layout
    end

    post "/global-admin/users/update-admin" do
      if params[:admin]
        tracker_manager.add_admin(params[:username])
      else
        tracker_manager.remove_admin(params[:username])
      end
      redirect "/global-admin/users"
    end

    post "/global-admin/users/update-password" do
      username = params[:username].downcase.delete("^a-z0-9-")
      password = params[:password].strip
      tracker_manager.update_password(username, password)
      redirect "/global-admin/users"
    end

    post "/global-admin/users/destroy" do
      if params[:confirm]
        username = params[:username].downcase.delete("^a-z0-9-")
        tracker_manager.destroy_user(username)
      end
      redirect "/global-admin/users"
    end

    post "/global-admin/users" do
      username = params[:username].downcase.delete("^a-z0-9-")
      password = params[:password].strip
      tracker_manager.add_user(username, password)
      if params[:admin]
        tracker_manager.add_admin(params[:username])
      end
      redirect "/global-admin/users"
    end

    get "/global-admin/global-block-list" do
      erb :global_admin_block_list, :layout=>:admin_layout
    end
    
    post "/global-admin/global-block-list" do
      names = params[:names].to_s.scan(/\S+/)
      tracker_manager.config.set_downloader_global_blocked(redis, names)
      redirect "/global-admin/global-block-list"
    end
  end
end

