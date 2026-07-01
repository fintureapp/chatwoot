# == Schema Information
#
# Table name: labels
#
#  id              :bigint           not null, primary key
#  color           :string           default("#1f93ff"), not null
#  description     :text
#  show_on_sidebar :boolean
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint
#
# Indexes
#
#  index_labels_on_account_id            (account_id)
#  index_labels_on_title_and_account_id  (title,account_id) UNIQUE
#
class Label < ApplicationRecord
  include RegexHelper
  include AccountCacheRevalidator

  belongs_to :account

  validates :title,
            presence: { message: I18n.t('errors.validations.presence') },
            format: { with: UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE },
            uniqueness: { scope: :account_id }

  after_create_commit :invalidate_filtered_unread_count_visibility_create, if: :show_on_sidebar?
  after_update_commit :update_associated_models
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :show_on_sidebar_previously_changed?
  after_destroy_commit :invalidate_filtered_unread_count_visibility_destroy, if: :show_on_sidebar?
  default_scope { order(:title) }

  before_validation do
    self.title = title.downcase if attribute_present?('title')
  end

  def conversations
    account.conversations.tagged_with(title)
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  private

  def update_associated_models
    return unless title_previously_changed?

    Labels::UpdateJob.perform_later(title, title_previously_was, account_id)
  end

  def invalidate_filtered_unread_count_visibility_create
    invalidate_filtered_unread_count_visibility
  end

  def invalidate_filtered_unread_count_visibility_update
    invalidate_filtered_unread_count_visibility
  end

  def invalidate_filtered_unread_count_visibility_destroy
    invalidate_filtered_unread_count_visibility
  end

  def invalidate_filtered_unread_count_visibility
    return if account.blank?

    invalidator = ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account)
    account.account_users.find_each { |account_user| invalidator.user_visibility_changed!(user_id: account_user.user_id) }
  end
end
