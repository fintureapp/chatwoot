# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.provider_options' do
    it 'returns configured providers supported by RubyLLM' do
      expect(described_class.provider_options).to include(
        'openai' => 'OpenAI',
        'anthropic' => 'Anthropic',
        'gemini' => 'Gemini'
      )
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
