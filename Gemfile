# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.3'

# CLI
gem 'thor', '~> 1.3'

# HTTP-клиент в заглушке Provider::BaseService (используется сгенерированным кодом)
gem 'faraday', '~> 2.9'

# Мок-сервер провайдера (bin/forge mock, bin/e2e) и приёмник webhook
gem 'puma', '~> 6.4'
gem 'rackup', '~> 2.1'
gem 'sinatra', '~> 4.0'

# Задачи сборки/проверок
gem 'rake', '~> 13.2'

group :development, :test do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.75', require: false
  gem 'rubocop-rake', '~> 0.7', require: false
  gem 'rubocop-rspec', '~> 3.6', require: false
  gem 'simplecov', '~> 0.22', require: false
  gem 'webmock', '~> 3.23'
end

# Резерв R1 (обсудить перед добавлением): валидация фикстур по JSON Schema
# gem 'json_schemer', '~> 2.3'
