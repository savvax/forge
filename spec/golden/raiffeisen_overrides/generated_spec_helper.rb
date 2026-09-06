# frozen_string_literal: true

# Копируется в output рядом со сгенерированным spec. Подключает контракт-заглушку и WebMock.
require 'bigdecimal'
require 'bigdecimal/util'
require 'json'
require 'uri'
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

  # Отправленное тело согласуется с примером из спеки: каждый ключ, который есть и там и там, совпадает по значению.
  # Отправленные поля без примера (из других алиасов operation) и пустые (nil/TODO) — допускаются.
  def subset_of?(actual, expected)
    case actual
    when Hash then hash_subset?(actual, expected)
    when Array then expected.is_a?(Array) && actual.each_with_index.all? { |v, i| subset_of?(v, expected[i]) }
    else actual == expected || actual.to_s == expected.to_s # form-тела приходят строками
    end
  end

  # nil, пустые Hash/Array и объекты из одних nil — поля без источника (TODO), они не сравниваются.
  def hash_subset?(actual, expected)
    return false unless expected.is_a?(Hash)

    actual.all? { |k, v| blank?(v) || !expected.key?(k) || subset_of?(v, expected[k]) }
  end

  def blank?(value)
    case value
    when nil then true
    when Hash then value.values.all? { |v| blank?(v) }
    when Array then value.empty?
    else false
    end
  end

  # Поля с пользовательским source из overrides.yml сравнивать нельзя (их значения не выводятся из примера).
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

  # Stripe-style header: t=<timestamp>,v1=<HMAC over "<t>.<body>">.
  def sign_timestamped(body, timestamp:, **) = "t=#{timestamp},v1=#{sign("#{timestamp}.#{body}", **)}"

  # Тело запроса → Hash: JSON или form-urlencoded (parent[child] → вложенный Hash, числа как строки).
  def parse_body(req)
    return JSON.parse(req.body) if req.headers['Content-Type'].to_s.include?('json')

    URI.decode_www_form(req.body).each_with_object({}) do |(key, value), acc|
      path = key.scan(/[^\[\]]+/)
      *head, last = path
      head.reduce(acc) { |node, k| node[k] ||= {} }[last] = value
    end
  end

  def dig_path(hash, path) = path.reduce(hash) { |node, key| node.is_a?(Hash) ? node[key] : nil }
end

RSpec.configure { |c| c.include GeneratedSpecHelper }
