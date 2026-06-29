require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::FilteredCountInvalidator do
  subject(:invalidator) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:filter_id) { 123 }
  let(:store) { Conversations::UnreadCounts::FilteredCountStore }

  after do
    redis_keys.each { |key| Redis::Alfred.delete(key) }
  end

  describe '#conversation_changed!' do
    it 'bumps the account conversation version when the feature is enabled' do
      account.enable_features!(:unread_count_for_filters)

      expect { invalidator.conversation_changed! }.to change { store.conversation_version(account.id) }.by(1)
    end

    it 'does not write Redis keys when the feature is disabled' do
      expect { invalidator.conversation_changed! }.not_to(change { store.conversation_version(account.id) })
    end
  end

  describe '#user_visibility_changed!' do
    it 'bumps the user built-in filter version' do
      account.enable_features!(:unread_count_for_filters)

      expect do
        invalidator.user_visibility_changed!(user_id: user.id)
      end.to change { store.built_in_filter_version(account_id: account.id, user_id: user.id) }.by(1)
    end
  end

  describe '#custom_filter_created!' do
    it 'bumps the folder index and saved filter versions for conversation filters' do
      account.enable_features!(:unread_count_for_filters)
      filter_version = store.filter_version(account_id: account.id, filter_id: filter_id)

      expect do
        invalidator.custom_filter_created!(conversation_filter)
      end.to change { store.folder_index_version(account_id: account.id, user_id: user.id) }.by(1)
      expect(store.filter_version(account_id: account.id, filter_id: filter_id)).to eq(filter_version + 1)
    end

    it 'ignores non-conversation filters' do
      account.enable_features!(:unread_count_for_filters)

      expect do
        invalidator.custom_filter_created!(conversation_filter(is_conversation: false))
      end.not_to(change { store.folder_index_version(account_id: account.id, user_id: user.id) })
    end
  end

  describe '#custom_filter_updated!' do
    it 'bumps only the filter version when the query changes' do
      account.enable_features!(:unread_count_for_filters)
      filter = conversation_filter(previous_changes: { 'query' => [{ status: 'open' }, { status: 'resolved' }] })
      folder_index_version = store.folder_index_version(account_id: account.id, user_id: user.id)

      expect do
        invalidator.custom_filter_updated!(filter)
      end.to change { store.filter_version(account_id: account.id, filter_id: filter_id) }.by(1)
      expect(store.folder_index_version(account_id: account.id, user_id: user.id)).to eq(folder_index_version)
    end

    it 'ignores name-only updates' do
      account.enable_features!(:unread_count_for_filters)
      filter = conversation_filter(previous_changes: { 'name' => %w[Open Resolved] })

      expect do
        invalidator.custom_filter_updated!(filter)
      end.not_to(change { store.filter_version(account_id: account.id, filter_id: filter_id) })
    end

    it 'bumps versions and deletes the saved count when the filter moves away from conversations' do
      account.enable_features!(:unread_count_for_filters)
      filter = conversation_filter(
        is_conversation: false,
        previous_changes: { 'filter_type' => %w[conversation contact] }
      )
      store.write_filter_count!(
        account_id: account.id,
        filter_id: filter_id,
        user_id: user.id,
        count: 4,
        account_version: 0,
        filter_version: 0,
        owner_built_in_filter_version: 0
      )
      filter_version = store.filter_version(account_id: account.id, filter_id: filter_id)

      expect do
        invalidator.custom_filter_updated!(filter)
      end.to change { store.folder_index_version(account_id: account.id, user_id: user.id) }.by(1)
      expect(store.filter_version(account_id: account.id, filter_id: filter_id)).to eq(filter_version + 1)
      expect(store.filter_count(account_id: account.id, filter_id: filter_id)).to be_nil
    end
  end

  describe '#custom_filter_destroyed!' do
    it 'bumps the folder index version and deletes the saved count' do
      account.enable_features!(:unread_count_for_filters)
      store.write_filter_count!(
        account_id: account.id,
        filter_id: filter_id,
        user_id: user.id,
        count: 2,
        account_version: 0,
        filter_version: 0,
        owner_built_in_filter_version: 0
      )

      expect do
        invalidator.custom_filter_destroyed!(conversation_filter)
      end.to change { store.folder_index_version(account_id: account.id, user_id: user.id) }.by(1)
      expect(store.filter_count(account_id: account.id, filter_id: filter_id)).to be_nil
    end
  end

  def conversation_filter(is_conversation: true, previous_changes: {})
    instance_double(
      CustomFilter,
      id: filter_id,
      user_id: user.id,
      conversation?: is_conversation,
      previous_changes: previous_changes
    )
  end

  def redis_keys
    [
      store.conversation_version_key(account.id),
      store.built_in_filter_version_key(account.id, user.id),
      store.folder_index_version_key(account.id, user.id),
      store.filter_version_key(account.id, filter_id),
      store.filter_count_key(account.id, filter_id)
    ]
  end
end
