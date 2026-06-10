require 'rails_helper'

RSpec.describe Captain::Tools::SearchDocumentationService do
  let(:assistant) { create(:captain_assistant) }
  let(:service) { described_class.new(assistant) }
  let(:question) { 'How to create a new account?' }
  let(:answer) { 'You can create a new account by clicking on the Sign Up button.' }
  let(:external_link) { 'https://example.com/docs/create-account' }

  describe '#name' do
    it 'returns the correct service name' do
      expect(service.name).to eq('search_documentation')
    end
  end

  describe '#description' do
    it 'returns the service description' do
      expect(service.description).to eq('Search and retrieve documentation from knowledge base')
    end
  end

  describe '#parameters' do
    it 'defines query parameter' do
      expect(service.parameters.keys).to contain_exactly(:query)
    end
  end

  describe '#execute' do
    let(:documentation_search_service) { instance_double(Captain::DocumentationSearchService) }
    let(:documentation_sufficiency_service) { instance_double(Captain::Llm::DocumentationSufficiencyService) }
    let(:translate_query_service) { instance_double(Captain::Llm::TranslateQueryService) }
    let!(:response) do
      create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: question,
        answer: answer,
        status: 'approved'
      )
    end

    let(:documentable) { create(:captain_document, external_link: external_link) }
    let(:recorded_searches) { [] }
    let(:service) { described_class.new(assistant, on_search: ->(search) { recorded_searches << search }) }
    let(:match) do
      Captain::AssistantResponse::SearchMatch.new(
        response: response,
        semantic_distance: 0.2
      )
    end

    def search_result(matches:)
      {
        query: question,
        queries: [question],
        matches: matches
      }
    end

    before do
      allow(Captain::Llm::TranslateQueryService).to receive(:new).and_return(translate_query_service)
      allow(translate_query_service).to receive(:translate).and_return(question)
      allow(Captain::DocumentationSearchService).to receive(:new)
        .with(scope: anything, account_id: assistant.account_id)
        .and_return(documentation_search_service)
    end

    context 'when matching responses exist' do
      it 'returns formatted responses for the search query' do
        response.update(documentable: documentable)
        allow(documentation_search_service).to receive(:search).with(question).and_return(
          search_result(matches: [match])
        )

        result = service.execute(query: question)

        expect(result).to include(question)
        expect(result).to include(answer)
        expect(result).to include(external_link)
        expect(recorded_searches.first[:matches].first[:question]).to eq(question)
      end
    end

    context 'when no matching responses exist' do
      it 'returns a bounded no-results instruction' do
        allow(documentation_search_service).to receive(:search).with(question).and_return(
          search_result(matches: [])
        )

        result = service.execute(query: question)

        expect(result).to include('No documentation found for the given query')
        expect(result).to include('No documentation matched this query')
      end
    end

    context 'when documentation sufficiency gate is enabled' do
      let(:conversation) { create(:conversation, account: assistant.account) }
      let(:message_history) { [{ role: 'user', content: 'Who is your mascot?' }] }
      let(:service) do
        described_class.new(
          assistant,
          on_search: ->(search) { recorded_searches << search },
          message_history: -> { message_history },
          conversation: conversation
        )
      end

      before do
        assistant.update!(config: assistant.config.merge('documentation_sufficiency_gate_enabled' => true))
        allow(Captain::Llm::DocumentationSufficiencyService).to receive(:new).with(
          assistant: assistant,
          conversation: conversation
        ).and_return(documentation_sufficiency_service)
      end

      it 'returns insufficient documentation support to the final assistant generation' do
        allow(documentation_search_service).to receive(:search).with(question).and_return(
          search_result(matches: [match])
        )
        allow(documentation_sufficiency_service).to receive(:evaluate).with(
          message_history: message_history,
          documentation_searches: [
            hash_including(
              query: question,
              matches: [hash_including(question: question, answer: answer)]
            )
          ]
        ).and_return({ 'decision' => 'insufficient', 'model' => 'gpt-5.4-mini' })

        result = service.execute(query: question)

        expect(result).to include('Documentation support: insufficient')
        expect(result).to include('Do not answer the factual question from these results')
        expect(recorded_searches.first[:documentation_sufficiency]).to include('decision' => 'insufficient')
      end
    end
  end
end
