class Captain::DocumentationSufficiencySchema < RubyLLM::Schema
  DECISIONS = %w[sufficient insufficient].freeze

  string :decision,
         enum: DECISIONS,
         description: 'Use sufficient only when retrieved documentation directly answers the latest user question'
end
