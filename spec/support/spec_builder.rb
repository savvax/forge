# frozen_string_literal: true

# Помощник для коротких тестов анализаторов: минимальная валидная OpenAPI-hash,
# части которой можно переопределить. См. docs/TESTING.md § 2.
module SpecBuilder
  def build_spec(paths: {}, security_schemes: {}, schemas: {}, servers: nil, security: nil, openapi: '3.0.3',
                 title: 'Test API')
    spec = {
      'openapi' => openapi,
      'info' => { 'title' => title, 'version' => '1.0.0' },
      'servers' => servers || [{ 'url' => 'https://api.test.example/v1', 'description' => 'Sandbox' }],
      'paths' => paths,
      'components' => { 'securitySchemes' => security_schemes, 'schemas' => schemas }
    }
    spec['security'] = security if security
    spec
  end

  def body_json(properties, required: properties.keys, example: nil)
    body = {
      'required' => true,
      'content' => {
        'application/json' => {
          'schema' => { 'type' => 'object', 'required' => required, 'properties' => properties }
        }
      }
    }
    body['content']['application/json']['example'] = example if example
    body
  end

  def response_json(status, properties, example: nil)
    res = { 'description' => "HTTP #{status}",
            'content' => { 'application/json' => { 'schema' => { 'type' => 'object', 'properties' => properties } } } }
    res['content']['application/json']['example'] = example if example
    { status.to_s => res }
  end

  def ir_for(hash)
    Forge::IR::Builder.build(Forge::RefResolver.resolve(hash), source_path: 'inline.yaml')
  end
end

RSpec.configure { |c| c.include SpecBuilder }
