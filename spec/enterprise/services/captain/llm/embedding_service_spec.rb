require 'rails_helper'

RSpec.describe Captain::Llm::EmbeddingService, type: :service do
  def configure_embedding_model(value)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_EMBEDDING_MODEL').tap do |config|
      config.value = value
      config.locked = false
      config.save!
    end
  end

  describe '.embedding_model' do
    it 'uses the installation embedding model when configured' do
      configure_embedding_model('custom-embedding-model')

      expect(described_class.embedding_model).to eq('custom-embedding-model')
    end

    it 'falls back to the default embedding model when the installation value is blank' do
      configure_embedding_model('')

      expect(described_class.embedding_model).to eq(LlmConstants::DEFAULT_EMBEDDING_MODEL)
    end
  end

  describe '#get_embedding' do
    let(:account) { create(:account) }
    let(:mock_context) { instance_double(RubyLLM::Context) }
    let(:embedding_response) { double('embedding_response', vectors: [0.1, 0.2]) } # rubocop:disable RSpec/VerifiedDoubles

    before do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    end

    it 'sends the installation embedding model to RubyLLM' do
      configure_embedding_model('custom-embedding-model')

      expect(Llm::Config).to receive(:with_provider).with(provider: 'openai').and_yield(mock_context)
      expect(mock_context).to receive(:embed).with(
        'search text',
        model: 'custom-embedding-model',
        provider: 'openai',
        assume_model_exists: true
      ).and_return(embedding_response)

      expect(described_class.new(account_id: account.id).get_embedding('search text')).to eq([0.1, 0.2])
    end

    it 'requires OpenAI configuration even when another LLM provider is selected' do
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy
      create(:installation_config, name: 'CAPTAIN_LLM_PROVIDER', value: 'openrouter')
      create(:installation_config, name: 'CAPTAIN_LLM_OPENROUTER_API_KEY', value: 'openrouter-key')

      expect(Llm::Config).not_to receive(:with_provider)

      expect { described_class.new(account_id: account.id).get_embedding('search text') }
        .to raise_error(described_class::EmbeddingsError, 'OpenAI configuration is required for embeddings.')
    end
  end
end
