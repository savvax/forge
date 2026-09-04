# frozen_string_literal: true

module Forge
  module Plan
    # Имя провайдера → name / class_name / env_prefix / file_name.
    module Naming
      STOP_WORDS = %w[api apis payout payouts payment payments transfer transfers outbound service services rest
                      gateway platform v\d+ openapi spec].freeze

      module_function

      def from_provider(provider)
        name = provider.strip.downcase.gsub(/[^a-z0-9]+/, '_').delete_prefix('_').delete_suffix('_')
        { name: name, class_name: "#{camelize(name)}Service", env_prefix: name.upcase, file_name: "#{name}_service.rb",
          title: provider }
      end

      def from_title(title)
        words = title.to_s.split(/[\s\-_]+/).reject { |w| STOP_WORDS.any? { |s| w.downcase.match?(/\A#{s}\z/) } }
        from_provider(words.empty? ? 'provider' : words.join(' '))
      end

      def camelize(name) = name.split('_').map(&:capitalize).join
    end
  end
end
