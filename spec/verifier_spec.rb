# frozen_string_literal: true

RSpec.describe Forge::Verifier do
  it 'passes valid files and rejects invalid ones' do
    File.write('tmp/ok.rb', "x = 1\nputs x\n")
    File.write('tmp/bad.rb', "def x(\n")
    expect(described_class.syntax!(['tmp/ok.rb'])).to eq(['tmp/ok.rb'])
    expect { described_class.syntax!(['tmp/bad.rb']) }
      .to raise_error(Forge::VerificationError) { |e| expect(e.message).to include('syntax error', 'tmp/bad.rb', 'hint:') }
  end

  it 'runs a generated spec and reports failures' do
    File.write('tmp/green_spec.rb', "RSpec.describe('g') { it { expect(1).to eq(1) } }\n")
    expect(described_class.rspec!('tmp/green_spec.rb')).to include('1 example, 0 failures')
    File.write('tmp/red_spec.rb', "RSpec.describe('r') { it { expect(1).to eq(2) } }\n")
    expect do
      described_class.rspec!('tmp/red_spec.rb')
    end.to raise_error(Forge::VerificationError, /generated spec failed/)
  end
end
