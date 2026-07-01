# == Schema Information
#
# Table name: captain_conversation_facts
#
#  id                                    :bigint           not null, primary key
#  captain_handed_off_at                 :datetime
#  captain_resolved_at                   :datetime
#  csat_rating                           :integer
#  csat_submitted_at                     :datetime
#  first_captain_message_at              :datetime
#  first_human_reply_after_captain_at    :datetime
#  last_captain_message_at               :datetime
#  reopened_after_captain_resolution_at  :datetime
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  account_id                            :bigint           not null
#  assistant_id                          :bigint           not null
#  conversation_id                       :bigint           not null
#  csat_response_id                      :bigint
#  inbox_id                              :bigint           not null
#
# Indexes
#
#  idx_captain_facts_on_account_assistant_first_message  (account_id,assistant_id,first_captain_message_at)
#  idx_captain_facts_on_account_csat_submitted_at        (account_id,csat_submitted_at)
#  idx_captain_facts_on_account_handed_off_at            (account_id,captain_handed_off_at)
#  idx_captain_facts_on_account_resolved_at              (account_id,captain_resolved_at)
#  index_captain_conversation_facts_on_account_id        (account_id)
#  index_captain_conversation_facts_on_conversation_id   (conversation_id) UNIQUE
#
class Captain::ConversationFact < ApplicationRecord
  self.table_name = 'captain_conversation_facts'

  belongs_to :account
  belongs_to :conversation
  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox
  belongs_to :csat_response, class_name: 'CsatSurveyResponse', optional: true

  validates :conversation_id, uniqueness: true
end
