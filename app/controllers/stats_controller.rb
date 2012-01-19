require 'net/http'

class StatsController < ActionController::Base
  def index
  end

  def query
    http = Net::HTTP.new('api.logiceditor.com', 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    r = Net::HTTP::Post.new('/tq_reviews/data.json')
    r.body = params.to_json
    r["Content-Type"] = "application/json"
    a = http.request(r)
    #Review.find_by_sql()
    render :json => a.body
  end
end
