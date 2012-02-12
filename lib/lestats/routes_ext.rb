module ActionDispatch::Routing
  class Mapper
    def db_stats_routes
      get "/dbstats" => "stats#index"
      post "/dbstats/reviews" => "stats#reviews", :as => :reviews_query
      post "/dbstats/users" => "stats#users", :as => :users_query
    end
  end
end
