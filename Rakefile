# frozen_string_literal: true

# Все проверки проекта — одной командой. Локальный эквивалент CI: `bundle exec rake ci`.
# Карточка задачи закрыта только при зелёном `bundle exec rake check`.

require 'rake'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'uri'

SPECS = {
  'novapay' => 'examples/specs/novapay.yaml',
  'cardpay' => 'examples/specs/cardpay.yaml',
  'swiftpay' => 'examples/specs/swiftpay.json',
  'raiffeisen' => 'examples/specs/raiffeisen.yaml'
}.freeze

OVERRIDES = {
  'cardpay' => 'examples/overrides/cardpay.yml',
  'swiftpay' => 'examples/overrides/swiftpay.yml',
  'raiffeisen' => 'examples/overrides/raiffeisen.yml'
}.freeze

# Реальные спеки провайдеров (docs/REAL_SPECS.md). Скачиваются в examples/real/, в git не попадают.
REAL_SPECS = {
  'stripe' => 'https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.json',
  'adyen_payout' => 'https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/PayoutService-v68.json',
  'adyen_transfers' => 'https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/TransferService-v4.json',
  'paypal_payouts' =>
    'https://raw.githubusercontent.com/paypal/paypal-rest-api-specifications/main/openapi/payments_payouts_batch_v1.json',
  'paystack' => 'https://raw.githubusercontent.com/PaystackHQ/openapi/master/dist/paystack.yaml',
  'square' => 'https://raw.githubusercontent.com/square/connect-api-specification/master/api.json',
  'plaid' => 'https://raw.githubusercontent.com/plaid/plaid-openapi/master/2020-09-14.yml',
  # Вторая волна (6.09): выплаты — Velo, Increase, Mollie, Dwolla, Wise, Open Banking PIS;
  # pay-in/конфиг как негативные — Klarna, PAYONE Link, VTEX, Adyen Balance Platform / Checkout,
  # NOWPayments (без POST /payout); GOV.UK Pay — Swagger 2.0 (ошибка загрузки).
  'velo' => 'https://api.apis.guru/v2/specs/velopayments.com/2.34.63/openapi.json',
  'increase' => 'https://api.apis.guru/v2/specs/increase.com/0.0.1/openapi.json',
  'mollie' => 'https://raw.githubusercontent.com/mollie/openapi/main/specs.yaml',
  'dwolla' => 'https://raw.githubusercontent.com/Dwolla/dwolla-openapi/main/openapi.yml',
  'wise_transfer' =>
    'https://raw.githubusercontent.com/api-evangelist/wise/main/openapi/wise-transfer-api-openapi.yml',
  'openbanking_pis' =>
    'https://api.apis.guru/v2/specs/openbanking.org.uk/payment-initiation-openapi/3.1.7/openapi.json',
  'nowpayments' => 'https://api.apis.guru/v2/specs/nowpayments.io/1.0.0/openapi.json',
  'klarna' => 'https://api.apis.guru/v2/specs/klarna.com/payments/1.0.0/openapi.json',
  'payone_link' => 'https://api.apis.guru/v2/specs/pay1.de/link/v1/openapi.json',
  'vtex_gateway' => 'https://api.apis.guru/v2/specs/vtex.local/Payments-Gateway-API/1.0/openapi.json',
  'adyen_balance' => 'https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/BalancePlatformService-v2.json',
  'adyen_checkout' => 'https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/CheckoutService-v71.json',
  'govuk_pay' => 'https://api.apis.guru/v2/specs/payments.service.gov.uk/payments/1.0.3/swagger.json'
}.freeze

# Флаги из docs/REAL_SPECS.md § 2 (большие спеки анализируем только по нужным путям).
REAL_FLAGS = {
  'paystack' => ['--include-paths', '/transfer*', '--include-paths', '/balance'],
  'stripe' => ['--include-paths', '/v1/payouts*'],
  'square' => ['--include-paths', '/v2/payouts*'],
  'plaid' => ['--include-paths', '/transfer/*']
}.freeze

ALLOWED_LICENSES = %w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause Ruby BSD ISC].freeze

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.exclude_pattern = 'spec/golden/**/*_spec.rb' # golden — это вывод генератора, не тесты forge
end

