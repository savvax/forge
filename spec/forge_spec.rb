# frozen_string_literal: true

RSpec.describe Forge do
  it 'has version 1.0.0' do
    expect(Forge::VERSION).to eq('1.0.0')
  end

  describe Forge::Error do
    it 'carries pointer, hint and file' do
      err = Forge::SpecError.new('bad ref', pointer: '#/a', hint: 'fix it', file: 'x.yaml')
      expect(err.message).to eq("bad ref at #/a in x.yaml\n  hint: fix it")
      expect(err.pointer).to eq('#/a')
      expect(err.hint).to eq('fix it')
      expect(err.file).to eq('x.yaml')
    end

    it 'keeps a bare message when no context is given' do
      expect(Forge::GenerationError.new('nothing to do').message).to eq('nothing to do')
    end

    it 'defines four subclasses with exit codes' do
      expect(Forge::SpecError.exit_code).to eq(1)
      expect(Forge::UnsupportedError.exit_code).to eq(1)
      expect(Forge::GenerationError.exit_code).to eq(2)
      expect(Forge::VerificationError.exit_code).to eq(3)
    end
  end
end
