class Captain::DocumentationSearchService
  TOP_MATCHES_TO_FORMAT = 5

  class << self
    def serialize(result)
      result.merge(matches: result[:matches].map(&:to_h))
    end

    def metadata(result)
      {
        match_count: result[:matches].length,
        top_semantic_distance: result[:matches].first&.semantic_distance
      }.compact
    end

    def format_for_tool(result, no_results_message:, documentation_sufficiency: nil)
      return "#{no_results_message}\n\n#{no_results_instruction}" if result[:matches].empty?

      [documentation_sufficiency_section(documentation_sufficiency), formatted_matches(result)].flatten.compact.join("\n")
    end

    private

    def formatted_matches(result)
      result[:matches].first(TOP_MATCHES_TO_FORMAT).map { |match| format_match(match) }
    end

    def format_match(match)
      response = match.response
      lines = ['', "Question: #{response.question}", "Answer: #{response.answer}"]
      lines << "Source: #{response.documentable.external_link}" if response.documentable.present? && response.documentable.try(:external_link)
      "#{lines.join("\n")}\n"
    end

    def documentation_sufficiency_section(documentation_sufficiency)
      decision = documentation_sufficiency && (documentation_sufficiency[:decision] || documentation_sufficiency['decision'])
      return if decision.blank?

      if decision == 'sufficient'
        [
          'Documentation support: sufficient',
          'Instruction: Use only the retrieved documentation below to answer the user.'
        ].join("\n")
      else
        [
          'Documentation support: insufficient',
          'Instruction: The retrieved documentation does not answer the user question.',
          'Do not answer the factual question from these results. Ask one clarifying question if useful, or offer a handoff.'
        ].join("\n")
      end
    end

    def no_results_instruction
      [
        'Instruction: No documentation matched this query.',
        'Do not use documentation search results to make factual claims.',
        'Ask one useful follow-up question or offer a handoff.'
      ].join(' ')
    end
  end

  def initialize(scope:, account_id: nil)
    @scope = scope
    @account_id = account_id
  end

  def search(query)
    matches = @scope.search_with_metadata(query, account_id: @account_id)
    {
      query: query,
      queries: [query],
      matches: matches
    }
  end
end
