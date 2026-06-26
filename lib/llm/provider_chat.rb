require 'delegate'

class Llm::ProviderChat < SimpleDelegator
  def initialize(chat, provider:)
    @provider = provider.to_s
    super(chat)
  end

  def with_schema(schema)
    return self unless supports_tools_and_schema?

    __setobj__(__getobj__.with_schema(schema))
    self
  end

  def with_tool(tool)
    return self unless supports_tools_and_schema?

    __setobj__(__getobj__.with_tool(tool))
    self
  end

  def with_params(**params)
    filtered_params = params.dup
    filtered_params.delete(:response_format) unless supports_tools_and_schema?
    return self if filtered_params.blank?

    __setobj__(__getobj__.with_params(**filtered_params))
    self
  end

  private

  def supports_tools_and_schema?
    Llm::Config.supports_tools_and_schema?(@provider)
  end
end
