# app/services/provider/novapay_service.rb
# Эталон из описания кейса (описание.docx). Не редактировать: spec/reference_spec.rb проверяет,
# что элементы этого файла присутствуют в сгенерированном сервисе.

class Provider
  class NovapayService < BaseService
    BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')

    def create_request(operation, request_method = 'create')
      payload = build_payout_payload(operation)
      response = client.post("#{BASE_URL}/payouts", json: payload, headers: auth_headers)
      parse_create_response(operation, response)
    rescue Provider::RateLimitError
      failure(:too_many_requests, 'provider.rate_limit')
    rescue Provider::UnauthorizedError
      failure(:unauthorized, 'provider.invalid_credentials')
    end

    def fetch_status(operation)
      response = client.get("#{BASE_URL}/payouts/#{operation.provider_operation_id}")
      map_status(response.body['status'])
    end

    def process_callback(payload)
      verify_signature!(payload) # HMAC-SHA256 из X-NovaPay-Signature
      case payload['event']
      when 'payout.completed' then approve_operation(payload['payout_id'])
      when 'payout.failed'    then reject_operation(payload['payout_id'], payload.dig('error', 'code'))
      else failure(:unprocessable_entity, 'unknown_event')
      end
    end

    def check_conditions(operation, request_method)
      base_result = super
      return base_result if base_result.failed?
      return failure(:unprocessable_entity, 'amount_too_low') if operation.amount < 1000
      success
    end

    private

    def build_payout_payload(operation)
      {
        amount: (operation.amount * 100).to_i,
        currency: 'RUB',
        external_id: operation.id,
        recipient: {
          type: 'sbp',
          phone: operation.payout_requisite.dig('sbp', 'phone'),
          bank_code: operation.payout_requisite.dig('sbp', 'bank_code'),
          bank_name: operation.payout_requisite.dig('sbp', 'bank_name')
        }
      }
    end

    STATUS_MAP = {
      'pending'    => 'in_progress',
      'processing' => 'in_progress',
      'completed'  => 'approved',
      'failed'     => 'rejected',
      'cancelled'  => 'rejected'
    }.freeze

    ERROR_MAP = {
      400 => 'validation_error',
      401 => 'invalid_credentials',
      402 => 'insufficient_balance',
      422 => 'validation_error',
      429 => 'rate_limit',
      500 => 'internal_error'
    }.freeze
  end
end
