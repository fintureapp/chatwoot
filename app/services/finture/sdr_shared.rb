# Helpers compartilhados pelas visões do Dashboard SDR. Os services expõem
# `account`, `inbox_id` e `current_user`, então isto concentra o que seria
# duplicado: o escopo de visibilidade, o rótulo de "área" (= Time da conversa,
# para onde a triagem roteia) e a agenda de follow-ups do próprio agente.
module Finture::SdrShared
  AGENT_FOLLOWUPS_LIMIT = 20

  # ---- Escopo de visibilidade -----------------------------------------------
  # Conversas que o usuário logado pode ver — MESMA regra do Kanban
  # (Conversations::PermissionFilterService: admin vê a conta inteira, agente só
  # as caixas de que é membro, custom role enterprise restringe ainda mais).
  # Antes os services partiam de account.conversations e um agente via métricas
  # e nomes de clientes de caixas que não são dele. Sem usuário não há escopo:
  # o dashboard nunca agrega a conta às cegas.
  def visible_conversations
    @visible_conversations ||= if current_user.nil?
                                 account.conversations.none
                               else
                                 Conversations::PermissionFilterService.new(account.conversations, current_user, account).perform
                               end
  end

  def conversations_scope
    inbox_id.present? ? visible_conversations.where(inbox_id: inbox_id) : visible_conversations
  end

  # Transições só de conversas visíveis. O recorte por caixa usa o inbox_id da
  # própria transição (a caixa onde ela aconteceu).
  def transitions_scope
    scope = Finture::StageTransition.where(account_id: account.id, conversation_id: visible_conversations.select(:id))
    inbox_id.present? ? scope.where(inbox_id: inbox_id) : scope
  end

  # {team_id => nome}. A triagem (n8n) atribui a conversa a um Time por área
  # (consórcio, crédito pj, saúde...); é a granularidade confiável de "produto".
  def team_names
    @team_names ||= account.teams.pluck(:id, :name).to_h
  end

  def team_name(team_id)
    return 'Sem time' if team_id.nil?

    team_names[team_id] || "Time ##{team_id}"
  end

  # Follow-ups em aberto DO agente logado, por ordem de vencimento — o rodapé do
  # dashboard onde ele vê o que marcou e quando vence.
  def my_follow_ups
    return [] unless current_user

    scope = Finture::FollowUp.where(account_id: account.id, user_id: current_user.id,
                                    conversation_id: conversations_scope.select(:id)).open_items

    scope.includes(conversation: :contact).order(:due_at).limit(AGENT_FOLLOWUPS_LIMIT).map do |follow_up|
      {
        id: follow_up.conversation.display_id,
        title: follow_up.title,
        contact: follow_up.conversation.contact&.name,
        due_at: follow_up.due_at.to_i,
        overdue: follow_up.due_at < Time.current
      }
    end
  end
end
