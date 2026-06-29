# Computes per-assistant overview metrics for the Captain Overview page.
# Each metric is returned for the current window and the previous equal-length
# window, plus a derived trend. See stats.md (repo root) for the metric
# definitions and the source-of-truth queries this mirrors.
class Captain::AssistantStatsBuilder
  RESOLVED_EVENT_NAMES = %w[conversation_captain_inference_resolved conversation_bot_resolved].freeze
  HANDOFF_EVENT_NAMES = %w[conversation_captain_inference_handoff conversation_bot_handoff].freeze
  DEFAULT_RANGE_DAYS = 30

  attr_reader :assistant, :account, :range_days

  def initialize(assistant, range_days = DEFAULT_RANGE_DAYS)
    @assistant = assistant
    @account = assistant.account
    @range_days = range_days.to_i.positive? ? range_days.to_i : DEFAULT_RANGE_DAYS
  end

  def metrics
    current = window_metrics(current_range)
    previous = window_metrics(previous_range)

    {
      conversations_handled: pack(current[:handled], previous[:handled], :percent),
      auto_resolution_rate: pack(current[:auto_resolution], previous[:auto_resolution], :point),
      handoff_rate: pack(current[:handoff], previous[:handoff], :point),
      hours_saved: pack(current[:hours_saved], previous[:hours_saved], :percent),
      reopen_rate: pack(current[:reopen], previous[:reopen], :point),
      conversation_depth: pack(current[:depth], previous[:depth], :absolute),
      knowledge: knowledge
    }
  end

  private

  def current_range
    @current_range ||= (range_days.days.ago)..Time.current
  end

  def previous_range
    @previous_range ||= ((2 * range_days).days.ago)..range_days.days.ago
  end

  # Raw metric values for a single window.
  def window_metrics(range)
    handled = handled_scope(range).distinct.count(:conversation_id)
    public_messages = public_outgoing_scope(range)
    public_count = public_messages.count
    depth_conversations = public_messages.distinct.count(:conversation_id)

    {
      handled: handled,
      auto_resolution: rate(resolved_count(range), handled),
      handoff: rate(handoff_count(range), handled),
      hours_saved: (public_count * avg_reply_time(range) / 3600.0).round,
      reopen: reopen_rate(range),
      depth: depth_conversations.zero? ? 0 : (public_count.to_f / depth_conversations).round(1)
    }
  end

  # Conversations the assistant participated in (authored any message).
  def handled_scope(range)
    account.messages.where(sender_type: 'Captain::Assistant', sender_id: assistant.id, created_at: range)
  end

  # Public outgoing replies the assistant sent (excludes private notes / handoff activity).
  def public_outgoing_scope(range)
    handled_scope(range).where(message_type: :outgoing, private: false)
  end

  def resolved_count(range)
    distinct_event_conversations(RESOLVED_EVENT_NAMES, handled_scope(range))
  end

  def handoff_count(range)
    distinct_event_conversations(HANDOFF_EVENT_NAMES, handled_scope(range))
  end

  def distinct_event_conversations(names, handled)
    account.reporting_events
           .where(name: names, conversation_id: handled.select(:conversation_id))
           .distinct.count(:conversation_id)
  end

  # Of the conversations Captain auto-resolved (inbox-based), the share reopened afterwards.
  def reopen_rate(range)
    resolved_conversation_ids = account.reporting_events
                                       .where(name: 'conversation_captain_inference_resolved',
                                              inbox_id: assistant_inbox_ids, created_at: range)
                                       .select(:conversation_id)
    resolved = account.reporting_events.where(name: 'conversation_captain_inference_resolved',
                                              inbox_id: assistant_inbox_ids, created_at: range)
                      .distinct.count(:conversation_id)
    reopened = account.reporting_events
                      .where(name: 'conversation_opened', conversation_id: resolved_conversation_ids)
                      .where('reporting_events.value > 0')
                      .distinct.count(:conversation_id)
    rate(reopened, resolved)
  end

  def avg_reply_time(range)
    account.reporting_events.where(name: 'reply_time', created_at: range).average(:value).to_f
  end

  def assistant_inbox_ids
    @assistant_inbox_ids ||= assistant.inboxes.ids
  end

  def knowledge
    responses = Captain::AssistantResponse.by_assistant(assistant.id)
    approved = responses.approved.count
    pending = responses.pending.count
    total = approved + pending

    {
      approved: approved,
      pending: pending,
      documents: Captain::Document.for_assistant(assistant.id).count,
      coverage: total.zero? ? 0 : (approved.to_f / total * 100).round
    }
  end

  def rate(numerator, denominator)
    return 0 if denominator.zero?

    (numerator.to_f / denominator * 100).round(1)
  end

  def pack(current, previous, mode)
    { current: current, previous: previous, trend: trend(current, previous, mode) }
  end

  def trend(current, previous, mode)
    case mode
    when :percent
      previous.zero? ? 0 : ((current - previous).to_f / previous * 100).round(1)
    else # :point and :absolute are both current - previous
      (current - previous).round(1)
    end
  end
end
