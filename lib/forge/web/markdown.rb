# frozen_string_literal: true

require 'cgi'

module Forge
  module Web
    # Подмножество Markdown, которого хватает для INTEGRATION.md: заголовки, таблицы, списки, ``` , цитаты,
    # `code`, **bold**, ссылки. Стриминг по строкам: fence — единый блок до закрывающих ```.
    module Markdown
      module_function

      def render(text)
        state = { blocks: [], buffer: [], fence: false }
        text.each_line { |raw| step(state, raw.chomp) }
        flush(state)
        state[:blocks].join("\n")
      end

      def step(state, line)
        return fence_line(state, line) if state[:fence] || line.start_with?('```')

        flush(state) if line.strip.empty? || (state[:buffer].any? && kind(state[:buffer].first) != kind(line))
        state[:buffer] << line unless line.strip.empty?
      end

      def fence_line(state, line)
        return close_fence(state) if state[:fence] && line.start_with?('```')
        return state[:buffer] << line if state[:fence]

        flush(state)
        state[:fence] = true
      end

      def flush(state)
        state[:blocks] << block(state[:buffer]) unless state[:buffer].empty?
        state[:buffer] = []
      end

      def close_fence(state)
        state[:blocks] << %(<pre>#{esc(state[:buffer].join("\n"))}</pre>)
        state[:buffer] = []
        state[:fence] = false
      end

      def kind(line)
        return :table if line.start_with?('|')
        return :list if line.match?(/\A\s*[-*] /)
        return :heading if line.start_with?('#')
        return :quote if line.start_with?('>')

        :para
      end

      def block(lines)
        case kind(lines.first)
        when :heading then heading(lines.first)
        when :table then table(lines)
        when :list then %(<ul>#{lines.map { |l| "<li>#{inline(l.sub(/\A\s*[-*] /, ''))}</li>" }.join}</ul>)
        when :quote then %(<blockquote>#{inline(lines.map { |l| l.sub(/\A>\s?/, '') }.join(' '))}</blockquote>)
        else %(<p>#{inline(lines.join(' '))}</p>)
        end
      end

      def heading(line)
        level = line[/\A#+/].size + 1
        %(<h#{level}>#{inline(line.sub(/\A#+\s*/, ''))}</h#{level}>)
      end

      def table(lines)
        rows = lines.grep_v(/\A\|[\s\-:|]+\|\z/).map { |l| cells(l) }
        head, *body = rows
        html = +'<table class="md">'
        html << "<tr>#{head.map { |c| "<th>#{inline(c)}</th>" }.join}</tr>"
        body.each { |r| html << "<tr>#{r.map { |c| "<td>#{inline(c)}</td>" }.join}</tr>" }
        html << '</table>'
      end

      def cells(line)
        line.strip.delete_prefix('|').delete_suffix('|').split(/(?<!\\)\|/).map { |c| c.strip.gsub('\\|', '|') }
      end

      def inline(text)
        esc(text).gsub(/`([^`]+)`/, '<code>\1</code>').gsub(/\*\*([^*]+)\*\*/, '<b>\1</b>')
                 .gsub(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="\2">\1</a>')
      end

      def esc(text) = CGI.escapeHTML(text.to_s)
    end
  end
end
