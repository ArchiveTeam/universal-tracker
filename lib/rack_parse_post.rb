module Rack
  class Request
    alias POST_without_rescue POST
    def POST
      POST_without_rescue rescue {}
    end
  end
end

