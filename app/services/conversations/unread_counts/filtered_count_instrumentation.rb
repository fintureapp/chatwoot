class Conversations::UnreadCounts::FilteredCountInstrumentation
  # Centralizes the rollout-critical filtered unread count signals:
  # API response duration, counter duration, snapshot build duration, snapshot state distribution,
  # refresh claim rate, build lock acquisition rate, and invalidation/version bump rate.
  EVENT_NAME = 'FilteredUnreadCounts'.freeze
  METRIC_PREFIX = 'Custom/Conversations/UnreadCounts/Filtered'.freeze

  class << self
    def observe(operation, attributes = {})
      started_at = monotonic_time

      yield.tap do
        record_observation(operation, attributes, started_at, status: :success)
      end
    rescue StandardError => e
      record_observation(operation, attributes.merge(error_class: e.class.name), started_at, status: :error)
      raise
    end

    def increment(operation, attributes = {})
      record_event(operation, attributes)
      record_metric("#{metric_name(operation)}/count", 1)
    end

    def record_event(operation, attributes = {})
      agent = new_relic_agent
      return unless agent.respond_to?(:record_custom_event)

      agent.record_custom_event(EVENT_NAME, sanitized_attributes(attributes.merge(operation: operation)))
    rescue StandardError
      nil
    end

    private

    def record_observation(operation, attributes, started_at, status:)
      duration_ms = elapsed_ms_since(started_at)
      record_event(operation, attributes.merge(status: status, duration_ms: duration_ms))
      record_metric("#{metric_name(operation)}/duration_ms", duration_ms)
    end

    def record_metric(name, value)
      agent = new_relic_agent
      return unless agent.respond_to?(:record_metric)

      agent.record_metric(name, value)
    rescue StandardError
      nil
    end

    def metric_name(operation)
      "#{METRIC_PREFIX}/#{operation}"
    end

    def sanitized_attributes(attributes)
      attributes.compact.transform_values do |value|
        case value
        when String, Integer, Float, TrueClass, FalseClass
          value
        else
          value.to_s
        end
      end
    end

    def elapsed_ms_since(started_at)
      ((monotonic_time - started_at) * 1000).round(2)
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def new_relic_agent
      return unless defined?(::NewRelic::Agent)

      ::NewRelic::Agent
    end
  end
end
