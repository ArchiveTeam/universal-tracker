require "sinatra"
require "time"
require "cgi"

Encoding.default_external = 'UTF-8'

module UniversalTracker
  class App < Sinatra::Base
    set :erb, :escape_html => true
    set :assets_version, File.mtime(__FILE__).to_i

    not_found do
      if request.path =~ /^\/[a-z0-9-]+\/$/
        @error_not_found = true
        erb :root_not_found
      else
        ""
      end
    end
  end
end

require File.expand_path("../lib/init", __FILE__)
require File.expand_path("../models/init", __FILE__)
require File.expand_path("../helpers/init", __FILE__)
require File.expand_path("../routes/init", __FILE__)

