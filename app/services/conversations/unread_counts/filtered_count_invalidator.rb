class Conversations::UnreadCounts::FilteredCountInvalidator
  FEATURE_FLAG = 'unread_count_for_filters'.freeze

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def conversation_changed!
    return false unless enabled?

    store.bump_conversation_version!(account.id)
    true
  end

  def user_visibility_changed!(user_id:)
    return false unless enabled? && user_id.present?

    store.bump_built_in_filter_version!(account_id: account.id, user_id: user_id)
    true
  end

  def custom_filter_created!(custom_filter)
    return false unless conversation_filter?(custom_filter)

    bump_folder_index_version!(custom_filter)
    bump_filter_version!(custom_filter)
    true
  end

  def custom_filter_updated!(custom_filter)
    return false unless enabled? && conversation_filter_before_or_after?(custom_filter)

    filter_type_changed = filter_type_changed?(custom_filter)
    query_changed = query_changed?(custom_filter)
    return false unless filter_type_changed || query_changed

    bump_folder_index_version!(custom_filter) if filter_type_changed
    bump_filter_version!(custom_filter)
    store.delete_filter_count!(account_id: account.id, filter_id: custom_filter.id) if moved_out_of_conversation_filters?(custom_filter)
    true
  end

  def custom_filter_destroyed!(custom_filter)
    return false unless conversation_filter?(custom_filter)

    bump_folder_index_version!(custom_filter)
    store.delete_filter_count!(account_id: account.id, filter_id: custom_filter.id)
    true
  end

  private

  def enabled?
    account&.feature_enabled?(FEATURE_FLAG)
  end

  def conversation_filter?(custom_filter)
    enabled? && custom_filter.conversation?
  end

  def conversation_filter_before_or_after?(custom_filter)
    custom_filter.conversation? || previous_filter_type(custom_filter) == 'conversation'
  end

  def moved_out_of_conversation_filters?(custom_filter)
    filter_type_changed?(custom_filter) && previous_filter_type(custom_filter) == 'conversation' && !custom_filter.conversation?
  end

  def filter_type_changed?(custom_filter)
    custom_filter.previous_changes.key?('filter_type')
  end

  def query_changed?(custom_filter)
    custom_filter.previous_changes.key?('query')
  end

  def previous_filter_type(custom_filter)
    raw_filter_type = custom_filter.previous_changes.dig('filter_type', 0)
    return if raw_filter_type.blank?
    return raw_filter_type if CustomFilter.filter_types.key?(raw_filter_type)
    return CustomFilter.filter_types.key(raw_filter_type) if raw_filter_type.is_a?(Integer)

    CustomFilter.filter_types.key(raw_filter_type.to_i) || raw_filter_type.to_s
  end

  def bump_folder_index_version!(custom_filter)
    store.bump_folder_index_version!(account_id: account.id, user_id: custom_filter.user_id)
  end

  def bump_filter_version!(custom_filter)
    store.bump_filter_version!(account_id: account.id, filter_id: custom_filter.id)
  end

  def store
    ::Conversations::UnreadCounts::FilteredCountStore
  end
end
