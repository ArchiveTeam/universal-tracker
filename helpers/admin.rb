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
        users = tracker_manager.users_with_password
        global_admins = tracker_manager.admins

        return true if global_admins.empty?

        @auth ||= Rack::Auth::Basic::Request.new(request.env)
        return false unless @auth.provided? && @auth.basic? && @auth.credentials

        username, password = @auth.credentials
        username = username.downcase.strip
        password = password.strip

        return false unless users[username] && users[username] == password

        if global_admins.include?(username)
          @user_is_global_admin = true
          return true
        else
          @user_is_global_admin = false
        end

        return true if tracker && tracker.admins.include?(username)

        return false
      end

      def user_is_global_admin?
        @user_is_global_admin
      end
    end
  end
end

