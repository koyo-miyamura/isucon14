# frozen_string_literal: true

require 'open3'

require 'isuride/base_handler'

module Isuride
  class InitializeHandler < BaseHandler
    PostInitializeRequest = Data.define(:payment_server)

    post '/api/initialize' do
      req = bind_json(PostInitializeRequest)

      out, status = Open3.capture2e('../sql/init.sh')
      unless status.success?
        raise HttpError.new(500, "failed to initialize: #{out}")
      end

      db.xquery("UPDATE settings SET value = ? WHERE name = 'payment_gateway_url'", req.payment_server)

      db.xquery('DROP TABLE IF EXISTS chair_total_distances')

      db.xquery(<<~SQL)
        CREATE TABLE chair_total_distances AS
        SELECT
            chair_id,
            SUM(distance) AS total_distance,
            MAX(created_at) AS total_distance_updated_at
        FROM (
            SELECT
                chair_id,
                created_at,
                IFNULL(ABS(latitude - LAG(latitude) OVER (PARTITION BY chair_id ORDER BY created_at)) +
                ABS(longitude - LAG(longitude) OVER (PARTITION BY chair_id ORDER BY created_at)), 0) AS distance
            FROM
                chair_locations
        ) AS subquery
        GROUP BY
            chair_id
      SQL

      db.xquery('ALTER TABLE chair_total_distances ADD UNIQUE INDEX `idx_chair_id` (`chair_id`)')

      json(language: 'ruby')
    end
  end
end
