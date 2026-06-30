# == Schema Information
#
# Table name: captain_usages
#
#  id                :bigint           not null, primary key
#  bucket_started_at :datetime         not null
#  credits_used      :integer          default(0), not null
#  usage_type        :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#
# Indexes
#
#  index_captain_usages_on_account_id            (account_id)
#  index_captain_usages_on_assistant_id          (assistant_id)
#  index_captain_usages_unique_bucket            (account_id,assistant_id,usage_type,bucket_started_at) UNIQUE
#
class Captain::Usage < ApplicationRecord
  self.table_name = 'captain_usages'

  # Width of each reporting bucket. Usage is binned into 15-minute UTC buckets so
  # it can be re-sliced into any caller timezone, including :45 offset zones
  # (e.g. Nepal +5:45). Do not widen this without revisiting timezone slicing.
  BUCKET_SIZE = 15.minutes

  # Only :assistant_response and :copilot_response are logged today. The
  # remaining values are reserved for future usage sources:
  #   editor_actions, label_suggestion, audio_transcription
  enum usage_type: {
    assistant_response: 0,
    copilot_response: 1
  }

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account

  # log is the only sanctioned write path; it uses upsert, which skips model
  # validations. Column invariants are enforced via NOT NULL at the DB level.
  #
  # Records credit usage against the 15-minute bucket that contains +occurred_at+.
  # Concurrent calls are safe: the row is created or its counter incremented in a
  # single atomic statement keyed on the unique (account, assistant, type, bucket).
  def self.log(account:, assistant:, usage_type:, credits: 1, occurred_at: Time.current)
    now = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    upsert(
      {
        account_id: account.id,
        assistant_id: assistant.id,
        usage_type: usage_types.fetch(usage_type.to_s),
        bucket_started_at: bucket_for(occurred_at),
        credits_used: credits,
        created_at: now,
        updated_at: now
      },
      unique_by: 'index_captain_usages_unique_bucket',
      on_duplicate: Arel.sql(
        'credits_used = captain_usages.credits_used + EXCLUDED.credits_used, updated_at = EXCLUDED.updated_at'
      )
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Floors +time+ to the start of its 15-minute UTC bucket. Subseconds are
  # dropped so the bucket timestamp is stable across calls within the same
  # bucket; otherwise distinct microseconds break the unique-key upsert.
  def self.bucket_for(time)
    epoch = time.to_i
    Time.at(epoch - (epoch % BUCKET_SIZE.to_i)).utc
  end
end
