require 'lestats/routes_ext'

module Lestats
  class Engine < Rails::Engine
    initializer "static assets" do |app|
      app.middleware.use ::ActionDispatch::Static, "#{root}/public"
    end
  end
end
