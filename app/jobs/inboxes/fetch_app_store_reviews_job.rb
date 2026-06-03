class Inboxes::FetchAppStoreReviewsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(channel)
    return unless channel.account.feature_enabled?(:channel_app_store)

    synced_until = sync_reviews(channel)
    return if synced_until.blank?

    channel.update!(last_synced_at: synced_until)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
  end

  private

  def sync_reviews(channel)
    failed = false
    synced_dates = []

    channel.fetch_reviews.each do |review_payload|
      ::AppStore::ReviewBuilder.new(review_payload: review_payload, channel: channel).perform
      synced_dates << parsed_review_created_at(review_payload)
    rescue StandardError => e
      failed = true
      ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
    end

    return if failed

    synced_dates.compact.max
  end

  def parsed_review_created_at(review_payload)
    Time.zone.parse(review_payload.dig('review', 'attributes', 'createdDate').to_s)
  rescue StandardError
    nil
  end
end
