class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    # Finture::DemandaListener é síncrono de propósito: precisa de Current (autor
    # do evento) e do instante exato em que a conversa ficou elegível. Só filtra
    # e enfileira; o envio ao HUB roda no Finture::DemandaSyncJob.
    [ActionCableListener.instance, AgentBotListener.instance, Finture::DemandaListener.instance]
  end
end
