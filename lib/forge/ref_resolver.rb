# frozen_string_literal: true

require 'uri'

module Forge
  # Разворачивает локальные `$ref` (JSON-pointer, `~0`/`~1`, percent-encoding) на месте, рекурсивно.
  # Внешние ссылки не резолвит: заменяет узел на `{'x-forge-unresolved' => ref}` (D-05).
  # Цикл (рекурсивная схема) обрывается маркером `{'x-forge-circular' => 'A -> B -> A'}`; критичность
  # решает Analyzers::Fields (D-14). Схемы из `#/components/schemas/<Name>` получают `x-forge-ref-name`.
  class RefResolver
    SCHEMA_PREFIX = '#/components/schemas/'

    def self.resolve(root, file: nil) = new(root, file).resolve

    def initialize(root, file)
      @root = root
      @file = file
      @stack = []
      @cache = {}
    end

    def resolve = walk(@root, '#')

    private

    def walk(node, pointer)
      case node
      when Hash then node.key?('$ref') ? deref(node['$ref'], pointer) : walk_hash(node, pointer)
      when Array then node.each_with_index.map { |v, i| walk(v, "#{pointer}/#{i}") }
      else node
      end
    end

    def walk_hash(hash, pointer)
      hash.to_h { |k, v| [k, walk(v, "#{pointer}/#{escape(k)}")] }
    end

    def deref(ref, pointer)
      return { 'x-forge-unresolved' => ref } unless ref.start_with?('#/')
      return circular(ref) if @stack.include?(ref)

      annotate(resolved(ref, pointer), ref)
    end

    # Каждая цель резолвится один раз (большие спеки: тысячи ссылок на одни и те же схемы).
    def resolved(ref, pointer)
      return @cache[ref] if @cache.key?(ref)

      @stack.push(ref)
      target = walk(lookup(ref, pointer), ref)
      @stack.pop
      @cache[ref] = target
    end

    # Несуществующая цель → маркер `{'x-forge-unresolved' => ref}`; критичность решает Analyzers::Fields.
    def lookup(ref, _pointer)
      ref.delete_prefix('#/').split('/').reduce(@root) do |node, key|
        key = unescape(URI.decode_www_form_component(key))
        child = node.is_a?(Array) ? node[Integer(key, exception: false) || -1] : node&.[](key)
        return { 'x-forge-unresolved' => ref } if child.nil?

        child
      end
    end

    def annotate(target, ref)
      return target unless target.is_a?(Hash) && ref.start_with?(SCHEMA_PREFIX)

      target.merge('x-forge-ref-name' => ref.delete_prefix(SCHEMA_PREFIX))
    end

    def circular(ref)
      { 'x-forge-circular' => (@stack + [ref]).join(' -> '), 'x-forge-ref-name' => ref.delete_prefix(SCHEMA_PREFIX) }
    end

    def escape(key) = key.to_s.gsub('~', '~0').gsub('/', '~1')
    def unescape(key) = key.gsub('~1', '/').gsub('~0', '~')
  end
end
