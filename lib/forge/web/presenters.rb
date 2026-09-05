# frozen_string_literal: true

require 'json'
require 'cgi'
require_relative 'markdown'

module Forge
  module Web
    # Рендер артефактов для просмотра в браузере: подсветка Ruby и JSON-дерево (Markdown — Web::Markdown).
    # Только stdlib и регулярные выражения — этого хватает для сгенерированных файлов.
    module Presenters
      KEYWORDS = %w[def end class module return if unless else elsif case when then do rescue raise super private
                    require require_relative yield self nil true false attr_reader freeze].freeze
      RUBY_TOKENS = [
        [/#.*$/, 'c'],
        [/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/, 's'],
        [/\b(?:#{KEYWORDS.join('|')})\b/, 'k'],
        [/\b[A-Z][A-Za-z0-9_]*\b/, 'C'],
        [/(?<![A-Za-z0-9_])[:@]\w+/, 'y'],
        [/\b\d+(?:\.\d+)?\b/, 'n']
      ].freeze
      RUBY_RE = Regexp.union(RUBY_TOKENS.map(&:first))

      module_function

      def esc(text) = CGI.escapeHTML(text.to_s)

      def markdown(text) = Markdown.render(text)

      def ruby(source)
        lines = source.lines.map { |line| line.chomp.gsub(RUBY_RE) { |tok| token(tok) } }
        rows = lines.each_with_index.map do |html, i|
          %(<tr><td class="ln">#{i + 1}</td><td class="code">#{html}</td></tr>)
        end
        %(<table class="src">#{rows.join}</table>)
      end

      def token(tok)
        klass = RUBY_TOKENS.find { |re, _| tok.match?(/\A#{re}\z/) }&.last
        klass ? %(<span class="t-#{klass}">#{esc(tok)}</span>) : esc(tok)
      end

      # JSON → дерево <details>; невалидный JSON — как есть.
      def json_tree(text)
        json_node(JSON.parse(text), 'fixtures', open: true)
      rescue JSON::ParserError
        %(<pre>#{esc(text)}</pre>)
      end

      def json_node(value, key, open: false)
        pairs = case value
                when Hash then value.to_a
                when Array then value.each_with_index.map { |v, i| [i, v] }
                else return json_leaf(value, key)
                end
        summary = value.is_a?(Hash) ? "{#{value.size}}" : "[#{value.size}]"
        head = %(<summary><span class="jk">#{esc(key)}</span> <span class="jm">#{summary}</span></summary>)
        %(<details#{' open' if open}>#{head}<div class="jc">#{pairs.map do |k, v|
          json_node(v, k)
        end.join}</div></details>)
      end

      def json_leaf(value, key)
        klass = value.is_a?(String) ? 'js' : 'jn'
        shown = esc(value.inspect)
        %(<div class="jl"><span class="jk">#{esc(key)}</span>: <span class="#{klass}">#{shown}</span></div>)
      end
    end
  end
end
