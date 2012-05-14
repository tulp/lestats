require 'net/http'

class StatsController < ActionController::Base
  def index
  end

  def reviews
    fields, values = do_request('/t_query/data.json')
    render(json: {ok: { fields: fields, values: values}}.to_json)
  end

  def users
    fields, values = do_request('/tq_users/data.json')
    render(json: {ok: { fields: fields, values: values}}.to_json)
  end

  private

  def do_request(processing_url)
    logger.info processing_url
    http = Net::HTTP.new('api.logiceditor.com', 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    r = Net::HTTP::Post.new(processing_url)
    r.body = params.to_json
    r["Content-Type"] = "application/json"
    resp = http.request(r)
    print "---"
    print resp
    print "---"
    print resp.body
    sql = ActiveSupport::JSON.decode(resp.body)['ok']['code']
    pgresult = CustomQuery.run(sql)
    [pgresult.fields, pgresult.values]
  end
end
