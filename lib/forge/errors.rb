# frozen_string_literal: true

module Forge
  # Базовая ошибка: "<что не так> at <pointer> in <file>\n  hint: <что сделать>".
  class Error < StandardError
    attr_reader :pointer, :hint, :file

    def self.exit_code = 1

    def initialize(message, pointer: nil, hint: nil, file: nil)
      @pointer = pointer
      @hint = hint
      @file = file
      super(format_message(message))
    end

    private

    def format_message(message)
      text = message.dup
      text << " at #{pointer}" if pointer
      text << " in #{file}" if file
      text << "\n  hint: #{hint}" if hint
      text
    end
  end

  class SpecError < Error; end

  class UnsupportedError < Error; end

  class GenerationError < Error
    def self.exit_code = 2
  end

  # Любое неожиданное исключение конвейера (баг на редкой структуре): без стектрейса, `cause` для --debug.
  class InternalError < GenerationError; end

  class VerificationError < Error
    def self.exit_code = 3
  end
end
