# Запись демо для README: `vhs docs/demo.tape` (или `rake demo:gif`) → docs/demo.gif.
# Фазы совпадают с нумерованным списком под гифкой в README («Демо: весь CLI»).
# Нужны: vhs, скачанный examples/real/stripe.json (`rake real:fetch`), свободный порт 4567.
Output docs/demo.gif

Set Shell bash
Set FontSize 13
Set Width 1280
Set Height 780
Set Padding 14
Set TypingSpeed 25ms
Set Framerate 15
Set Theme "Catppuccin Mocha"

Hide
Type "export PS1='$ ' && rm -rf output tmp/demo && mkdir -p tmp/demo && clear" Enter
Show

# 1. Команды CLI
Type "bin/forge version && bin/forge help" Enter
Sleep 4s

# 2. Анализ: роли с confidence, auth, статусы, ошибки, webhook + подпись, сумма, WARN с подсказками
Type "clear" Enter
Type "bin/forge analyze --spec examples/specs/novapay.yaml" Enter
Sleep 6s

# 3. Тот же отчёт в JSON — для CI и веб-интерфейса
Type "clear" Enter
Type "bin/forge analyze --spec examples/specs/novapay.yaml --format json | head -32" Enter
Sleep 4s

# 4. Генерация командой из ТЗ: прогресс, 7 файлов, ruby -c + rspec сгенерированного
Type "clear" Enter
Type "bin/integrate --spec provider_api.yaml --provider novapay --lang ruby" Enter
Sleep 6s

# 5. Что получилось: файлы и исчерпывающий гайд интеграции
Type "clear" Enter
Type "ls output/novapay && sed -n '1,40p' output/novapay/INTEGRATION.md" Enter
Sleep 6s

# 6. Фикстуры: запросы, ответы, webhook с ожидаемыми статусами операции
Type "clear" Enter
Type "sed -n '1,34p' output/novapay/fixtures.json" Enter
Sleep 4s

# 7. Сгенерированный RSpec — доказательство, что сервис работает (WebMock + фикстуры)
Type "clear" Enter
Type "bundle exec rspec -I lib -I output/novapay output/novapay/novapay_service_spec.rb" Enter
Sleep 4s

# 8. Мок-сервер провайдера из той же спеки: создать выплату, статус, симулировать событие, состояние
Hide
Type `ruby -rjson -e 'print JSON.parse(File.read("output/novapay/fixtures.json"))["create_request"]["request"].to_json' > tmp/demo/req.json` Enter
Show
Type "clear" Enter
Type "bin/forge mock --spec examples/specs/novapay.yaml --port 4567 --out tmp/demo/mock &" Enter
Sleep 4s
Type `curl -s -X POST localhost:4567/payouts -H 'X-API-Key: test-key' -H 'Content-Type: application/json' -d @tmp/demo/req.json; echo` Enter
Sleep 2s
Type `curl -s localhost:4567/payouts/novapay_1 -H 'X-API-Key: test-key'; echo` Enter
Sleep 2s
Type `curl -s -X POST localhost:4567/_simulate/novapay_1/payout.completed; echo; curl -s localhost:4567/_state; echo` Enter
Sleep 4s
Type "kill %1" Enter
Sleep 1s

# 9. e2e: мок + сгенерированный сервис + подписанный webhook → approved
Type "clear" Enter
Type "bin/e2e examples/specs/novapay.yaml" Enter
Sleep 5s

# 10. e2e на других схемах: подпись t=…,v1=… (SwiftPay) и OAuth2 client_credentials (токен у мока)
Type "clear" Enter
Type "bin/e2e examples/specs/swiftpay.json | tail -3; bin/e2e spec/fixtures/oauth2_payout.yaml | tail -3" Enter
Sleep 6s

# 11. overrides закрывают WARN: --strict даёт exit 0
Type "clear" Enter
Type `bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --out tmp/demo/cardpay --force --strict --no-verify | tail -4; echo "exit: ${PIPESTATUS[0]}"` Enter
Sleep 5s

# 12. Честные ошибки: циклический $ref (exit 1 с pointer), pay-in спека без create (exit 2 с подсказкой)
Type `bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo "exit: $?"` Enter
Sleep 4s
Type `bin/forge generate --spec examples/payin/kaspi.yaml --out tmp/demo/kaspi; echo "exit: $?"` Enter
Sleep 5s

# 13. Реальная спека (Stripe, 594 эндпоинта): --include-paths, те же правила, без привязки к провайдеру
Type "clear" Enter
Type `bin/forge analyze --spec examples/real/stripe.json --include-paths '/v1/payouts*' | grep -E '^Parsing|^  (create|status|cancel) |^Auth|^Statuses|^Amount|^Done'` Enter
Sleep 7s
