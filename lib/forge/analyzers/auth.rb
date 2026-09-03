# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Схема авторизации create-эндпоинта: apiKey → api_key, bearer → token, basic → login/password.
    class Auth < Base
      BEARER = { type: 'bearer', header: 'Authorization', prefix: 'Bearer', credential_key: 'token',
                 credential_keys: ['token'], location: 'header' }.freeze
      NONE = { type: 'none', scheme_name: nil, header: nil, prefix: nil, credential_key: nil, credential_keys: [],
               location: nil }.freeze

      def call
        alternatives = requirements.map { |req| scheme_for(req.keys.first) }
        chosen = alternatives.find { |s| s && supported?(s) }
        alternatives.compact.each { |s| unsupported_alternative(s) unless s.equal?(chosen) }
        return fallback(alternatives) unless chosen

        finding(:auth, describe(chosen), confidence: 0.95, source: "securitySchemes.#{chosen.name} (#{chosen.type})")
      end

      private

      def requirements
        reqs = role(:create)&.security || spec.default_security || []
        reqs.reject(&:empty?)
      end

      def scheme_for(name)
        scheme = spec.security_schemes.find { |s| s.name == name }
        return scheme if scheme

        warn(:auth_scheme_missing, "security scheme '#{name}' is not defined in components.securitySchemes",
             pointer: '#/components/securitySchemes', hint: 'auth.type: api_key|bearer|basic (overrides.yml)')
        nil
      end

      def supported?(scheme)
        scheme.type == 'apiKey' || (scheme.type == 'http' && %w[bearer basic].include?(scheme.scheme))
      end

      def describe(scheme)
        return api_key(scheme) if scheme.type == 'apiKey'
        return BEARER.merge(scheme_name: scheme.name) if scheme.scheme == 'bearer'

        { type: 'basic', scheme_name: scheme.name, header: 'Authorization', prefix: 'Basic', credential_key: 'login',
          credential_keys: %w[login password], location: 'header' }
      end

      def api_key(scheme)
        in_header = scheme.location == 'header'
        unless in_header
          warn(:api_key_in_query, "apiKey '#{scheme.param_name}' is sent in #{scheme.location}, not header",
               pointer: pointer(scheme), hint: 'the generated client passes it as a query param')
        end
        { type: 'api_key', scheme_name: scheme.name, header: in_header ? scheme.param_name : nil, prefix: nil,
          credential_key: 'api_key', credential_keys: ['api_key'], location: scheme.location,
          param_name: scheme.param_name }
      end

      def unsupported_alternative(scheme)
        message = "alternative security scheme '#{scheme.name}' (#{scheme.type}) is ignored"
        unsupported(:"#{scheme.type}_alternative", message, pointer: pointer(scheme),
                                                            hint: 'the first supported scheme is used')
      end

      def fallback(alternatives)
        scheme = alternatives.compact.first
        return bearer_fallback(scheme) if scheme

        warn(:auth_not_found, 'no security requirement on the create endpoint or at the root',
             pointer: '#/security', hint: 'auth.type: api_key|bearer|basic (overrides.yml)')
        finding(:auth, NONE, confidence: 0.0, source: 'no security found')
      end

      def bearer_fallback(scheme)
        unsupported(scheme.type.to_sym, "security scheme '#{scheme.name}' (#{scheme.type}) is not supported; " \
                                        'bearer token assumed',
                    pointer: pointer(scheme), hint: 'obtain the token out of band and put it into credentials.token')
        finding(:auth, BEARER.merge(scheme_name: scheme.name), confidence: 0.5, source: "fallback for #{scheme.type}")
      end

      def pointer(scheme) = "#/components/securitySchemes/#{scheme.name}"
    end
  end
end
