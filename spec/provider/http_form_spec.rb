# frozen_string_literal: true

require 'provider'

RSpec.describe Provider::HttpClient do
  it 'flattens nested form bodies as parent[child]' do
    encoded = 'amount=1&destination%5Baccount%5D=acc&destination%5Bbank%5D%5Bcode%5D=b1'
    stub = stub_request(:post, 'https://api.test.example/v1/x').with(body: encoded).to_return(status: 200, body: '{}')
    described_class.new.post('https://api.test.example/v1/x',
                             form: { amount: 1, destination: { account: 'acc', bank: { code: 'b1' } } })
    expect(stub).to have_been_requested
  end
end
