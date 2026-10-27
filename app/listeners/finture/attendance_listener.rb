# Mantém o modo de atendimento coerente com os caminhos antigos que já
# significavam "humano": etiqueta `atendimento_humano` aplicada à mão (ou por
# automação) e conversa atribuída a um agente. Só ESCALA para humano — remover
# etiqueta/responsável nunca devolve à IA (isso exige o botão).
#
# Roda assíncrono: o evento pode chegar atrasado. Por isso confere se o sinal
# ainda vale (etiqueta/responsável continuam lá) e passa o horário do evento ao
# serviço, que ignora a escalada se o modo mudou depois dele.
class Finture::AttendanceListener < BaseListener
  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes] || {}
    return if conversation.blank? || changes.blank?

    if human_label_added?(conversation, changes)
      escalate(conversation, 'label', nil, event)
    elsif agent_assigned?(conversation, changes)
      escalate(conversation, 'assignment', conversation.assignee, event)
    end
  end

  private

  def escalate(conversation, source, user, event)
    Finture::AttendanceModeService.new(conversation: conversation)
                                  .escalate!(source: source, user: user, occurred_before: event.timestamp)
  end

  def human_label_added?(conversation, changes)
    previous, current = changes['label_list'] || changes[:label_list]
    return false unless previous.is_a?(Array) && current.is_a?(Array)

    label = Finture::AttendanceState::HUMAN_LABEL
    current.include?(label) && previous.exclude?(label) && conversation.cached_label_list_array.include?(label)
  end

  def agent_assigned?(conversation, changes)
    _previous, current = changes['assignee_id'] || changes[:assignee_id]
    current.present? && conversation.assignee_id == current
  end
end
