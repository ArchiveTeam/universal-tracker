module UniversalTracker
  class App < Sinatra::Base
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
    end
  end
end

