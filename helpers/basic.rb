module UniversalTracker
  class App < Sinatra::Base
    def redis
      settings.redis
    end

    def tracker_manager
      settings.tracker_manager
    end

    def tracker
      @tracker
    end

    def tracker_config
      tracker.config
    end

    def tracker_manager_config
      tracker_manager.config
    end

    helpers do
      def tracker
        @tracker
      end

      def tracker_config
        tracker.config
      end

      def tracker_manager_config
        tracker_manager.config
      end

      def assets_version
        settings.assets_version
      end
    end
  end
end

