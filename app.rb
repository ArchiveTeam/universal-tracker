require "sinatra"
require "time"

module UniversalTracker
  class App < Sinatra::Base
    set :erb, :escape_html => true
    set :assets_version, File.mtime(__FILE__).to_i

    not_found do
      ""
    end
  end
end

require File.expand_path("../lib/init", __FILE__)
require File.expand_path("../models/init", __FILE__)
require File.expand_path("../helpers/init", __FILE__)
require File.expand_path("../routes/init", __FILE__)

