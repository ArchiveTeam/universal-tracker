require "stringio"
require "zlib"

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
      headers["Content-Encoding"] = "gzip"

      gzip_cached("cache:#{ tracker.slug }:stats.json.gz") do
        JSON.dump(tracker.stats)
      end
    end

    get "/:slug/update-status.json" do
      content_type :json
      expires 60, :public, :must_revalidate
      headers["Content-Encoding"] = "gzip"

      gzip_cached("cache:#{ tracker.slug }:update-status.json.gz") do
        JSON.dump(tracker.downloader_update_status)
      end
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

    private

    def gzip_cached(cache_key)
      cached = redis.get(cache_key)
      if cached.nil?
        cached = StringIO.new.tap do |io|
          gz = Zlib::GzipWriter.new(io)
          begin
            gz.write(yield)
          ensure
            gz.close
          end
        end.string
        redis.set(cache_key, cached)
        redis.expire(cache_key, 60)
      end
      cached
    end
  end
end

