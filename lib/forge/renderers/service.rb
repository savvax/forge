# frozen_string_literal: true

require_relative 'base'
require_relative 'service_view'

module Forge
  module Renderers
    # <provider>_service.rb по templates/service.rb.erb; логика представления — ServiceView.
    class Service < Base
      def template_name = 'service.rb.erb'
      def filename = plan.provider[:file_name]

      private

      def view = @view ||= ServiceView.new(plan)
    end
  end
end
