module UniversalTracker
  class App < Sinatra::Base
    get "/:slug" do |slug|
      redirect "/#{ slug }/"
    end

    get "/:slug/" do
      expires 60, :public, :must_revalidate
      erb :index
    end

    get "/:slug/stats.json" do
      content_type :json
      expires 60, :public, :must_revalidate

      cache_key = "cache:#{ tracker.slug }:stats.json"
      cached = redis.get(cache_key)
      if cached.nil?
        cached = JSON.dump(tracker.stats)
        redis.set(cache_key, cached)
        redis.expire(cache_key, 60)
      end
      cached
    end

    get "/:slug/update-status.json" do
      content_type :json
      expires 60, :public, :must_revalidate

      cache_key = "cache:#{ tracker.slug }:update-status.json"
      cached = redis.get(cache_key)
      if cached.nil?
        cached = JSON.dump(tracker.downloader_update_status)
        redis.set(cache_key, cached)
        redis.expire(cache_key, 60)
      end
      cached
    end

    get "/:slug/rescue-me" do
      erb :rescue_me
    end

    post "/:slug/rescue-me" do
      items = params[:items].to_s.downcase.scan(tracker_config.valid_item_regexp_object).map do |match|
        match[0]
      end.uniq
      new_items = tracker.add_items(items)
      tracker.log_added_items(items, request.ip)

      erb :rescue_me_thanks, :locals=>{ :new_items=>new_items }
    end
  end
end

