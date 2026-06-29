class Conversations::UnreadCounts::FilteredCounter
  FEATURE_FLAG = 'unread_count_for_filters'.freeze
  BUILD_LOCK_TTL = 15.minutes.to_i
  EMPTY_COUNTS = {
    mentions_count: 0,
    participating_count: 0,
    unattended_count: 0,
    folders: {}
  }.freeze

  attr_reader :account, :user, :now

  def self.empty_counts = EMPTY_COUNTS.deep_dup

  def initialize(account:, user:, now: Time.current)
    @account = account
    @user = user
    @now = now
  end

  def perform = built_in_counts.merge(folders: folder_counts)

  private

  def built_in_counts
    counts_from_built_in_snapshot(built_in_counts_snapshot) || self.class.empty_counts.except(:folders)
  end

  def built_in_counts_snapshot
    snapshot_or_build(
      state: store.built_in_filter_counts_state(account_id: account.id, user_id: user.id, now: now),
      lock_key: store.built_in_filter_build_lock_key(account.id, user.id),
      claim_refresh: -> { store.claim_built_in_filter_refresh!(account_id: account.id, user_id: user.id) }
    ) { build_built_in_counts! }
  end

  def counts_from_built_in_snapshot(snapshot)
    snapshot&.fetch(:counts, nil)&.slice(:mentions_count, :participating_count, :unattended_count)
  end

  def folder_counts
    folder_index = folder_index_snapshot
    return {} if folder_index.blank?

    folder_index[:filter_ids].each_with_object({}) do |filter_id, counts|
      count = filter_count(filter_id)
      counts[filter_id.to_s] = count if count.to_i.positive?
    end
  end

  def folder_index_snapshot
    snapshot_or_build(
      state: store.folder_index_state(account_id: account.id, user_id: user.id, now: now),
      lock_key: store.folder_index_build_lock_key(account.id, user.id),
      claim_refresh: -> { store.claim_folder_index_refresh!(account_id: account.id, user_id: user.id) }
    ) { build_folder_index! }
  end

  def filter_count(filter_id)
    snapshot = snapshot_or_build(
      state: store.filter_count_state(account_id: account.id, filter_id: filter_id, owner_user_id: user.id, now: now),
      lock_key: store.filter_build_lock_key(account.id, filter_id),
      claim_refresh: -> { store.claim_filter_refresh!(account_id: account.id, filter_id: filter_id) }
    ) { build_filter_count!(filter_id) }

    snapshot&.fetch(:count, nil)
  end

  # Version mismatches make a snapshot stale immediately, but refresh_after keeps DB rebuilds throttled.
  def snapshot_or_build(state:, lock_key:, claim_refresh:)
    return state.payload if state.fresh?

    stale_payload = state.payload if state.stale?
    return stale_payload if stale_payload.present? && !store.refresh_due?(stale_payload, now: now)
    return stale_payload unless claim_refresh.call

    built_payload = nil
    lock_acquired = false
    lock_manager.with_lock(lock_key, BUILD_LOCK_TTL) do
      lock_acquired = true
      built_payload = yield
    end
    lock_acquired ? built_payload : stale_payload
  end

  def build_built_in_counts!
    store.write_built_in_filter_counts!(**built_in_count_snapshot_payload)
    store.built_in_filter_counts(account_id: account.id, user_id: user.id)
  end

  def built_in_count_snapshot_payload
    {
      account_id: account.id,
      user_id: user.id,
      counts: built_in_counts_from_database,
      account_version: store.conversation_version(account.id),
      built_in_filter_version: store.built_in_filter_version(account_id: account.id, user_id: user.id),
      built_at: now
    }
  end

  def built_in_counts_from_database
    {
      mentions_count: count_relation(mentioned_unread_conversations),
      participating_count: count_relation(participating_unread_conversations),
      unattended_count: count_relation(unread_open_accessible_conversations.unattended)
    }
  end

  def mentioned_unread_conversations
    unread_open_accessible_conversations
      .joins(:mentions)
      .where(mentions: { account_id: account.id, user_id: user.id })
  end

  def participating_unread_conversations
    unread_open_accessible_conversations
      .joins(:conversation_participants)
      .where(conversation_participants: { user_id: user.id })
  end

  def build_folder_index!
    filter_ids = account.custom_filters.where(user_id: user.id, filter_type: :conversation).pluck(:id)
    store.write_folder_index!(
      account_id: account.id,
      user_id: user.id,
      filter_ids: filter_ids,
      folder_index_version: store.folder_index_version(account_id: account.id, user_id: user.id),
      built_at: now
    )
    store.folder_index(account_id: account.id, user_id: user.id)
  end

  def build_filter_count!(filter_id)
    custom_filter = account.custom_filters.find_by(id: filter_id, user_id: user.id, filter_type: :conversation)
    return delete_filter_count!(filter_id) if custom_filter.blank?

    count = filter_query_count(custom_filter)
    return delete_filter_count!(filter_id) if count.nil?

    write_filter_count!(filter_id, count)
    store.filter_count(account_id: account.id, filter_id: filter_id)
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue
    delete_filter_count!(filter_id)
  end

  def filter_query_count(custom_filter)
    ::Conversations::UnreadCounts::FilterQueryCounter.new(
      account: account,
      user: user,
      query: custom_filter.query
    ).perform
  end

  def write_filter_count!(filter_id, count)
    store.write_filter_count!(
      account_id: account.id,
      filter_id: filter_id,
      user_id: user.id,
      count: count,
      account_version: store.conversation_version(account.id),
      filter_version: store.filter_version(account_id: account.id, filter_id: filter_id),
      owner_built_in_filter_version: store.built_in_filter_version(account_id: account.id, user_id: user.id),
      built_at: now
    )
  end

  def delete_filter_count!(filter_id)
    store.delete_filter_count!(account_id: account.id, filter_id: filter_id)
    nil
  end

  def unread_open_accessible_conversations
    @unread_open_accessible_conversations ||= Conversations::PermissionFilterService.new(
      unread_conversations.open,
      user,
      account
    ).perform
  end

  def unread_conversations
    account.conversations
           .joins(:messages)
           .merge(Message.incoming.reorder(nil))
           .where(messages: { account_id: account.id })
           .where(unread_since_last_seen_condition)
           .distinct
  end

  def unread_since_last_seen_condition
    conversations = Conversation.arel_table
    messages = Message.arel_table

    conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))
  end

  def count_relation(relation)
    relation.unscope(:order).count
  end

  def lock_manager
    @lock_manager ||= Redis::LockManager.new
  end

  def store
    ::Conversations::UnreadCounts::FilteredCountStore
  end
end
