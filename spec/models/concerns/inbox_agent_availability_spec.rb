# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InboxAgentAvailability do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:online_agent) { create(:user, account: account, role: :agent) }
  let(:offline_agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: inbox, user: online_agent)
    create(:inbox_member, inbox: inbox, user: offline_agent)
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .and_return({ online_agent.id.to_s => 'online', offline_agent.id.to_s => 'offline' })
  end

  describe '#assignment_eligible_members' do
    it 'includes members regardless of presence' do
      expect(inbox.assignment_eligible_members.map(&:user_id)).to contain_exactly(online_agent.id, offline_agent.id)
    end

    it 'excludes agents without access to the inbox' do
      outsider = create(:user, account: account, role: :agent)

      expect(inbox.assignment_eligible_members.map(&:user_id)).not_to include(outsider.id)
    end

    it 'excludes agents that no longer belong to the account' do
      offline_agent.account_users.find_by(account_id: account.id).destroy!

      expect(inbox.assignment_eligible_members.map(&:user_id)).to contain_exactly(online_agent.id)
    end

    it 'excludes agents that cannot sign in yet' do
      offline_agent.update!(confirmed_at: nil)

      expect(inbox.assignment_eligible_members.map(&:user_id)).to contain_exactly(online_agent.id)
    end
  end

  describe '#available_agents' do
    it 'returns only the online members' do
      expect(inbox.available_agents.map(&:user_id)).to contain_exactly(online_agent.id)
    end

    it 'returns nothing when no one is online' do
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

      expect(inbox.available_agents).to be_empty
    end

    it 'does not return an online agent that lost access to the inbox' do
      inbox.inbox_members.find_by(user_id: online_agent.id).destroy!

      expect(inbox.available_agents).to be_empty
    end
  end

  describe '#prioritize_online_agents' do
    it 'keeps only the online members while at least one is online' do
      result = inbox.prioritize_online_agents(inbox.assignment_eligible_members)

      expect(result.map(&:user_id)).to contain_exactly(online_agent.id)
    end

    it 'falls back to every eligible member when no one is online' do
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

      result = inbox.prioritize_online_agents(inbox.assignment_eligible_members)

      expect(result.map(&:user_id)).to contain_exactly(online_agent.id, offline_agent.id)
    end

    it 'falls back when every online agent sits outside the given pool' do
      pool = inbox.assignment_eligible_members.where(user_id: offline_agent.id)

      result = inbox.prioritize_online_agents(pool)

      expect(result.map(&:user_id)).to contain_exactly(offline_agent.id)
    end
  end

  describe '#member_ids_with_assignment_capacity' do
    it 'returns the eligible members regardless of presence' do
      expect(inbox.member_ids_with_assignment_capacity).to contain_exactly(online_agent.id, offline_agent.id)
    end
  end
end
