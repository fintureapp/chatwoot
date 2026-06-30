require 'rails_helper'

RSpec.describe Captain::AssistantStatsBuilder do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  describe '#metrics' do
    # Two conversations handled in the current 30-day window, one in the previous.
    let(:current_convo_a) { create(:conversation, account: account, inbox: inbox) }
    let(:current_convo_b) { create(:conversation, account: account, inbox: inbox) }
    let(:previous_convo) { create(:conversation, account: account, inbox: inbox) }

    before do
      [current_convo_a, current_convo_b].each do |conversation|
        create(:message, account: account, inbox: inbox, conversation: conversation,
                         sender: assistant, message_type: :outgoing, private: false, created_at: 5.days.ago)
      end
      create(:message, account: account, inbox: inbox, conversation: previous_convo,
                       sender: assistant, message_type: :outgoing, private: false, created_at: 45.days.ago)
    end

    it 'returns every metric for the current and previous window' do
      metrics = described_class.new(assistant, '30').metrics

      expect(metrics.keys).to contain_exactly(
        :conversations_handled, :auto_resolution_rate, :handoff_rate,
        :hours_saved, :reopen_rate, :conversation_depth, :knowledge
      )
      expect(metrics[:conversations_handled]).to include(:current, :previous, :trend)
    end

    it 'counts distinct handled conversations per window and the percent trend' do
      handled = described_class.new(assistant, '30').metrics[:conversations_handled]

      expect(handled[:current]).to eq(2)
      expect(handled[:previous]).to eq(1)
      expect(handled[:trend]).to eq(100.0)
    end

    it 'derives auto-resolution and handoff rates from reporting events on the handled set' do
      create(:reporting_event, account: account, conversation: current_convo_a,
                               name: 'conversation_captain_inference_resolved')
      create(:reporting_event, account: account, conversation: current_convo_b,
                               name: 'conversation_captain_inference_handoff')

      metrics = described_class.new(assistant, '30').metrics

      expect(metrics[:auto_resolution_rate][:current]).to eq(50.0)
      expect(metrics[:handoff_rate][:current]).to eq(50.0)
    end

    it 'computes conversation depth as public replies per handled conversation' do
      depth = described_class.new(assistant, '30').metrics[:conversation_depth]

      # 2 public outgoing replies across 2 distinct conversations in the current window.
      expect(depth[:current]).to eq(1.0)
    end

    it 'ignores private notes and incoming messages when counting public replies' do
      create(:message, account: account, inbox: inbox, conversation: current_convo_a,
                       sender: assistant, message_type: :outgoing, private: true, created_at: 5.days.ago)

      depth = described_class.new(assistant, '30').metrics[:conversation_depth]

      expect(depth[:current]).to eq(1.0)
    end
  end

  describe '#metrics knowledge' do
    before do
      create_list(:captain_assistant_response, 3, assistant: assistant, account: account, status: :approved)
      create(:captain_assistant_response, assistant: assistant, account: account, status: :pending)
      create_list(:captain_document, 2, assistant: assistant, account: account)
    end

    it 'returns approved, pending, document counts and coverage' do
      knowledge = described_class.new(assistant, '30').metrics[:knowledge]

      expect(knowledge).to eq(approved: 3, pending: 1, documents: 2, coverage: 75)
    end

    it 'reports zero coverage when there are no responses' do
      Captain::AssistantResponse.where(assistant: assistant).delete_all

      knowledge = described_class.new(assistant, '30').metrics[:knowledge]

      expect(knowledge[:coverage]).to eq(0)
    end
  end

  describe '#period' do
    it 'labels a day range and exposes its bounds' do
      period = described_class.new(assistant, '30').period

      expect(period[:label]).to eq('the last 30 days')
      expect(period[:starts_on]).to eq(30.days.ago.to_date)
      expect(period[:ends_on]).to eq(Time.zone.today)
    end

    it 'labels the this_month range' do
      expect(described_class.new(assistant, 'this_month').period[:label]).to eq('this month')
    end

    it 'labels the last_month range' do
      expect(described_class.new(assistant, 'last_month').period[:label]).to eq('last month')
    end
  end
end
