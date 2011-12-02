require "sinatra"
require "time"
require "extensions/kernel"

module UniversalTracker
  class App < Sinatra::Base
    set :erb, :escape_html => true
    set :assets_version, File.mtime(__FILE__).to_i

    not_found do
      ""
    end
  end
end

require_relative "lib/init"
require_relative "models/init"
require_relative "helpers/init"
require_relative "routes/init"

