require 'rails_helper'

describe Conversations::AssignmentService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:captain_assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#perform' do
    context 'when assignee_id is blank' do
      before do
        conversation.update!(assignee_agent_bot: agent_bot, assignee_captain_assistant: captain_assistant)
      end

      it 'clears human and AI assignees' do
        described_class.new(conversation: conversation, assignee_id: nil).perform

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.assignee_captain_assistant_id).to be_nil
      end
    end

    context 'when assigning a user' do
      before do
        conversation.update!(assignee_captain_assistant: captain_assistant, assignee: nil, status: :pending)
      end

      it 'sets the agent and clears AI ownership' do
        result = described_class.new(conversation: conversation, assignee_id: agent.id).perform

        conversation.reload
        expect(result).to eq(agent)
        expect(conversation.assignee_id).to eq(agent.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.assignee_captain_assistant_id).to be_nil
        expect(conversation.status).to eq('open')
      end
    end

    context 'when assigning an agent bot' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: agent_bot.id,
          assignee_type: 'AgentBot'
        )
      end

      it 'sets the agent bot and clears other assignees' do
        conversation.update!(assignee_agent_bot: nil, assignee_captain_assistant: captain_assistant)

        result = service.perform

        conversation.reload
        expect(result).to eq(agent_bot)
        expect(conversation.assignee_agent_bot_id).to eq(agent_bot.id)
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_captain_assistant_id).to be_nil
      end
    end

    context 'when assigning a Captain assistant' do
      let(:service) do
        described_class.new(
          conversation: conversation,
          assignee_id: captain_assistant.id,
          assignee_type: 'CaptainAssistant'
        )
      end

      it 'sets the Captain assistant, clears other assignees, and marks pending' do
        conversation.update!(assignee_agent_bot: agent_bot, status: :resolved)

        result = service.perform

        conversation.reload
        expect(result).to eq(captain_assistant)
        expect(conversation.assignee_captain_assistant_id).to eq(captain_assistant.id)
        expect(conversation.assignee_agent_bot_id).to be_nil
        expect(conversation.assignee_id).to be_nil
        expect(conversation.status).to eq('pending')
      end
    end
  end
end
