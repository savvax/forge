# Запись демо для README: `vhs docs/demo.tape` (или `rake demo:gif`) → docs/demo.gif + docs/demo.mp4.
# Фазы совпадают с нумерованным списком под гифкой в README («Демо за 90 секунд»).
Output docs/demo.gif
Output docs/demo.mp4

Set Shell bash
Set FontSize 13
Set Width 1280
Set Height 780
Set Padding 14
Set TypingSpeed 30ms
Set Framerate 15
Set Theme "Catppuccin Mocha"

Hide
Type "export PS1='$ ' && rm -rf output tmp/demo && clear" Enter
Show

# 1. Анализ: роли с confidence, auth, статусы, ошибки, webhook + подпись, сумма, WARN с подсказками
Type "bin/forge analyze --spec examples/specs/novapay.yaml" Enter
Sleep 6s

# 2. Генерация командой из ТЗ: прогресс-вывод, 7 файлов, ruby -c + rspec сгенерированного
Type "clear" Enter
Type "bin/integrate --spec provider_api.yaml --provider novapay --lang ruby" Enter
Sleep 6s

# 3. Что получилось: файлы и гайд интеграции
Type "clear" Enter
Type "ls output/novapay && sed -n '1,40p' output/novapay/INTEGRATION.md" Enter
Sleep 6s

# 4. Сгенерированный RSpec — доказательство, что сервис работает (WebMock + фикстуры)
Type "clear" Enter
Type "bundle exec rspec -I lib -I output/novapay output/novapay/novapay_service_spec.rb" Enter
Sleep 4s

# 5. e2e: мок из той же спеки + сервис + подписанный webhook → approved
Type "clear" Enter
Type "bin/e2e examples/specs/novapay.yaml" Enter
Sleep 5s

# 6. overrides закрывают WARN: --strict даёт exit 0
Type "clear" Enter
Type `bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --out tmp/demo/cardpay --force --strict --no-verify | tail -4; echo "exit: ${PIPESTATUS[0]}"` Enter
Sleep 5s

# 7. Битая спека: ошибка с JSON-pointer и подсказкой, exit 1, без стектрейса
Type `bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo "exit: $?"` Enter
Sleep 5s

# 8. Реальная спека (Stripe, 6 МБ): те же правила, роли и OAuth/basic — без привязки к провайдеру
Type "clear" Enter
Type `bin/forge analyze --spec examples/real/stripe.json --include-paths '/v1/payouts*' | grep -E '^Parsing|^  (create|status|cancel) |^Auth|^Statuses|^Amount|^Done'` Enter
Sleep 7s
