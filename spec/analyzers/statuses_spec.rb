# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Statuses do
  let(:rules) { Forge::Rules.load }

  def statuses_for(spec)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    described_class.new(spec, rules, roles: roles.value).call
  end

  def for_file(file) = statuses_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  def spec_with_response(properties)
    ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                        'operationId' => 'createPayout', 'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
                        'responses' => response_json(201, properties)
                      } } }))
  end

  it 'novapay: enum status field, 5 mapped, id at root' do
    finding = for_file('examples/specs/novapay.yaml')
    expect(finding.value).to include(field_path: ['status'], unmapped: [], response_id_path: ['id'])
    expect(finding.value[:map]).to eq('pending' => 'in_progress', 'processing' => 'in_progress',
                                      'completed' => 'approved', 'failed' => 'rejected', 'cancelled' => 'rejected')
    expect(finding.confidence).to eq(0.95)
    expect(finding.warnings).to eq([])
  end

  it 'cardpay: data.state with ON_HOLD unmapped, id data.transfer_id 0.8' do
    finding = for_file('examples/specs/cardpay.yaml')
    expect(finding.value).to include(field_path: %w[data state], unmapped: ['ON_HOLD'],
                                     response_id_path: %w[data transfer_id], response_id_confidence: 0.8)
    expect(finding.value[:map]).to include('NEW' => 'in_progress', 'SUCCESS' => 'approved', 'DECLINED' => 'rejected')
    expect(finding).to have_warning(:unmapped_status, hint: /statuses\.ON_HOLD: in_progress\|approved\|rejected/)
  end

  it 'swiftpay: PENDING_APPROVAL and RETURNED unmapped' do
    finding = for_file('examples/specs/swiftpay.json')
    expect(finding.value[:unmapped]).to eq(%w[PENDING_APPROVAL RETURNED])
    expect(finding.value[:response_id_path]).to eq(['payment_id'])
    expect(finding.warnings.count { |w| w.code == :unmapped_status }).to eq(2)
  end

  it 'reads statuses from description when there is no enum' do
    status = { 'type' => 'string', 'description' => 'One of `paid`, `pending`, `in_transit`.' }
    finding = statuses_for(spec_with_response('id' => { 'type' => 'string' }, 'status' => status))
    expect(finding.value[:map]).to eq('paid' => 'approved', 'pending' => 'in_progress', 'in_transit' => 'in_progress')
    expect(finding.confidence).to eq(0.6)
    expect(finding).to have_warning(:status_from_description)
  end

  it 'normalises camelCase values and reports unmapped' do
    finding = statuses_for(spec_with_response('status' => { 'type' => 'string', 'enum' => %w[approvalPending done] }))
    expect(finding.value[:unmapped]).to eq(['approvalPending'])
    expect(finding.value[:map]).to eq('done' => 'approved')
    expect(finding).to have_warning(:unmapped_status, message: /approval_pending/)
    expect(finding).to have_warning(:response_id_not_found)
  end

  it 'warns when no status field is found' do
    finding = statuses_for(spec_with_response('id' => { 'type' => 'string' }))
    expect(finding.value[:field_path]).to eq(['status'])
    expect(finding.value[:map]).to eq({})
    expect(finding).to have_warning(:status_field_not_found)
  end
end
