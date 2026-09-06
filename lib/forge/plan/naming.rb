# frozen_string_literal: true

require 'uri'

module Forge
  module Plan
    # Имя провайдера → name / class_name / env_prefix / file_name.
    module Naming
      STOP_WORDS = %w[api apis payout payouts payment payments transfer transfers outbound service services rest
                      gateway platform v\d+ openapi spec].freeze

      module_function

      # Имя файла/класса: ≤ 60 символов, не начинается с цифры, мусор («!!!») → provider.
      def from_provider(provider)
        name = provider.to_s.strip.downcase.gsub(/[^a-z0-9]+/, '_')[0, 60].delete_prefix('_').delete_suffix('_')
        name = "p#{name}" if name.match?(/\A\d/)
        name = 'provider' if name.empty?
        { name: name, class_name: "#{camelize(name)}Service", env_prefix: name.upcase, file_name: "#{name}_service.rb",
          title: provider }
      end

      # Title из одних стоп-слов («Transfers API») → имя из домена сервера (pal-test.example.com → example).
      def from_title(title, host: nil)
        words = title.to_s.split(/[\s\-_]+/).reject { |w| STOP_WORDS.any? { |s| w.downcase.match?(/\A#{s}\z/) } }
        latin = words.join(' ').gsub(/[^A-Za-z0-9\s]/, '').strip
        from_provider(latin.empty? ? from_host(host) || 'provider' : latin)
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
