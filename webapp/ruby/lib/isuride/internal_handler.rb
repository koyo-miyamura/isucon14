# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      # MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
      ride = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1').first
      unless ride
        halt 204
      end


      # 基準点
      lat = ride[:pickup_latitude]
      lon = ride[:pickup_longitude]

      # 最も近くにある椅子を返す
      matches = db.query(<<~SQL)
               SELECT chair.id,
                      ABS(chair_locations.latitude - #{lat}) + ABS(chair_locations.longitude - #{lon}) AS dist
                 FROM chairs
           INNER JOIN chair_locations
                   ON chair_locations.chair_id = chairs.id
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

      204
    end
  end
end
