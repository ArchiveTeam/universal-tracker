module UniversalTracker
  class App < Sinatra::Base
    before "/:the_slug/*" do
      if params[:the_slug] == "global-admin"
        @tracker = nil
      else
        # TODO
        @tracker = tracker_manager.tracker_for_slug(params[:the_slug])
        raise Sinatra::NotFound if @tracker.nil?
      end
    end

    get "/" do
      erb :root_not_found
    end
  end
end

