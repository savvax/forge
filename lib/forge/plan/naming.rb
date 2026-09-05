# frozen_string_literal: true

require 'uri'

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

      # Title из одних стоп-слов («Transfers API») → имя из домена сервера (pal-test.example.com → example).
      def from_title(title, host: nil)
        words = title.to_s.split(/[\s\-_]+/).reject { |w| STOP_WORDS.any? { |s| w.downcase.match?(/\A#{s}\z/) } }
        from_provider(words.empty? ? from_host(host) || 'provider' : words.join(' '))
      end

      def from_host(url)
        labels = URI(url.to_s).host.to_s.split('.')
        labels.size >= 2 ? labels[-2] : nil
      rescue URI::InvalidURIError
        nil
      end

      def camelize(name) = name.split('_').map(&:capitalize).join
    end
  end
end
