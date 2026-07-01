require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::FilteredCounter do
  subject(:counter) { described_class.new(account: account, user: agent, now: now) }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:visible_inbox) { create(:inbox, account: account) }
  let(:hidden_inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-06-29 10:00:00 UTC') }
  let(:store) { Conversations::UnreadCounts::FilteredCountStore }

  before do
    create(:inbox_member, user: agent, inbox: visible_inbox)
  end

  after do
    redis_keys.each { |key| Redis::Alfred.delete(key) }
  end

  it 'builds built-in filter counts from unread open conversations visible to the user' do
    mentioned = create_visible_unread_conversation
    participating = create_visible_unread_conversation
    create_visible_unread_conversation(unattended: true)
    hidden_mention = create_unread_conversation(account: account, inbox: hidden_inbox)
    resolved_mention = create_visible_unread_conversation(status: :resolved)
    read_mention = create_visible_unread_conversation(agent_last_seen_at: 1.minute.from_now)

    [mentioned, hidden_mention, resolved_mention, read_mention].each do |conversation|
      create(:mention, account: account, conversation: conversation, user: agent)
    end
    create(:conversation_participant, account: account, conversation: participating, user: agent)

    expect(counter.perform).to include(
      mentions_count: 1,
      participating_count: 1,
      unattended_count: 1
    )
  end

  it 'returns stale built-in counts until the refresh interval elapses' do
    mentioned = create_visible_unread_conversation
    create(:mention, account: account, conversation: mentioned, user: agent)

    expect(counter.perform[:mentions_count]).to eq(1)

    second_mention = create_visible_unread_conversation
    create(:mention, account: account, conversation: second_mention, user: agent)
    store.bump_conversation_version!(account.id)

    expect(described_class.new(account: account, user: agent, now: now + 10.seconds).perform[:mentions_count]).to eq(1)

    Redis::Alfred.delete(store.built_in_filter_refresh_throttle_key(account.id, agent.id))
    expect(described_class.new(account: account, user: agent, now: now + 31.seconds).perform[:mentions_count]).to eq(2)
  end

  it 'tags built-in snapshots with versions captured before the DB read' do
    race_counter = described_class.new(account: account, user: agent, now: now)
    allow(race_counter).to receive(:built_in_counts_from_database) do
      store.bump_conversation_version!(account.id)
      { mentions_count: 1, participating_count: 0, unattended_count: 0 }
    end

    race_counter.perform

    snapshot = store.built_in_filter_counts(account_id: account.id, user_id: agent.id)
    expect(snapshot[:account_version]).to eq(0)
    expect(store.built_in_filter_counts_state(account_id: account.id, user_id: agent.id, now: now)).to be_stale
  end

  it 'tags folder indexes with versions captured before the DB read' do
    race_counter = described_class.new(account: account, user: agent, now: now)
    allow(race_counter).to receive(:folder_filter_ids_from_database) do
      store.bump_folder_index_version!(account_id: account.id, user_id: agent.id)
      []
    end

    race_counter.send(:build_folder_index!)

    snapshot = store.folder_index(account_id: account.id, user_id: agent.id)
    expect(snapshot[:folder_index_version]).to eq(0)
    expect(store.folder_index_state(account_id: account.id, user_id: agent.id, now: now)).to be_stale
  end

  it 'builds saved folder counts from unread conversations matching the saved filter query' do
    resolved = create_visible_unread_conversation(status: :resolved)
    create_visible_unread_conversation(status: :open)
    hidden_resolved = create_unread_conversation(account: account, inbox: hidden_inbox)
    hidden_resolved.update!(status: :resolved)
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'status', values: ['resolved'])
    )

    expect(counter.perform[:folders]).to eq(custom_filter.id.to_s => 1)
    expect(store.filter_count(account_id: account.id, filter_id: custom_filter.id)[:count]).to eq(1)
    expect(resolved.reload.status).to eq('resolved')
  end

  it 'tags saved filter counts with versions captured before the DB read' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'status', values: ['open'])
    )
    race_counter = described_class.new(account: account, user: agent, now: now)
    allow(race_counter).to receive(:filter_query_count) do
      store.bump_filter_version!(account_id: account.id, filter_id: custom_filter.id)
      1
    end

    race_counter.send(:build_filter_count!, custom_filter.id)

    snapshot = store.filter_count(account_id: account.id, filter_id: custom_filter.id)
    expect(snapshot[:filter_version]).to eq(0)
    expect(store.filter_count_state(account_id: account.id, filter_id: custom_filter.id, owner_user_id: agent.id, now: now)).to be_stale
  end

  it 'tags saved filter counts with versions captured before loading the filter row' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'status', values: ['open'])
    )
    filters = account.custom_filters
    allow(account).to receive(:custom_filters).and_return(filters)
    allow(filters).to receive(:find_by) do
      store.bump_filter_version!(account_id: account.id, filter_id: custom_filter.id)
      custom_filter
    end

    counter.send(:build_filter_count!, custom_filter.id)

    snapshot = store.filter_count(account_id: account.id, filter_id: custom_filter.id)
    expect(snapshot[:filter_version]).to eq(0)
    expect(store.filter_count_state(account_id: account.id, filter_id: custom_filter.id, owner_user_id: agent.id, now: now)).to be_stale
  end

  it 'omits invalid saved folders without writing a badge count' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'unknown_attribute', values: ['value'])
    )

    expect(counter.perform[:folders]).to eq({})
    expect(store.filter_count(account_id: account.id, filter_id: custom_filter.id)).to be_nil
  end

  it 'omits saved folders with malformed query payloads' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'status', values: 'open')
    )

    expect(counter.perform[:folders]).to eq({})
    expect(store.filter_count(account_id: account.id, filter_id: custom_filter.id)).to be_nil
  end

  it 'omits saved folders with invalid typed values' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'team_id', values: ['abc'])
    )

    expect(counter.perform[:folders]).to eq({})
    expect(store.filter_count(account_id: account.id, filter_id: custom_filter.id)).to be_nil
  end

  it 'omits saved folders with invalid ID values' do
    custom_filter = create(
      :custom_filter,
      account: account,
      user: agent,
      filter_type: :conversation,
      query: filter_query(attribute_key: 'assignee_id', values: ['abc'])
    )

    expect(counter.perform[:folders]).to eq({})
    expect(store.filter_count(account_id: account.id, filter_id: custom_filter.id)).to be_nil
  end

  def create_visible_unread_conversation(status: :open, agent_last_seen_at: 1.hour.ago, unattended: false)
    conversation = create_unread_conversation(account: account, inbox: visible_inbox)
    conversation.update!(
      status: status,
      agent_last_seen_at: agent_last_seen_at,
      first_reply_created_at: unattended ? nil : Time.current,
      waiting_since: unattended ? 5.minutes.ago : nil
    )
    conversation
  end

  def filter_query(attribute_key:, values:)
    {
      payload: [{
        attribute_key: attribute_key,
        attribute_model: 'standard',
        filter_operator: 'equal_to',
        values: values
      }]
    }
  end

  def redis_keys
    version_keys + snapshot_keys + lock_and_throttle_keys
  end

  def filter_ids
    CustomFilter.where(account_id: account.id).pluck(:id)
  end

  def version_keys
    [
      store.conversation_version_key(account.id),
      store.built_in_filter_version_key(account.id, agent.id),
      store.folder_index_version_key(account.id, agent.id)
    ] + filter_ids.map { |filter_id| store.filter_version_key(account.id, filter_id) }
  end

  def snapshot_keys
    [
      store.built_in_filter_counts_key(account.id, agent.id),
      store.folder_index_key(account.id, agent.id)
    ] + filter_ids.map { |filter_id| store.filter_count_key(account.id, filter_id) }
  end

  def lock_and_throttle_keys
    user_lock_and_throttle_keys + filter_lock_and_throttle_keys
  end

  def user_lock_and_throttle_keys
    [
      store.built_in_filter_build_lock_key(account.id, agent.id),
      store.built_in_filter_refresh_throttle_key(account.id, agent.id),
      store.folder_index_build_lock_key(account.id, agent.id),
      store.folder_index_refresh_throttle_key(account.id, agent.id)
    ]
  end

  def filter_lock_and_throttle_keys
    filter_ids.flat_map do |filter_id|
      [
        store.filter_build_lock_key(account.id, filter_id),
        store.filter_refresh_throttle_key(account.id, filter_id)
      ]
    end
  end
end