RuboCop::RakeTask.new(:rubocop)

desc 'rubocop'
task lint: :rubocop

desc 'rspec с покрытием (SimpleCov, пороги в spec/spec_helper.rb)'
task test: :spec

def sh_or_fail(cmd, env = {})
  out, status = Open3.capture2e(env, cmd)
  puts out
  abort "FAILED: #{cmd}" unless status.success?
  out
end

namespace :generate do
  SPECS.each do |name, path|
    desc "bin/forge generate для #{name}"
    task name.to_sym do
      sh_or_fail("bin/forge generate --spec #{path} --out tmp/out/#{name} --force")
      next unless OVERRIDES[name]

      sh_or_fail("bin/forge generate --spec #{path} --overrides #{OVERRIDES[name]} " \
                 "--out tmp/out/#{name}_overrides --force")
    end
  end

  # generated:spec берёт все tmp/out/*/ — чужой старый каталог там ломал бы прогон.
  desc 'Очистить tmp/out/'
  task(:clean) { rm_rf 'tmp/out' }

  desc 'Сгенерировать все примеры в tmp/out/ (каталог очищается)'
  task all: [:clean, *SPECS.keys.map(&:to_sym)]
end

namespace :generated do
  desc 'Запустить сгенерированные spec-файлы (после generate:all)'
  task spec: 'generate:all' do
    Dir['tmp/out/*/*_service_spec.rb'].each do |spec|
      sh_or_fail("bundle exec rspec -I lib -I #{File.dirname(spec)} #{spec}")
    end
  end

  desc 'rubocop на сгенерированном коде (только показать, не блокирует)'
  task lint: 'generate:all' do
    system('bundle exec rubocop --display-only-fail-level-offenses --fail-level error tmp/out/*/*.rb')
  end
end

namespace :golden do
  desc 'Обновить golden-файлы (осознанно! просмотреть diff перед коммитом)'
  task :update do
    sh_or_fail('bundle exec rspec spec/golden_spec.rb', { 'UPDATE_GOLDEN' => '1' })
    puts 'golden обновлены — проверьте `git diff spec/golden/`'
  end
end

desc 'Два прогона generate → одинаковые sha256 (детерминизм)'
task :determinism do
  sums = [1, 2].map do |run|
    dir = "tmp/determinism/#{run}"
    FileUtils.rm_rf(dir)
    SPECS.each do |name, path|
      sh_or_fail("bin/forge generate --spec #{path} --out #{dir}/#{name} --force --no-verify")
    end
    Dir["#{dir}/**/*"].select { |f| File.file?(f) }.sort.to_h do |f|
      [f.sub("#{dir}/", ''), Digest::SHA256.file(f).hexdigest]
    end
  end
  diff = sums[0].reject { |k, v| sums[1][k] == v }.keys
  abort "NOT DETERMINISTIC: #{diff.join(', ')}" unless diff.empty?
  puts "determinism ok (#{sums[0].size} files)"
end

desc 'Все гемы — только open-source лицензии'
task :licenses do
  require 'bundler'
  bad = Bundler.load.specs.reject do |spec|
    spec.licenses.empty? ? spec.name == 'bundler' : spec.licenses.any? { |l| ALLOWED_LICENSES.include?(l) }
  end
  bad.each { |s| puts "  #{s.name} #{s.version}: #{s.licenses.inspect}" }
  abort 'Гемы с неизвестной/недопустимой лицензией (см. выше)' unless bad.empty?
  puts "licenses ok (#{Bundler.load.specs.size} gems)"
end

namespace :guard do
  desc 'В lib/ нет знания о конкретном провайдере'
  task :vendor do
    words = %w[novapay cardpay swiftpay stripe adyen paystack paypal сбербанк]
    hits = Dir['lib/**/*.rb'].flat_map do |f|
      File.readlines(f).each_with_index.filter_map do |line, i|
        w = words.find { |word| line.downcase.include?(word) }
        "#{f}:#{i + 1}: #{w}" if w
      end
    end
    abort "Vendor-специфика в lib/:\n  #{hits.join("\n  ")}" unless hits.empty?
    puts 'guard:vendor ok'
  end
end

