class Llm::CredentialResolver
  def initialize(provider:, openai_hook: nil)
    @provider = provider.to_s
    @openai_hook = openai_hook
  end

  def resolve
    hook_llm_credential || system_llm_credential
  end

  private

  attr_reader :provider, :openai_hook

  def hook_llm_credential
    return unless Llm::Config.openai_provider?(provider)

    key = openai_hook&.settings&.dig('api_key').presence
    { api_key: key, provider: provider, source: :hook } if key
  end

  def system_llm_credential
    key = Llm::Config.api_key_for(provider).presence
    { api_key: key, provider: provider, source: :system } if key
  end
end
