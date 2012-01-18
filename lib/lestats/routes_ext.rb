module ActionDispatch::Routing
  class Mapper
    def db_stats_routes
      get "/dbstats" => "stats#index"
      post "/dbstats" => "stats#query"
    end
  end
end
