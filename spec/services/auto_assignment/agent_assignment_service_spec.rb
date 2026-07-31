require 'rails_helper'

RSpec.describe AutoAssignment::AgentAssignmentService do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:inbox_members) { create_list(:inbox_member, 5, inbox: inbox) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:allowed_agent_ids) { inbox_members.map(&:user_id).map(&:to_s) }
  let(:online_users) do
    {
      inbox_members[0].user_id.to_s => 'busy',
      inbox_members[1].user_id.to_s => 'busy',
      inbox_members[2].user_id.to_s => 'busy',
      inbox_members[3].user_id.to_s => 'online',
      inbox_members[4].user_id.to_s => 'online'
    }
  end

  before do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(online_users)
  end

  describe '#perform' do
    it 'will assign an online agent to the conversation' do
      expect(conversation.reload.assignee).to be_nil
      described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).perform
      expect(conversation.reload.assignee).not_to be_nil
    end
  end

  describe '#find_assignee' do
    it 'will return an online agent from the allowed agent ids in roud robin' do
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: allowed_agent_ids).find_assignee).to eq(inbox_members[3].user)
      expect(described_class.new(conversation: conversation,
                                 allowed_agent_ids: allowed_agent_ids).find_assignee).to eq(inbox_members[4].user)
    end

    context 'when no agent is online' do
      let(:online_users) { inbox_members.index_by { |member| member.user_id.to_s }.transform_values { 'offline' } }

      it 'falls back to the eligible offline agents instead of leaving it unassigned' do
        assignee = described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee

        expect(inbox_members.map(&:user)).to include(assignee)
      end

      it 'distributes the offline fallback in round robin' do
        first = described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee
        second = described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee

        expect(second).not_to eq(first)
      end

      it 'never falls back to an agent without access to the inbox' do
        outsider = create(:user, account: account, role: :agent)

        assignee = described_class.new(conversation: conversation,
                                       allowed_agent_ids: allowed_agent_ids + [outsider.id.to_s]).find_assignee

        expect(assignee).not_to eq(outsider)
      end

      it 'never falls back to an agent that no longer belongs to the account' do
        eligible = inbox_members.first
        AccountUser.where(account_id: account.id).where.not(user_id: eligible.user_id).destroy_all

        assignee = described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee

        expect(assignee).to eq(eligible.user)
      end

      it 'never falls back to an agent that cannot sign in yet' do
        eligible = inbox_members.first
        # rubocop:disable Rails/SkipsModelValidations
        User.where(id: inbox_members.map(&:user_id)).where.not(id: eligible.user_id).update_all(confirmed_at: nil)
        # rubocop:enable Rails/SkipsModelValidations

        assignee = described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee

        expect(assignee).to eq(eligible.user)
      end

      it 'returns nil when there is no eligible agent at all' do
        inbox.inbox_members.destroy_all

        expect(described_class.new(conversation: conversation, allowed_agent_ids: allowed_agent_ids).find_assignee).to be_nil
      end
    end

    context 'when the only online agent is not eligible' do
      it 'ignores the online agent and falls back to the eligible pool' do
        outsider = create(:user, account: account, role: :agent)
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ outsider.id.to_s => 'online' })

        assignee = described_class.new(conversation: conversation,
                                       allowed_agent_ids: allowed_agent_ids + [outsider.id.to_s]).find_assignee

        expect(inbox_members.map(&:user)).to include(assignee)
      end
    end
  end
end
