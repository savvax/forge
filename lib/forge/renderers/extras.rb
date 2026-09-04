# frozen_string_literal: true

require_relative 'base'
require_relative 'service_view'

module Forge
  module Renderers
    # <provider>_extras.rb: хелперы вне контракта (cancel_request, fetch_balance) отдельным классом-наследником.
    # Нет таких эндпоинтов → render возвращает nil, файл не пишется.
    class Extras < Base
      def template_name = 'extras.rb.erb'
      def filename = "#{plan.provider[:name]}_extras.rb"
      def applicable? = !(plan.operations[:cancel] || plan.operations[:balance]).nil?
      def render = applicable? ? super : nil

      private

      def view = @view ||= ServiceView.new(plan)
    end
  end
end
