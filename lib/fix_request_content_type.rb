class FixRequestContentType
  def initialize(app, options = {})
    @app = app
    @options = options
  end

  def call(env)
    if (@options[:urls] || []).any? { |url| url == env["PATH_INFO"] }
      env["CONTENT_TYPE"] = @options[:content_type]
    end

    @app.call(env)
  end
end

