# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      rides = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 10')
      rides.each do |ride|
        # 基準点
        lat = ride[:pickup_latitude]
        lon = ride[:pickup_longitude]

        # 目的地
        lat2 = ride[:destination_latitude]
        lon2 = ride[:destination_longitude]

        # 目的地への距離
        dist = calculate_distance(lat, lon, lat2, lon2)

        matches = db.query(<<~SQL)
               SELECT chairs.id,
                      ABS(chair_locations.latitude - #{lat}) + ABS(chair_locations.longitude - #{lon})
                       + #{dist}/chair_models.speed AS dist
                 FROM chairs
           INNER JOIN chair_locations
                   ON chair_locations.chair_id = chairs.id
           INNER JOIN chair_models
                   ON chair_models.name = chairs.model
                WHERE chairs.is_active = TRUE
             ORDER BY dist
        SQL

        matches.each do |matched|
          empty = db.xquery('SELECT COUNT(*) = 0 FROM (SELECT COUNT(chair_sent_at) = 6 AS completed FROM ride_statuses WHERE ride_id IN (SELECT id FROM rides WHERE chair_id = ?) GROUP BY ride_id) is_completed WHERE completed = FALSE', matched.fetch(:id), as: :array).first[0]

          if empty > 0
            db.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', matched.fetch(:id), ride.fetch(:id))
            break
          end
        end
      end

      204
    end
  end
end
