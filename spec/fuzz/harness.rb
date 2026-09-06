# frozen_string_literal: true

require 'timeout'
require 'fileutils'

module Fuzz
  # Общее для rake fuzz:*: один кейс = один блок; любое исключение (кроме Interrupt) — падение.
  # Отчёт печатает падения с первыми кадрами из lib/forge и завершает процесс с кодом 1.
  class Harness
    TMP = File.expand_path('../../tmp/fuzz', __dir__)

    attr_reader :crashes, :total

    def initialize(name)
      @name = name
      @crashes = []
      @total = 0
    end

    def workdir(sub)
      dir = File.join(TMP, sub)
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(dir)
      dir
    end

    def check(label, timeout: 120, &)
      @total += 1
      Timeout.timeout(timeout, &)
    rescue StandardError, SystemStackError, ScriptError => e
      @crashes << [label, e]
    end

    def report!(extra = '')
      puts "=== fuzz:#{@name}: #{@crashes.size} crashes of #{@total} cases#{extra}"
      @crashes.each do |label, e|
        frames = e.backtrace.to_a.grep(%r{/lib/forge/}).first(3).map { |f| f.sub(%r{.*/lib/forge/}, 'lib/forge/') }
        puts "#{label}\n  #{e.class}: #{e.message.lines.first.to_s.strip[0, 200]}\n  #{frames.join("\n  ")}"
      end
      exit(1) unless @crashes.empty?
    end
  end
end
