# frozen_string_literal: true

require 'faraday'
require 'json'

module Provider
  # Тонкая обёртка над Faraday: JSON/form тела, разбор ответа, типизированные ошибки.
  # 401 → UnauthorizedError, 429 → RateLimitError, 5xx → ServerError, сеть → ConnectionError.
  # Прочие 4xx возвращаются как Response — их интерпретирует сервис через ERROR_MAP.
  class HttpClient
    Response = Data.define(:status, :body, :headers)

    def initialize(connection: nil, timeout: 10, open_timeout: 5)
      @connection = connection || Faraday.new do |f|
        f.options.timeout = timeout
        f.options.open_timeout = open_timeout
        f.adapter Faraday.default_adapter
      end
    end

    def get(url, headers: {}, params: {})
      perform(:get, url, headers: headers, params: params)
    end

    def post(url, json: nil, form: nil, headers: {})
      perform(:post, url, headers: headers, json: json, form: form)
    end

    def delete(url, headers: {})
      perform(:delete, url, headers: headers)
    end

    private

    def perform(verb, url, headers:, json: nil, form: nil, params: {})
      raw = @connection.run_request(verb, url, encode_body(json, form),
                                    content_headers(json, form).merge(headers)) do |req|
        req.params.update(params) unless params.empty?
      end
      response = Response.new(status: raw.status, body: parse_body(raw.body), headers: raw.headers.to_h)
      raise_for_status!(response)
      response
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError, "#{verb.upcase} #{url}: #{e.message}"
    end

    def encode_body(json, form)
      return JSON.generate(json) if json
      return URI.encode_www_form(flatten_form(form)) if form

      nil
    end

    # {destination: {account: 'x'}} → [['destination[account]', 'x']] (Rails-стиль вложенных ключей).
    def flatten_form(hash, prefix = nil)
      hash.flat_map do |key, value|
        name = prefix ? "#{prefix}[#{key}]" : key.to_s
        value.is_a?(Hash) ? flatten_form(value, name) : [[name, value]]
      end
    end

    def content_headers(json, form)
      return { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } if json
      return { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' } if form

      { 'Accept' => 'application/json' }
    end

    def parse_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'raw' => body }
    end

    def raise_for_status!(response)
      case response.status
      when 401 then raise UnauthorizedError, response
      when 429 then raise RateLimitError.new(response, retry_after: response.headers['retry-after'])
      when 500..599 then raise ServerError, response
      end
    end
  end
end
