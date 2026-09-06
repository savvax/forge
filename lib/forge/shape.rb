# frozen_string_literal: true

module Forge
  # Форма документа после резолва $ref: контейнеры там, где их ждут IR::Builder и анализаторы.
  # Это не валидатор OpenAPI — только то, без чего конвейер упал бы с NoMethodError. Нарушение → SpecError
  # с pointer. `null` у ключа = ключа нет (черновики «post:» без тела); `null` в массиве — ошибка.
  # Расширения `x-*` не проверяются. Правило: Hash — ключи узла ('*' — остальные), [rule] — массив, символ — тип.
  class Shape
    METHODS = %w[get post put patch delete head options trace].freeze
    SCHEMA = { 'properties' => { '*' => :schema }, 'items' => :schema, 'not' => :schema,
               'allOf' => [:schema], 'oneOf' => [:schema], 'anyOf' => [:schema],
               'required' => :array, 'enum' => :array, 'discriminator' => { 'mapping' => :hash },
               'minimum' => :number, 'maximum' => :number, 'multipleOf' => :number,
               'minLength' => :number, 'maxLength' => :number }.freeze
    MEDIA = { 'schema' => :schema, 'examples' => :hash }.freeze
    CONTENT = { '*' => MEDIA }.freeze
    PARAMETER = { 'schema' => :schema, 'content' => CONTENT }.freeze
    SERVER = { 'variables' => { '*' => { 'enum' => :array } } }.freeze
    RESPONSE = { 'content' => CONTENT, 'headers' => { '*' => { 'schema' => :schema } } }.freeze
    OPERATION = { 'parameters' => [PARAMETER], 'requestBody' => { 'content' => CONTENT },
                  'responses' => { '*' => RESPONSE }, 'security' => [{ '*' => :array }], 'servers' => [SERVER],
                  'callbacks' => { '*' => { '*' => :path_item } } }.freeze
    PATH_ITEM = METHODS.to_h { |m| [m, OPERATION] }.merge('parameters' => [PARAMETER], 'servers' => [SERVER]).freeze
    ROOT = { 'info' => :hash, 'servers' => [SERVER], 'security' => [{ '*' => :array }],
             'components' => { 'schemas' => { '*' => :schema }, '*' => { '*' => :hash } },
             'paths' => { '*' => PATH_ITEM }, 'webhooks' => { '*' => PATH_ITEM },
             'x-webhooks' => { '*' => PATH_ITEM } }.freeze
    TYPES = { hash: [Hash, 'object'], array: [Array, 'array'], number: [Numeric, 'number'] }.freeze

    def self.check!(doc, file: nil) = new(file).walk(doc, ROOT, '#')

    # Цели $ref после резолва — общие объекты (DAG): без памяти по identity обход большой спеки экспоненциален.
    def initialize(file)
      @file = file
      @seen = {}.compare_by_identity
    end

    def walk(node, rule, pointer)
      case rule
      when Array then each_item(node, rule.first, pointer)
      when Hash then each_key(node, rule, pointer)
      when :path_item then each_key(node, PATH_ITEM, pointer)
      when :schema then each_key(node, SCHEMA, pointer) unless [true, false].include?(node)
      else expect!(node, *TYPES.fetch(rule), pointer)
      end
    end

    private

    def each_item(node, rule, pointer)
      expect!(node, Array, 'array', pointer)
      return if seen?(node, rule)

      node.each_with_index { |v, i| walk(v, rule, "#{pointer}/#{i}") }
    end

    def each_key(node, rules, pointer)
      expect!(node, Hash, 'object', pointer)
      return if seen?(node, rules)

      node.each do |key, value|
        rule = rules[key] || (rules['*'] unless key.start_with?('x-'))
        walk(value, rule, "#{pointer}/#{escape(key)}") if rule && !value.nil?
      end
    end

    def seen?(node, rule)
      rules = (@seen[node] ||= [])
      return true if rules.any? { |r| r.equal?(rule) }

      rules << rule
      false
    end

    def expect!(node, klass, want, pointer)
      return if node.is_a?(klass) && !node.nil?

      raise SpecError.new("expected #{want}, got #{kind(node)}", pointer: pointer, file: @file,
                                                                 hint: 'fix the document structure (OpenAPI 3)')
    end

    def kind(node)
      case node
      when nil then 'null'
      when Hash then 'object'
      when Array then 'array'
      when String then 'string'
      when Numeric then 'number'
      when true, false then 'boolean'
      else node.class.name.downcase
      end
    end

    def escape(key) = key.to_s.gsub('~', '~0').gsub('/', '~1')
  end
end