desc 'e2e: мок-сервер + сгенерированный сервис + webhook → approved'
task :e2e do
  SPECS.each_value { |path| sh_or_fail("bin/e2e #{path}") }
  sh_or_fail('bin/e2e spec/fixtures/oauth2_payout.yaml') # OAuth2 client_credentials: токен у мока
end

namespace :readme do
  desc 'Команды из блока «Быстрый старт» README выполняются с кодом 0'
  task :check do
    readme = File.read('README.md')
    block = readme[/## Быстрый старт.*?```(?:bash|sh)\n(.*?)```/m, 1]
    abort 'README: не найден блок ```bash под «## Быстрый старт»' unless block
    cmds = block.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') || l.start_with?('docker') }
    cmds.each { |cmd| sh_or_fail(cmd) }
    puts "readme:check ok (#{cmds.size} commands)"
  end
end

namespace :real do
  desc 'Скачать реальные спеки в examples/real/ (пропускает уже скачанные)'
  task :fetch do
    FileUtils.mkdir_p('examples/real')
    REAL_SPECS.each do |name, url|
      ext = File.extname(URI(url).path)
      target = "examples/real/#{name}#{ext}"
      next puts("  skip #{target}") if File.exist?(target)

      res = Net::HTTP.get_response(URI(url))
      abort "#{url}: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      File.binwrite(target, res.body)
      puts "  #{target} (#{res.body.bytesize / 1024} KB)"
    end
  end

  desc 'bin/forge analyze для каждой реальной спеки → examples/real/reports/<name>.{txt,json} + SUMMARY.md'
  task :analyze do
    FileUtils.mkdir_p('examples/real/reports')
    rows = REAL_SPECS.keys.map do |name|
      file = Dir["examples/real/#{name}.*"].first
      next "| #{name} | — | missing (rake real:fetch) |" unless file

      flags = REAL_FLAGS.fetch(name, [])
      text, status = Open3.capture2e('bin/forge', 'analyze', '--spec', file, *flags)
      File.write("examples/real/reports/#{name}.txt", text)
      json, = Open3.capture2e('bin/forge', 'analyze', '--spec', file, '--format', 'json', *flags)
      File.write("examples/real/reports/#{name}.json", json)
      "| #{name} | #{flags.join(' ')} | exit #{status.exitstatus} | #{text[/Done: .*/] || text.lines.first&.strip} |"
    end
    header = "# Реальные спеки — сводка `rake real:analyze`\n\n| Спека | Флаги | Код | Итог |\n|---|---|---|---|\n"
    summary = "#{header}#{rows.join("\n")}\n"
    File.write('examples/real/reports/SUMMARY.md', summary)
    puts summary
  end

  desc 'rspec spec/real_specs_spec.rb (REAL=1)'
  task :spec do
    sh_or_fail('bundle exec rspec spec/real_specs_spec.rb', { 'REAL' => '1' })
  end
end

desc 'Реальные спеки: fetch → analyze → spec'
task real: %w[real:fetch real:analyze real:spec]

namespace :fuzz do
  desc 'Враждебные спеки, overrides, параметры формы и URL против веб-приложения (spec/fuzz/corpus)'
  task(:web) { ruby '-Ilib', 'spec/fuzz/web.rb' }

  desc 'Мутационный фаззинг конвейера (SEED=42 ROUNDS=100; красный — исключение вне Forge::Error)'
  task(:mutate) { ruby '-Ilib', 'spec/fuzz/mutate.rb' }

  desc 'Враждебные запросы к сгенерированным мок-серверам'
  task(:mock) { ruby '-Ilib', 'spec/fuzz/mock.rb' }
end

namespace :demo do
  desc 'Записать docs/demo.gif по docs/demo.tape (нужен vhs)'
  task(:gif) { sh 'vhs docs/demo.tape' }
end

desc 'Фаззинг: web + mutate + mock (падение или 5xx = красный)'
task fuzz: %w[fuzz:web fuzz:mutate fuzz:mock]

desc 'Локальная проверка карточки: lint + test + guard:vendor'
task check: %w[lint test guard:vendor]

desc 'Полный CI локально'
task ci: %w[check generate:all generated:spec determinism fuzz licenses readme:check]

task default: :check
