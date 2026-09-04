# frozen_string_literal: true

# Элементы эталона ТЗ (spec/reference/novapay/*) присутствуют в сгенерированном NovaPay.
RSpec.describe 'reference (NovaPay from the task statement)' do
  let(:plan) { plan_for('examples/specs/novapay.yaml') }
  let(:service) { Forge::Renderers::Service.new(plan).render }

  it 'contains every element of the reference service' do
    expect(service).to include(
      'class NovapayService < BaseService',
      "BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')",
      'def create_request', 'def fetch_status', 'def process_callback', 'def check_conditions',
      'def build_payout_payload', 'def verify_signature!',
      'rescue Provider::RateLimitError', 'rescue Provider::UnauthorizedError',
      "failure(:too_many_requests, 'provider.rate_limit'", "failure(:unauthorized, 'provider.invalid_credentials')",
      "failure(:unprocessable_entity, 'amount_too_low')",
      "'X-NovaPay-Signature'", "'payout.completed'", "'payout.failed'", 'approve_operation', 'reject_operation',
      "payload.dig('error', 'code')", 'operation.payout_requisite', "'sbp'", 'bank_code', 'bank_name', "'phone'"
    )
  end

  it 'has the same STATUS_MAP and ERROR_MAP rows plus 404' do
    reference = File.read('spec/reference/novapay/novapay_service.rb')
    reference.scan(/^\s+'(\w+)'\s+=> '(\w+)'/).each { |k, v| expect(plan.status_map[k]).to eq(v) }
    reference.scan(/^\s+(\d{3}) => '(\w+)'/).each { |k, v| expect(plan.error_map[k.to_i][:internal_code]).to eq(v) }
    expect(plan.error_map[404][:internal_code]).to eq('not_found')
  end
end
