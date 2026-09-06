# frozen_string_literal: true

# rake fuzz:mutate — мутационный фаззинг конвейера: случайные структурные искажения спек из examples/
# (и до четырёх небольших реальных спек, если скачаны) и overrides с фиксированным seed → GenerateCommand.
# Красный: любое исключение, кроме Forge::Error; отдельно считаются InternalError (обработано, но не Shape).
# SEED=42 ROUNDS=100 — переопределяются через окружение.
require 'yaml'
require 'json'
require 'date'
require 'stringio'
require_relative 'harness'
require_relative '../../lib/forge'
require_relative '../../lib/forge/generate_command'

module Fuzz
  class Mutate
    SEED = Integer(ENV.fetch('SEED', 42))
    ROUNDS = Integer(ENV.fetch('ROUNDS', 100))
    REPLACEMENTS = [nil, 'str', 5, -1, 2.5, [], {}, [nil], [5], { 'a' => 1 }, true, false, '', 10**30, '$ref',
                    '#/components/schemas/X', { '$ref' => 5 }, { '$ref' => '#/' }, { '$ref' => '#/paths' }].freeze
    KEYS = [7, '', 'x-y', "a\nb"].freeze

    def initialize
      @rng = Random.new(SEED)
      @h = Harness.new("mutate seed=#{SEED} rounds=#{ROUNDS}")
      @work = @h.workdir('mutate')
      @internal = Hash.new(0)
      @counts = Hash.new(0)
    end

    def run
      specs.each { |path| ROUNDS.times { |i| spec_round(path, i) } }
      overrides.each { |path| ((ROUNDS / 3) + 1).times { |i| overrides_round(path, i) } }
      report
    end

    private

    def specs
      real = Dir['examples/real/*.{json,yaml,yml}'].select { |f| File.size(f) < 400_000 }.sort.first(4)
      Dir['examples/specs/*'] + real
    end

    def overrides = Dir['examples/overrides/*.yml']

    def spec_round(path, index)
      ext = path.end_with?('.json') ? 'json' : 'yaml'
      doc = mutate(deep_copy(base(path)), 1 + @rng.rand(6))
      file = File.join(@work, "spec.#{ext}")
      File.write(file, ext == 'json' ? JSON.generate(doc) : YAML.dump(doc))
      generate("#{File.basename(path)}##{index}", file, nil)
    rescue JSON::GeneratorError
      nil # мутация дала несериализуемый документ — пропуск
    end

    def overrides_round(path, index)
      spec = Dir["examples/specs/#{File.basename(path, '.yml')}.*"].first
      file = File.join(@work, 'overrides.yml')
      File.write(file, YAML.dump(mutate(deep_copy(base(path)), 1 + @rng.rand(4))))
      generate("#{File.basename(path)}##{index}", spec, file)
    end

    def base(path)
      @base ||= {}
      @base[path] ||= begin
        raw = YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: true)
        Forge::Loader.new(path).send(:stringify, raw)
      end
    end

    def deep_copy(obj) = Marshal.load(Marshal.dump(obj))

    def generate(label, spec, overrides_path)
      opts = { spec: spec, out: File.join(@work, 'out'), overrides: overrides_path, force: true, verify: false,
               format: 'json', include_paths: [], provider: nil, templates_dir: nil }
      @h.check(label) { quiet { classify(label, spec, overrides_path) { Forge::GenerateCommand.new(opts).run } } }
    end

    def classify(label, spec, overrides_path)
      yield
      @counts[:ok] += 1
    rescue Forge::InternalError => e
      @counts[:internal] += 1
      @internal["#{e.message.lines.first.to_s.strip[0, 90]} @ #{origin(e)}"] += 1
      keep(label, spec, overrides_path)
    rescue Forge::Error
      @counts[:forge_error] += 1
    end

    def origin(error)
      error.cause&.backtrace.to_a.grep(%r{lib/forge}).first.to_s[%r{lib/forge/[^:]+:\d+}]
    end

    def keep(label, spec, overrides_path)
      name = label.tr('#', '_')
      FileUtils.cp(spec, File.join(@work, "internal-#{name}#{File.extname(spec)}"))
      FileUtils.cp(overrides_path, File.join(@work, "internal-#{name}.overrides.yml")) if overrides_path
    end

    def quiet
      saved = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = saved
    end

    # --- мутации -------------------------------------------------------------------------------------

    def paths(node, prefix = [])
      case node
      when Hash then node.flat_map { |k, v| [prefix + [k]] + paths(v, prefix + [k]) }
      when Array then node.each_with_index.flat_map { |v, i| [prefix + [i]] + paths(v, prefix + [i]) }
      else []
      end
    end

    def parent_of(root, path) = path[0..-2].reduce(root) { |n, k| n[k] }
    def value_at(root, path) = path.reduce(root) { |n, k| n.is_a?(Hash) || n.is_a?(Array) ? n[k] : nil }

    def mutate(doc, count)
      count.times do
        all = paths(doc)
        break if all.empty?

        mutate_one(doc, all, all.sample(random: @rng))
      end
      doc
    end

    # 60 % — подмена значения, 20 % — удаление, 10 % — перенос чужого куска, 10 % — переименование ключа.
    def mutate_one(doc, all, path)
      parent = parent_of(doc, path)
      case @rng.rand(10)
      when 0..5 then parent[path.last] = deep_copy(REPLACEMENTS.sample(random: @rng))
      when 6..7 then parent.is_a?(Hash) ? parent.delete(path.last) : parent.delete_at(path.last)
      when 8 then parent[path.last] = deep_copy(value_at(doc, all.sample(random: @rng)))
      else parent[KEYS.sample(random: @rng)] = parent.delete(path.last) if parent.is_a?(Hash)
      end
    end

    def report
      @internal.sort_by { |_, n| -n }.each { |msg, n| puts "#{n.to_s.rjust(4)}  #{msg}" }
      @h.report!(" #{@counts.sort.to_h}")
      return if @internal.empty?

      puts "internal errors are handled, but Shape should reject the input with a pointer: see #{@work}/internal-*"
      exit(1)
    end
  end
end

Fuzz::Mutate.new.run if $PROGRAM_NAME == __FILE__
