class ReportingEventListener < BaseListener
  include ReportingEventHelper

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    event_end_time = event.timestamp
    time_to_resolve = event_end_time.to_i - conversation.created_at.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_resolved',
      value: time_to_resolve,
      value_in_business_hours: business_hours(conversation.inbox, conversation.created_at,
                                              event_end_time),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: conversation.created_at,
      event_end_time: event_end_time,
      **actor_attributes(actor_from_event(event))
    )

    create_bot_resolved_event(conversation, reporting_event)
    persist_reporting_event(reporting_event)
  end

  def first_reply_created(event)
    message = extract_message_and_account(event)[0]
    conversation = message.conversation
    first_response_time = message.created_at.to_i - last_non_human_activity(conversation).to_i

    reporting_event = ReportingEvent.new(
      name: 'first_response',
      value: first_response_time,
      value_in_business_hours: business_hours(conversation.inbox, last_non_human_activity(conversation),
                                              message.created_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: message.sender_id,
      conversation_id: conversation.id,
      event_start_time: last_non_human_activity(conversation),
      event_end_time: message.created_at,
      **actor_attributes(actor_from_event(event) || message.sender)
    )

    persist_reporting_event(reporting_event)
  end

  def reply_created(event)
    message = extract_message_and_account(event)[0]
    conversation = message.conversation
    waiting_since = event.data[:waiting_since]

    return if waiting_since.blank?

    # When waiting_since is nil, set reply_time to 0
    reply_time = message.created_at.to_i - waiting_since.to_i

    reporting_event = ReportingEvent.new(
      name: 'reply_time',
      value: reply_time,
      value_in_business_hours: business_hours(conversation.inbox, waiting_since, message.created_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: waiting_since,
      event_end_time: message.created_at,
      **actor_attributes(actor_from_event(event) || message.sender)
    )
    persist_reporting_event(reporting_event)
  end

  def conversation_bot_handoff(event)
    conversation = extract_conversation_and_account(event)[0]
    event_end_time = event.timestamp

    # Best-effort guard: raw report reads count bot handoffs with DISTINCT conversation_id,
    # while rollup counts assume one conversation_bot_handoff event per conversation.
    # That uniqueness is not currently enforced at the database level.
    bot_handoff_event = ReportingEvent.find_by(conversation_id: conversation.id, name: 'conversation_bot_handoff')
    return if bot_handoff_event.present?

    time_to_handoff = event_end_time.to_i - conversation.created_at.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_bot_handoff',
      value: time_to_handoff,
      value_in_business_hours: business_hours(conversation.inbox, conversation.created_at, event_end_time),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: conversation.created_at,
      event_end_time: event_end_time,
      **actor_attributes(actor_from_event(event))
    )
    persist_reporting_event(reporting_event)
  end

  def conversation_captain_inference_resolved(event)
    create_captain_inference_event(event, 'conversation_captain_inference_resolved')
  end

  def conversation_captain_inference_handoff(event)
    create_captain_inference_event(event, 'conversation_captain_inference_handoff')
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]
    event_end_time = event.timestamp

    # Find the most recent resolved event for this conversation
    last_resolved_event = ReportingEvent.where(
      conversation_id: conversation.id,
      name: 'conversation_resolved'
    ).where('event_end_time <= ?', event_end_time).order(event_end_time: :desc).first

    create_conversation_opened_event(
      conversation,
      conversation_opened_event_attributes(conversation, last_resolved_event, event_end_time),
      actor_from_event(event)
    )
  end

  private

  def conversation_opened_event_attributes(conversation, last_resolved_event, event_end_time)
    return first_conversation_opened_event_attributes(conversation, event_end_time) if last_resolved_event.blank?

    {
      value: event_end_time.to_i - last_resolved_event.event_end_time.to_i,
      value_in_business_hours: business_hours(conversation.inbox, last_resolved_event.event_end_time, event_end_time),
      event_start_time: last_resolved_event.event_end_time,
      event_end_time: event_end_time
    }
  end

  def first_conversation_opened_event_attributes(conversation, event_end_time)
    {
      value: 0,
      value_in_business_hours: 0,
      event_start_time: conversation.created_at,
      event_end_time: event_end_time
    }
  end

  def create_conversation_opened_event(conversation, event_attributes, actor)
    reporting_event = ReportingEvent.new(
      name: 'conversation_opened',
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      **event_attributes,
      **actor_attributes(actor)
    )
    persist_reporting_event(reporting_event, rollup: false)
  end

  def create_captain_inference_event(event, event_name)
    conversation = extract_conversation_and_account(event)[0]
    time_to_event = event.timestamp.to_i - conversation.created_at.to_i

    reporting_event = ReportingEvent.new(
      name: event_name,
      value: time_to_event,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: conversation.created_at,
      event_end_time: event.timestamp,
      **actor_attributes(actor_from_event(event))
    )
    persist_reporting_event(reporting_event, rollup: false)
  end

  def create_bot_resolved_event(conversation, reporting_event)
    return unless conversation.inbox.active_bot?
    # We don't want to create a bot_resolved event if there is user interaction on the conversation
    return if conversation.messages.exists?(message_type: :outgoing, sender_type: 'User')

    bot_resolved_event = reporting_event.dup
    bot_resolved_event.name = 'conversation_bot_resolved'
    persist_reporting_event(bot_resolved_event)
  end

  def persist_reporting_event(reporting_event, rollup: true)
    reporting_event.save!
    safe_rollup(reporting_event) if rollup
    update_captain_conversation_fact(reporting_event)
  end

  def update_captain_conversation_fact(reporting_event)
    return unless defined?(Captain::ConversationFactUpdater)

    Captain::ConversationFactUpdater.record_reporting_event(reporting_event)
  end

  def actor_from_event(event)
    event.data[:performed_by]
  end

  def actor_attributes(actor)
    return {} if actor.blank? || actor.id.blank?

    { actor_type: actor.class.name, actor_id: actor.id }
  end

  def safe_rollup(reporting_event)
    # Rollups are derived from the raw reporting event. If a transient rollup write
    # failure bubbles out here, Sidekiq retries the dispatcher job and can insert the
    # same raw event again. That can temporarily under-report rollups, but the source
    # event is preserved and rollup data can be rebuilt or re-applied later.
    ReportingEvents::RollupService.perform(reporting_event)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: reporting_event.account).capture_exception
  end
end
