require 'rails_helper'

RSpec.describe Captain::Llm::DocumentationSufficiencyService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { described_class.new(assistant: assistant, conversation: conversation) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_response) do
    instance_double(
      RubyLLM::Message,
      content: { 'decision' => 'sufficient' }
    )
  end

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#evaluate' do
    it 'uses the documentation support model instead of the global Captain model' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.5')

      expect(RubyLLM).to receive(:chat).with(model: 'gpt-5.4-mini').and_return(mock_chat)

      result = service.evaluate(
        message_history: [{ role: 'user', content: 'Who is your mascot?' }],
        documentation_searches: [
          {
            query: 'mascot',
            matches: [{ question: 'Who is the brand mascot?', answer: 'Robin the bird.' }]
          }
        ]
      )

      expect(result).to include('decision' => 'sufficient', 'model' => 'gpt-5.4-mini')
    end
  end
end
