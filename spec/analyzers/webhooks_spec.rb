# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Webhooks do
  let(:rules) { Forge::Rules.load }

  def webhooks_for(spec)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    described_class.new(spec, rules, roles: roles.value).call
  end

  def for_file(file) = webhooks_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  it 'novapay: signature from header, sha256, raw body, hex assumed' do
    finding = for_file('examples/specs/novapay.yaml')
    expect(finding.value[:signature]).to eq(header: 'X-NovaPay-Signature', algorithm: 'sha256', encoding: 'hex',
                                            payload: 'raw_body', secret_key: 'callback_secret')
    expect(finding.value).to include(source: :paths, event_field: 'event', id_field: ['payout_id'],
                                     status_field: ['status'])
    expect(finding.value[:event_map]).to eq('payout.completed' => 'approved', 'payout.failed' => 'rejected',
                                            'payout.processing' => 'in_progress', 'payout.cancelled' => 'rejected')
    expect(finding.confidence).to eq(0.85)
    expect(finding.warnings.map(&:code)).to eq([:signature_encoding_assumed])
  end

  it 'cardpay: callbacks, sha512/base64, payload assumed, on_hold unmapped' do
    finding = for_file('examples/specs/cardpay.yaml')
    expect(finding.value[:signature]).to include(header: 'X-Signature', algorithm: 'sha512', encoding: 'base64',
                                                 payload: 'raw_body')
    expect(finding.value).to include(source: :callbacks, event_field: 'type', id_field: %w[data transfer_id],
                                     status_field: %w[data state])
    expect(finding.value[:event_map]).to eq('transfer.settled' => 'approved', 'transfer.declined' => 'rejected')
    expect(finding).to have_warning(:signature_payload_assumed, hint: /webhook\.signature_payload/)
    expect(finding).to have_warning(:unmapped_event, message: /transfer\.on_hold/,
                                                     hint: /statuses\.on_hold|events\.transfer\.on_hold/)
  end

  it 'swiftpay: top-level webhooks, timestamp signature unsupported, no event enum' do
    finding = for_file('examples/specs/swiftpay.json')
    expect(finding.value).to include(source: :webhooks, event_map: {}, status_field: %w[data status],
                                     id_field: %w[data payment_id])
    expect(finding.value[:signature]).to include(header: 'Swift-Signature', encoding: 'hex', payload: 'raw_body')
    expect(finding).to have_warning(:signature_with_timestamp, level: :unsupported)
    expect(finding.warnings.map(&:level)).not_to include(:warn)
  end

  it 'no webhook → WARN no_webhook and empty value' do
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                               'operationId' => 'createPayout',
                               'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
                               'responses' => { '201' => { 'description' => 'ok' } }
                             } } }))
    finding = webhooks_for(spec)
    expect(finding.value[:endpoint]).to be_nil
    expect(finding).to have_warning(:no_webhook)
  end

  it 'webhook without signature header → WARN signature_not_found' do
    spec = ir_for(build_spec(paths: { '/webhooks' => { 'post' => {
                               'operationId' => 'hook', 'security' => [],
                               'requestBody' => body_json({ 'id' => { 'type' => 'string' },
                                                            'status' => { 'type' => 'string' } }),
                               'responses' => { '200' => { 'description' => 'ok' } }
                             } } }))
    finding = webhooks_for(spec)
    expect(finding.value[:signature][:header]).to be_nil
    expect(finding).to have_warning(:signature_not_found)
  end
end
