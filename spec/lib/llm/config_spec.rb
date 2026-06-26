# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.provider_options' do
    it 'returns configured providers supported by RubyLLM' do
      expect(described_class.provider_options).to include(
        'openai' => 'OpenAI',
        'anthropic' => 'Anthropic',
        'gemini' => 'Gemini',
        'openrouter' => 'OpenRouter'
      )
    end
  end

  describe '.provider_config_keys' do
    it 'includes dynamic RubyLLM provider credential keys' do
      expect(described_class.provider_config_keys).to include(
        'CAPTAIN_LLM_PROVIDER',
        'CAPTAIN_LLM_OPENROUTER_API_KEY'
      )
    end
  end

  describe '.provider_configured?' do
    it 'uses dynamic provider requirements' do
      create(:installation_config, name: 'CAPTAIN_LLM_OPENROUTER_API_KEY', value: 'openrouter-key')

      expect(described_class.provider_configured?('openrouter')).to be true
    end
  end

  describe '.api_base_for' do
    it 'normalizes OpenAI-compatible endpoints to the v1 base' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://proxy.example.com/chat/completions')

      expect(described_class.api_base_for('openai')).to eq('https://proxy.example.com/v1')
    end

    it 'keeps non-OpenAI provider endpoints unchanged except trailing slashes' do
      create(:installation_config, name: 'CAPTAIN_ANTHROPIC_API_BASE', value: 'https://anthropic.example.com/')

      expect(described_class.api_base_for('anthropic')).to eq('https://anthropic.example.com')
    end
  end

  describe '.supports_tools_and_schema?' do
    it 'allows tool and schema configuration only for OpenAI' do
      expect(described_class.supports_tools_and_schema?('openai')).to be true
      expect(described_class.supports_tools_and_schema?('anthropic')).to be false
    end
  end
end
