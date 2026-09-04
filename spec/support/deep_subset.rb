# frozen_string_literal: true

# expect(ours).to deep_include(reference): каждый ключ/значение reference есть в ours (рекурсивно).
RSpec::Matchers.define :deep_include do |expected|
  match { |actual| deep_subset?(expected, actual) }

  def deep_subset?(expected, actual)
    case expected
    when Hash then hash_subset?(expected, actual)
    when Array then actual.is_a?(Array) && expected.each_with_index.all? { |v, i| deep_subset?(v, actual[i]) }
    else expected == actual
    end
  end

  def hash_subset?(expected, actual)
    actual.is_a?(Hash) && expected.all? { |k, v| actual.key?(k) && deep_subset?(v, actual[k]) }
  end

  failure_message { |actual| "expected #{actual.inspect[0, 300]} to deep-include #{expected.inspect[0, 300]}" }
end
