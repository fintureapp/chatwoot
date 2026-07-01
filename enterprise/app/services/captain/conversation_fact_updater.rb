class Captain::ConversationFactUpdater
  RESOLVED_EVENT_NAMES = %w[
    conversation_resolved
    conversation_bot_resolved
    conversation_captain_inference_resolved
  ].freeze

  HANDOFF_EVENT_NAMES = %w[
    conversation_bot_handoff
    conversation_captain_inference_handoff
  ].freeze

  class << self
    def record_message(message)
      return unless message.outgoing?
      return if message.private?

      if captain_message?(message)
        record_captain_message(message)
      elsif human_message?(message)
        record_human_message(message)
      end
    end

    def record_reporting_event(reporting_event)
      if RESOLVED_EVENT_NAMES.include?(reporting_event.name)
        record_captain_resolution(reporting_event)
      elsif HANDOFF_EVENT_NAMES.include?(reporting_event.name)
        record_captain_handoff(reporting_event)
      elsif reporting_event.name == 'conversation_opened'
        record_reopen_after_captain_resolution(reporting_event)
      end
    end

    def record_csat_response(csat_response)
      fact = Captain::ConversationFact.find_by(conversation_id: csat_response.conversation_id)
      return if fact.blank?

      fact.assign_attributes(
        csat_response_id: csat_response.id,
        csat_rating: csat_response.rating,
        csat_submitted_at: csat_response.created_at
      )
      fact.save! if fact.changed?
    end

    private

    def captain_message?(message)
      message.sender_type == 'Captain::Assistant'
    end

    def human_message?(message)
      message.sender_type == 'User'
    end

    def record_captain_message(message)
      fact = find_or_create_fact!(
        conversation_id: message.conversation_id,
        account_id: message.account_id,
        inbox_id: message.inbox_id,
        assistant_id: message.sender_id
      )
      fact.first_captain_message_at ||= message.created_at
      fact.last_captain_message_at = latest_time(fact.last_captain_message_at, message.created_at)
      fact.save! if fact.changed?
    end

    def record_human_message(message)
      fact = Captain::ConversationFact.find_by(conversation_id: message.conversation_id)
      return if fact.blank?
      return if fact.first_captain_message_at.blank?
      return if fact.first_human_reply_after_captain_at.present?
      return if message.created_at <= fact.first_captain_message_at

      fact.update!(first_human_reply_after_captain_at: message.created_at)
    end

    def record_captain_resolution(reporting_event)
      return unless captain_actor?(reporting_event)

      fact = find_or_create_fact_from_event!(reporting_event)
      fact.captain_resolved_at = earliest_time(fact.captain_resolved_at, reporting_event.event_end_time)
      fact.save! if fact.changed?
    end

    def record_captain_handoff(reporting_event)
      return unless captain_actor?(reporting_event)

      fact = find_or_create_fact_from_event!(reporting_event)
      fact.captain_handed_off_at = earliest_time(fact.captain_handed_off_at, reporting_event.event_end_time)
      fact.save! if fact.changed?
    end

    def record_reopen_after_captain_resolution(reporting_event)
      fact = Captain::ConversationFact.find_by(conversation_id: reporting_event.conversation_id)
      return if fact.blank?
      return if fact.captain_resolved_at.blank?
      return if fact.reopened_after_captain_resolution_at.present?
      return if reporting_event.event_end_time < fact.captain_resolved_at

      fact.update!(reopened_after_captain_resolution_at: reporting_event.event_end_time)
    end

    def captain_actor?(reporting_event)
      reporting_event.actor_type == 'Captain::Assistant' && reporting_event.actor_id.present?
    end

    def find_or_create_fact_from_event!(reporting_event)
      find_or_create_fact!(
        conversation_id: reporting_event.conversation_id,
        account_id: reporting_event.account_id,
        inbox_id: reporting_event.inbox_id,
        assistant_id: reporting_event.actor_id
      )
    end

    def find_or_create_fact!(conversation_id:, account_id:, inbox_id:, assistant_id:)
      Captain::ConversationFact.create_or_find_by!(conversation_id: conversation_id) do |fact|
        fact.account_id = account_id
        fact.inbox_id = inbox_id
        fact.assistant_id = assistant_id
      end
    end

    def earliest_time(current_time, candidate_time)
      [current_time, candidate_time].compact.min
    end

    def latest_time(current_time, candidate_time)
      [current_time, candidate_time].compact.max
    end
  end
end
