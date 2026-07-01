require 'rails_helper'

RSpec.describe Label do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'title validations' do
    it 'would not let you start title without numbers or letters' do
      label = FactoryBot.build(:label, title: '_12')
      expect(label.valid?).to be false
    end

    it 'would not let you use special characters' do
      label = FactoryBot.build(:label, title: 'jell;;2_12')
      expect(label.valid?).to be false
    end

    it 'would not allow space' do
      label = FactoryBot.build(:label, title: 'heeloo _12')
      expect(label.valid?).to be false
    end

    it 'allows foreign charactes' do
      label = FactoryBot.build(:label, title: '学中文_12')
      expect(label.valid?).to be true
    end

    it 'converts uppercase letters to lowercase' do
      label = FactoryBot.build(:label, title: 'Hello_World')
      expect(label.valid?).to be true
      expect(label.title).to eq 'hello_world'
    end

    it 'validates uniqueness of label name for account' do
      account = create(:account)
      label = FactoryBot.create(:label, account: account)
      duplicate_label = FactoryBot.build(:label, title: label.title, account: account)
      expect(duplicate_label.valid?).to be false
    end
  end

  describe '.after_update_commit' do
    let(:label) { create(:label) }

    it 'calls update job' do
      expect(Labels::UpdateJob).to receive(:perform_later).with('new-title', label.title, label.account_id)

      label.update(title: 'new-title')
    end

    it 'does not call update job if title is not updated' do
      expect(Labels::UpdateJob).not_to receive(:perform_later)

      label.update(description: 'new-description')
    end
  end

  describe 'filtered unread count invalidation' do
    let(:account) { create(:account) }
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:invalidator) { instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, user_visibility_changed!: true) }

    before do
      create(:account_user, account: account, user: user)
      create(:account_user, account: account, user: other_user)
    end

    it 'invalidates filtered counts for account users when a sidebar label is created' do
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)

      create(:label, account: account, show_on_sidebar: true)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: other_user.id)
    end

    it 'invalidates filtered counts for account users when sidebar visibility changes' do
      label = create(:label, account: account, show_on_sidebar: false)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)

      label.update!(show_on_sidebar: true)

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: other_user.id)
    end

    it 'invalidates filtered counts for account users when a sidebar label is deleted' do
      label = create(:label, account: account, show_on_sidebar: true)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)

      label.destroy!

      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: user.id)
      expect(invalidator).to have_received(:user_visibility_changed!).with(user_id: other_user.id)
    end

    it 'skips invalidation when a sidebar label is destroyed after its account has been deleted' do
      label = create(:label, account: account, show_on_sidebar: true)
      account.delete

      orphaned_label = described_class.find(label.id)

      expect { orphaned_label.destroy! }.not_to raise_error
    end

    it 'does not invalidate filtered counts when sidebar visibility is unchanged' do
      label = create(:label, account: account, show_on_sidebar: false)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).with(account).and_return(invalidator)

      label.update!(description: 'new-description')

      expect(invalidator).not_to have_received(:user_visibility_changed!)
    end
  end
end
