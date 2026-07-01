module Enterprise::CsatSurveyResponse
  extend ActiveSupport::Concern

  included do
    after_commit :update_captain_conversation_fact, on: [:create, :update]
  end

  private

  def update_captain_conversation_fact
    Captain::ConversationFactUpdater.record_csat_response(self)
  end
end
