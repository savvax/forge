# frozen_string_literal: true

# expect(finding).to have_warning(:role_conflict, hint: /endpoints\./)
RSpec::Matchers.define :have_warning do |code, level: nil, hint: nil, message: nil|
  match do |finding|
    finding.warnings.any? do |w|
      w.code == code && (level.nil? || w.level == level) && (hint.nil? || w.hint.to_s.match?(hint)) &&
        (message.nil? || w.message.match?(message))
    end
  end

  failure_message do |finding|
    "expected warning #{code.inspect}, got: #{finding.warnings.map { |w| "#{w.level} #{w.code}: #{w.message}" }}"
  end
end
