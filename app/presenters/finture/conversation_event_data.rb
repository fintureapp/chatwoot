# Acrescenta o modo de atendimento (IA x humano) ao payload da conversa usado no
# ActionCable (lista/kanban atualizam sem recarregar) e nos webhooks (o n8n
# recebe `conversation.finture_attendance` já no evento de mensagem).
module Finture::ConversationEventData
  def push_data
    super.merge(finture_attendance: Finture::AttendanceState.payload_for(__getobj__))
  end
end
