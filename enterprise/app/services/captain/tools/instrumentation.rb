module Captain::Tools::Instrumentation
  extend ActiveSupport::Concern
  include Integrations::LlmInstrumentation

  def execute(**args)
    return super unless self.class.instrument_tool_execution?

    instrument_tool_call(name, args) do
      super
    end
  end

  def self.prepended(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def instrument_tool_execution?
      @instrument_tool_execution != false
    end

    def skip_tool_execution_instrumentation
      @instrument_tool_execution = false
    end
  end
end
