require 'rails_helper'

RSpec.describe TeamMember do
  describe 'associations' do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'filtered unread count invalidation' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }
    let(:user) { create(:user) }
    let(:store) { Conversations::UnreadCounts::FilteredCountStore }

    before do
      account.enable_features!(:unread_count_for_filters)
    end

    it 'invalidates the user built-in filter version when team access is added' do
      expect do
        create(:team_member, team: team, user: user)
      end.to change { store.built_in_filter_version(account_id: account.id, user_id: user.id) }.by(1)
    end

    it 'invalidates the user built-in filter version when team access is removed' do
      team_member = create(:team_member, team: team, user: user)

      expect do
        team_member.destroy!
      end.to change { store.built_in_filter_version(account_id: account.id, user_id: user.id) }.by(1)
    end
  end
end
