# frozen_string_literal: true

require 'open3'

module Forge
  # Проверка сгенерированного кода: `ruby -c` (синтаксис) и rspec сгенерированного spec.
  module Verifier
    module_function

    def syntax!(paths)
      paths.each do |path|
        out, status = Open3.capture2e('ruby', '-c', path)
        next if status.success?

        raise VerificationError.new("generated file has a syntax error:\n#{out.strip}", file: path,
                                                                                        hint: SYNTAX_HINT)
      end
      paths
    end

    SYNTAX_HINT = 'this is a template bug; report it with the spec that triggered it'
    RSPEC_HINT = 'run it directly to see the full output; --no-verify skips this step'

    # --options /dev/null: не читать .rspec проекта (spec_helper + SimpleCov относятся к forge, не к выводу).
    def rspec!(spec_path, load_paths: [])
      args = ['bundle', 'exec', 'rspec', '--options', '/dev/null', *load_paths.flat_map { |p| ['-I', p] }, spec_path]
      out, status = Open3.capture2e(*args)
      return out if status.success?

      raise VerificationError.new("generated spec failed:\n#{out.lines.last(30).join}", file: spec_path,
                                                                                        hint: RSPEC_HINT)
    end
  end
end
