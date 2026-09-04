# frozen_string_literal: true

require_relative 'base'
require_relative 'service_paths'

module Forge
  module Renderers
    # mock_server.rb по templates/mock_server.rb.erb (docs/OUTPUT_FORMAT.md § 5): Sinatra-мок провайдера из плана.
    class MockServer < Base
      def template_name = 'mock_server.rb.erb'
      def filename = 'mock_server.rb'

      private

      def paths = @paths ||= ServicePaths.new(plan)
      def op(role) = plan.operations[role]
      def class_name = "#{plan.provider[:class_name].delete_suffix('Service')}Mock"
      def sinatra_path(role) = op(role).path.gsub(/\{(\w+)\}/, ':\1')
      def status_path = (op(:create).response_status_path || ['status']).inspect
      def id_path = (op(:create).response_id_path || ['id']).inspect
      def amount_path = plan.amount[:path].inspect

      # Обязательные корневые ключи: required из схемы запроса (плоские поля и контейнер реквизитов).
      def required_fields
        schema = op(:create).endpoint.request_body&.schema
        Array(schema&.required)
      end

      def idempotency_header = op(:create).headers.first&.provider_field

      # Минимум в единицах провайдера.
      def min_amount
        min = plan.amount[:minimum_major]
        return nil unless min

        plan.amount[:unit] == :minor ? min * plan.amount[:multiplier] : min
      end

      def status_for(internal, prefer: nil)
        raws = plan.status_map.select { |_raw, int| int == internal }.keys
        (prefer && raws.find { |r| r.downcase.include?(prefer) }) || raws.first
      end

      def initial_status = status_for('in_progress') || plan.status_map.keys.first
      def cancelled_status = status_for('rejected', prefer: 'cancel') || status_for('rejected')

      def events
        return plan.event_map unless plan.event_map.empty?

        plan.status_map
      end

      def webhook_id_path = (plan.webhook&.dig(:id_field) || ['id']).inspect
      def webhook_status_path = plan.webhook&.dig(:status_field)&.inspect
      def event_field = plan.webhook&.dig(:event_field)
      def signature = plan.webhook&.dig(:signature)
      def auth = plan.auth
    end
  end
end
