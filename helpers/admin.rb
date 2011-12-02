module UniversalTracker
  class App < Sinatra::Base
    helpers do
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
  end
end

