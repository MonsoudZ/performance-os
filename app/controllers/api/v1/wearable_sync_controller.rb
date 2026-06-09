module Api
  module V1
    class WearableSyncController < ActionController::API
      before_action :authenticate_device!

      def create
        result = WearableSyncIngestor.new(@device, samples: sync_params.fetch(:samples)).call
        render json: result, status: :accepted
      rescue ActiveRecord::RecordInvalid, KeyError, ArgumentError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      private

      def authenticate_device!
        device_id, raw_token = bearer_token.to_s.split(".", 2)
        @device = WearableDevice.active.find_by(id: device_id)
        return if @device&.authenticate_token(raw_token)

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def bearer_token
        request.authorization&.delete_prefix("Bearer ")
      end

      def sync_params
        params.permit(samples: [
          :external_id,
          :metric_type,
          :started_at,
          :ended_at,
          :value,
          { metadata: {} }
        ]).to_h
      end
    end
  end
end
