# frozen_string_literal: true

module Forge
  # Разворачивает локальные `$ref` (JSON-pointer, `~0`/`~1`) на месте, рекурсивно.
  # Внешние ссылки не резолвит: заменяет узел на `{'x-forge-unresolved' => ref}` (D-05).
  # Схемы из `#/components/schemas/<Name>` получают `x-forge-ref-name`.
  class RefResolver
    SCHEMA_PREFIX = '#/components/schemas/'

    def self.resolve(root, file: nil) = new(root, file).resolve

    def initialize(root, file)
      @root = root
      @file = file
      @stack = []
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
      raise circular(ref, pointer) if @stack.include?(ref)

      @stack.push(ref)
      target = walk(lookup(ref, pointer), ref)
      @stack.pop
      annotate(target, ref)
    end

    def lookup(ref, pointer)
      ref.delete_prefix('#/').split('/').reduce(@root) do |node, key|
        key = unescape(key)
        child = node.is_a?(Array) ? node[Integer(key, exception: false) || -1] : node&.[](key)
        child.nil? ? raise(unresolved(ref, pointer)) : child
      end
    end

    def annotate(target, ref)
      return target unless target.is_a?(Hash) && ref.start_with?(SCHEMA_PREFIX)

      target.merge('x-forge-ref-name' => ref.delete_prefix(SCHEMA_PREFIX))
    end

    def unresolved(ref, pointer)
      SpecError.new("unresolved $ref '#{ref}'", pointer: pointer, file: @file,
                                                hint: 'check the pointer: the target must exist in this document')
    end

    def circular(ref, pointer)
      chain = (@stack + [ref]).join(' -> ')
      SpecError.new("circular $ref: #{chain}", pointer: pointer, file: @file,
                                               hint: 'break the cycle: inline one side or drop the back-reference')
    end

    def escape(key) = key.to_s.gsub('~', '~0').gsub('/', '~1')
    def unescape(key) = key.gsub('~1', '/').gsub('~0', '~')
  end
end
