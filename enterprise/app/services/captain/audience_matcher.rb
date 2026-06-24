# Evaluates a Captain assistant's audience tree in-memory against the conversation's contact
# (plus the two conversation language fields). Zero DB queries on the hot path.
#
# A node is either:
#   - a GROUP: { "operator" => "and"|"or", "conditions" => [node, ...] }
#   - a LEAF:  { "attribute_key" => "...", "filter_operator" => "...", "values" => [...] }
#
# Operator semantics mirror Chatwoot's FilterService (see app/services/filter_service.rb and
# app/services/contacts/filter_service.rb) so the audience agrees with what the same conditions
# would match in the contact segment UI.
class Captain::AudienceMatcher
  CONTACT_STANDARD = %w[name email phone_number identifier blocked created_at last_activity_at].freeze
  CONTACT_ADDITIONAL = %w[country_code city company_name].freeze
  CONVERSATION_ADDITIONAL = %w[browser_language conversation_language].freeze
  OPERATORS = %w[equal_to not_equal_to contains does_not_contain is_present is_not_present starts_with
                 is_greater_than is_less_than days_before].freeze
  # One level of nesting: root group (depth 1) -> sub-group (depth 2) -> leaves (depth 3).
  MAX_DEPTH = 3

  def initialize(audience)
    @root = audience
  end

  def matches?(contact, conversation)
    return true if @root.blank?

    evaluate(@root, contact, conversation)
  end

  private

  def evaluate(node, contact, conversation)
    node = node.with_indifferent_access
    return evaluate_group(node, contact, conversation) if node.key?(:conditions)

    evaluate_leaf(node, contact, conversation)
  end

  def evaluate_group(node, contact, conversation)
    results = Array(node[:conditions]).map { |child| evaluate(child, contact, conversation) }
    node[:operator].to_s.casecmp?('or') ? results.any? : results.all?
  end

  def evaluate_leaf(node, contact, conversation)
    key = node[:attribute_key]
    actual = resolve_value(key, contact, conversation)
    apply_operator(node[:filter_operator], key, actual, node[:values])
  end

  def resolve_value(key, contact, conversation)
    case key
    when *CONTACT_STANDARD then contact.public_send(key)
    when *CONTACT_ADDITIONAL then contact.additional_attributes[key]
    when 'labels' then contact.label_list
    else resolve_conversation_value(key, contact, conversation)
    end
  end

  def resolve_conversation_value(key, contact, conversation)
    case key
    when *CONVERSATION_ADDITIONAL then conversation.additional_attributes[key]
    when 'hmac_verified' then conversation.contact_inbox&.hmac_verified || false
    else contact.custom_attributes[key]
    end
  end

  def apply_operator(operator, key, actual, values)
    expected = values.is_a?(Array) ? values.first : values

    case operator
    when 'equal_to'       then value_equal?(key, actual, expected)
    when 'not_equal_to'   then !value_equal?(key, actual, expected)
    when 'is_present'     then actual.present?
    when 'is_not_present' then actual.blank?
    else extended_operator(operator, actual, expected)
    end
  end

  def extended_operator(operator, actual, expected)
    case operator
    when 'contains'         then downcase(actual).include?(downcase(expected))
    when 'does_not_contain' then downcase(actual).exclude?(downcase(expected))
    when 'starts_with'      then downcase(actual).start_with?(downcase(expected))
    when 'is_greater_than'  then compare(actual, expected, :>)
    when 'is_less_than'     then compare(actual, expected, :<)
    when 'days_before'      then date_before?(actual, expected)
    else false
    end
  end

  def value_equal?(key, actual, expected)
    return Array(actual).include?(expected) if key == 'labels'
    return ActiveModel::Type::Boolean.new.cast(expected) == actual if [true, false].include?(actual)

    normalize(key, actual) == normalize(key, expected)
  end

  def normalize(key, value)
    return value if value.nil?

    case key
    when 'phone_number' then "+#{value.to_s.delete('+')}"
    when 'country_code' then value.to_s.downcase
    else value.is_a?(String) ? value.downcase : value
    end
  end

  def downcase(value)
    value.to_s.downcase
  end

  def compare(actual, expected, operator)
    return false if actual.blank?

    actual_value, expected_value = coerce_pair(actual, expected)
    return false if actual_value.nil? || expected_value.nil?

    actual_value.public_send(operator, expected_value)
  end

  def coerce_pair(actual, expected)
    if date_like?(actual)
      [actual.to_time, parse_time(expected)]
    else
      [BigDecimal(actual.to_s), BigDecimal(expected.to_s)]
    end
  rescue ArgumentError, TypeError
    [nil, nil]
  end

  def date_before?(actual, expected)
    actual_date = to_date(actual)
    return false if actual_date.nil?

    actual_date < (Time.zone.today - expected.to_i.days)
  end

  def date_like?(value)
    value.is_a?(Date) || value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  end

  def to_date(value)
    return value.to_date if value.respond_to?(:to_date)

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
