# frozen_string_literal: true

require 'json'
require_relative 'base'

module Forge
  module Renderers
    # fixtures.json — без ERB, JSON.pretty_generate плана.
    class Fixtures < Base
      def filename = 'fixtures.json'
      def render = "#{JSON.pretty_generate(plan.fixtures)}\n"
    end
  end
end
