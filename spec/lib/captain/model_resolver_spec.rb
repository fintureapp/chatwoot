require 'rails_helper'

RSpec.describe Captain::ModelResolver do
  let(:default_model) { 'gpt-4.1-mini' }

  # Upserts an installation config so a `before` value can be overridden within an example.
  def set_installation_config(name, value)
    config = InstallationConfig.find_or_initialize_by(name: name)
    config.value = value
    config.save!
    config
  end

  describe '.resolve' do
    it 'returns the provided default when nothing is configured' do
      expect(described_class.resolve('assistant', default: default_model)).to eq(default_model)
    end

    context 'with the global installation model (CAPTAIN_OPEN_AI_MODEL)' do
      before { set_installation_config('CAPTAIN_OPEN_AI_MODEL', 'gpt-5.1') }

      it 'is used in preference to the default' do
        expect(described_class.resolve('assistant', default: default_model)).to eq('gpt-5.1')
      end

      it 'is ignored when apply_global is false' do
        expect(described_class.resolve('assistant', default: default_model, apply_global: false)).to eq(default_model)
      end

      it 'is ignored when blank' do
        set_installation_config('CAPTAIN_OPEN_AI_MODEL', '')
        expect(described_class.resolve('assistant', default: default_model)).to eq(default_model)
      end
    end

    context 'with an installation per-feature override (CAPTAIN_FEATURE_MODELS)' do
      before do
        set_installation_config('CAPTAIN_OPEN_AI_MODEL', 'gpt-5.1')
        set_installation_config('CAPTAIN_FEATURE_MODELS', { 'assistant' => 'gpt-5.2', 'summary' => '' })
      end

      it 'is preferred over the global model' do
        expect(described_class.resolve('assistant', default: default_model)).to eq('gpt-5.2')
      end

      it 'applies even when apply_global is false' do
        expect(described_class.resolve('assistant', default: default_model, apply_global: false)).to eq('gpt-5.2')
      end

      it 'falls through to the global model for a feature with a blank override' do
        expect(described_class.resolve('summary', default: default_model)).to eq('gpt-5.1')
      end

      it 'falls through to the global model for a feature not present in the hash' do
        expect(described_class.resolve('copilot', default: default_model)).to eq('gpt-5.1')
      end

      it 'ignores the override when the stored value is not a hash' do
        set_installation_config('CAPTAIN_FEATURE_MODELS', 'gpt-5.2')
        expect(described_class.resolve('assistant', default: default_model)).to eq('gpt-5.1')
      end
    end

    context 'with an account level override' do
      let(:account) { create(:account, captain_models: { 'assistant' => 'gpt-5.2' }) }

      before do
        set_installation_config('CAPTAIN_OPEN_AI_MODEL', 'gpt-5.1')
        set_installation_config('CAPTAIN_FEATURE_MODELS', { 'assistant' => 'gpt-5-mini' })
      end

      it 'wins over the installation and global overrides' do
        expect(described_class.resolve('assistant', account: account, default: default_model)).to eq('gpt-5.2')
      end

      it 'falls through to the installation override when the account has none for the feature' do
        expect(described_class.resolve('copilot', account: account, default: default_model)).to eq('gpt-5.1')
      end

      it 'is ignored when the account does not support model overrides' do
        # Account override would be 'gpt-5.2'; an unsupported account falls through to the
        # installation per-feature override instead.
        expect(described_class.resolve('assistant', account: Object.new, default: default_model)).to eq('gpt-5-mini')
      end

      it 'is ignored when the account is nil' do
        expect(described_class.resolve('assistant', account: nil, default: default_model)).to eq('gpt-5-mini')
      end
    end

    context 'when the feature is blank' do
      before do
        set_installation_config('CAPTAIN_OPEN_AI_MODEL', 'gpt-5.1')
        set_installation_config('CAPTAIN_FEATURE_MODELS', { 'assistant' => 'gpt-5.2' })
      end

      it 'skips the feature-keyed overrides but still applies the global model' do
        expect(described_class.resolve(nil, default: default_model)).to eq('gpt-5.1')
      end

      it 'returns the default when the global is not applied' do
        expect(described_class.resolve('', default: default_model, apply_global: false)).to eq(default_model)
      end
    end
  end
end
