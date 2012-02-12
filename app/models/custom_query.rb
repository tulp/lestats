class CustomQuery < ActiveRecord::Base
  def self.run(query)
    Rails.logger.debug "start query"
    self.connection.execute(sanitize_sql(query))
  end
end
