# frozen_string_literal: true

# Копируется в output рядом со сгенерированным spec. Подключает контракт-заглушку и WebMock.
require 'bigdecimal'
require 'bigdecimal/util'
require 'json'
require 'base64'
require 'openssl'
require 'provider'
require 'webmock/rspec'

WebMock.disable_net_connect!

module GeneratedSpecHelper
  TEST_CREDENTIALS = { 'api_key' => 'test_api_key', 'token' => 'test_token', 'login' => 'test_login',
                       'password' => 'test_password', 'callback_secret' => 'test_secret',
                       'merchant_id' => 'test_merchant' }.freeze

  def fixtures = @fixtures ||= JSON.parse(File.read(File.join(__dir__, 'fixtures.json')))

  # Credentials/config из fixtures.create_request (значения примера спеки) поверх тестовых заглушек.
  def build_record(name)
    credentials = TEST_CREDENTIALS.merge(fixtures.dig('create_request', 'credentials') || {})
    config = { 'callback_url' => 'https://spacepayments.example/webhooks/test' }
             .merge(fixtures.dig('create_request', 'config') || {})
    Provider::Record.new(name: name, credentials: credentials, config: config)
  end

  def build_operation(fixture = fixtures.dig('create_request', 'operation'))
    Provider::Operation.new(id: fixture['id'], amount: fixture['amount'].to_s.to_d, currency: fixture['currency'],
                            payout_requisite: fixture['payout_requisite'] || {}, description: fixture['description'],
                            customer: fixture['customer'])
  end

  # Сравнение тела запроса без полей, которые forge не смог отобразить (TODO/массивы).
  def without_paths(hash, paths)
    copy = Marshal.load(Marshal.dump(hash))
    paths.each do |path|
      *head, last = path
      node = head.reduce(copy) { |cur, key| cur.is_a?(Hash) ? cur[key] : nil }
      node.delete(last) if node.is_a?(Hash)
    end
    copy
  end

  # HMAC той же схемой, что и сервис: algorithm 'sha256', encoding 'hex' | 'base64'.
  def sign(body, algorithm:, encoding:, secret: TEST_CREDENTIALS['callback_secret'])
    digest = OpenSSL::HMAC.digest(algorithm.upcase, secret, body)
    encoding == 'base64' ? Base64.strict_encode64(digest) : digest.unpack1('H*')
  end

  def dig_path(hash, path) = path.reduce(hash) { |node, key| node.is_a?(Hash) ? node[key] : nil }
end

RSpec.configure { |c| c.include GeneratedSpecHelper }
