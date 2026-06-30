# Computes per-assistant overview metrics for the Captain Overview page.
# Each metric is returned for the current window and the previous equal-length
# window, plus a derived trend.
#
# Queries are batched to cut round trips: the message-derived counts (handled,
# public replies, depth) and the average reply time are each computed for both
# windows in a single scan via conditional FILTER aggregation.
class Captain::AssistantStatsBuilder
  RESOLVED_EVENT_NAMES = %w[conversation_captain_inference_resolved conversation_bot_resolved].freeze
  HANDOFF_EVENT_NAMES = %w[conversation_captain_inference_handoff conversation_bot_handoff].freeze
  DEFAULT_RANGE = '30'.freeze
  ALLOWED_RANGES = %w[7 30 90 this_month last_month].freeze

  attr_reader :assistant, :account, :range

  # `range` is either a day count ('7', '30', '90') or a named period
  # ('this_month', 'last_month'). The previous window mirrors the current one:
  # the preceding N days for day ranges, or the preceding month for month ranges.
  def initialize(assistant, range = DEFAULT_RANGE)
    @assistant = assistant
    @account = assistant.account
    @range = ALLOWED_RANGES.include?(range.to_s) ? range.to_s : DEFAULT_RANGE
  end

  def metrics
    messages = message_window_metrics
    reply_times = avg_reply_times
    current = window_metrics(current_range, messages[:current], reply_times[:current])
    previous = window_metrics(previous_range, messages[:previous], reply_times[:previous])

    build_metrics(current, previous)
  end

  # Human-readable description of the period the metrics cover, for grounding the
  # LLM summary in real dates.
  def period
    {
      label: period_label,
      starts_on: current_range.first.to_date,
      ends_on: current_range.last.to_date
    }
  end

  private

  def build_metrics(current, previous)
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

  def period_label
    { 'this_month' => 'this month', 'last_month' => 'last month' }[range.to_s] || "the last #{range.to_i} days"
  end

  def current_range
    resolved_ranges[:current]
  end

  def previous_range
    resolved_ranges[:previous]
  end

  def resolved_ranges
    @resolved_ranges ||= case range.to_s
                         when 'this_month' then this_month_ranges
                         when 'last_month' then last_month_ranges
                         else day_ranges
                         end
  end

  def this_month_ranges
    start = Time.current.beginning_of_month
    elapsed = Time.current - start
    previous_start = start - 1.month
    { current: start..Time.current, previous: previous_start..(previous_start + elapsed) }
  end

  def last_month_ranges
    start = 1.month.ago.beginning_of_month
    previous_start = start - 1.month
    { current: start..start.end_of_month, previous: previous_start..previous_start.end_of_month }
  end

  def day_ranges
    days = range.to_i
    { current: days.days.ago..Time.current, previous: (2 * days).days.ago..days.days.ago }
  end

  # Combines the per-window message counts and reply time with the reporting-event metrics for one window.
  def window_metrics(range, message_counts, avg_reply)
    handled = message_counts[:handled]
    public_count = message_counts[:public_count]
    depth_conversations = message_counts[:depth_conversations]
    resolution = resolution_counts(range)

    {
      handled: handled,
      auto_resolution: rate(resolution[:resolved], handled),
      handoff: rate(resolution[:handoff], handled),
      hours_saved: (public_count * avg_reply / 3600.0).round,
      reopen: reopen_rate(range),
      depth: depth_conversations.zero? ? 0 : (public_count.to_f / depth_conversations).round(1)
    }
  end

  # One scan over the assistant's messages computes handled, public-reply count,
  # and depth-conversation count for both windows via conditional aggregation.
  def message_window_metrics
    public_clause = "message_type = #{Message.message_types[:outgoing]} AND private = false"
    cur = window_clause(current_range)
    prev = window_clause(previous_range)

    row = handled_scope(full_span).reorder(nil).pick(
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE #{cur})"),
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE #{prev})"),
      Arel.sql("COUNT(*) FILTER (WHERE #{cur} AND #{public_clause})"),
      Arel.sql("COUNT(*) FILTER (WHERE #{prev} AND #{public_clause})"),
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE #{cur} AND #{public_clause})"),
      Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE #{prev} AND #{public_clause})")
    )

    {
      current: { handled: row[0], public_count: row[2], depth_conversations: row[4] },
      previous: { handled: row[1], public_count: row[3], depth_conversations: row[5] }
    }
  end

  # Average reply time (seconds) for both windows in one scan.
  def avg_reply_times
    row = account.reporting_events.where(name: 'reply_time', created_at: full_span).reorder(nil).pick(
      Arel.sql("AVG(value) FILTER (WHERE #{window_clause(current_range)})"),
      Arel.sql("AVG(value) FILTER (WHERE #{window_clause(previous_range)})")
    )
    { current: row[0].to_f, previous: row[1].to_f }
  end

  # Resolved and handed-off conversation counts for one window, in a single scan
  # of the handled set's reporting events.
  def resolution_counts(range)
    row = account.reporting_events
                 .where(name: RESOLVED_EVENT_NAMES + HANDOFF_EVENT_NAMES,
                        created_at: range,
                        conversation_id: handled_scope(range).select(:conversation_id))
                 .reorder(nil)
                 .pick(
                   Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE name IN (#{quoted(RESOLVED_EVENT_NAMES)}))"),
                   Arel.sql("COUNT(DISTINCT conversation_id) FILTER (WHERE name IN (#{quoted(HANDOFF_EVENT_NAMES)}))")
                 )
    { resolved: row[0], handoff: row[1] }
  end

  # Conversations the assistant participated in (authored any message).
  def handled_scope(range)
    account.messages.where(sender_type: 'Captain::Assistant', sender_id: assistant.id, created_at: range)
  end

  # Span covering both windows so a single scan can split them with FILTER.
  def full_span
    [current_range.first, previous_range.first].min..current_range.last
  end

  def window_clause(range)
    "created_at >= #{quote(range.first)} AND created_at <= #{quote(range.last)}"
  end

  def quote(value)
    account.class.connection.quote(value)
  end

  def quoted(values)
    values.map { |value| quote(value) }.join(', ')
  end

  # Of the conversations Captain auto-resolved (inbox-based), the share reopened afterwards.
  def reopen_rate(range)
    resolved_scope = account.reporting_events.where(name: 'conversation_captain_inference_resolved',
                                                    inbox_id: assistant_inbox_ids, created_at: range)
    resolved = resolved_scope.distinct.count(:conversation_id)
    reopened = account.reporting_events
                      .where(name: 'conversation_opened', conversation_id: resolved_scope.select(:conversation_id))
                      .where('reporting_events.value > 0')
                      .distinct.count(:conversation_id)
    rate(reopened, resolved)
  end

  def assistant_inbox_ids
    @assistant_inbox_ids ||= assistant.inboxes.ids
  end

  # Approved/pending FAQ counts and the document total in a single round trip.
  def knowledge
    approved, pending, documents = Captain::AssistantResponse.by_assistant(assistant.id).reorder(nil).pick(
      Arel.sql("COUNT(*) FILTER (WHERE status = #{Captain::AssistantResponse.statuses['approved']})"),
      Arel.sql("COUNT(*) FILTER (WHERE status = #{Captain::AssistantResponse.statuses['pending']})"),
      Arel.sql("(SELECT COUNT(*) FROM captain_documents WHERE assistant_id = #{assistant.id.to_i})")
    )
    total = approved + pending

    {
      approved: approved,
      pending: pending,
      documents: documents,
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
