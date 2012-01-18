require 'net/http'

class StatsController < ActionController::Base
  def index
  end

  def query
    p params # debug print
    http = Net::HTTP.new('api.logiceditor.com', 443)
    resp = http.post('/tq_reviews/data.json', params.to_json)
    render :text => resp.message
  end
end
