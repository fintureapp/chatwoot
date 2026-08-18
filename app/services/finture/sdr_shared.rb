# Helpers compartilhados pelas visões Comercial e Operacional do Dashboard SDR.
# Ambos os services expõem `account`, `inbox_id` e `current_user`, então isto
# concentra o que seria duplicado: o rótulo de "área" (= Time da conversa, para
# onde a triagem roteia) e a agenda de follow-ups do próprio agente.
module Finture::SdrShared
  AGENT_FOLLOWUPS_LIMIT = 20

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

    scope = Finture::FollowUp.where(account_id: account.id, user_id: current_user.id).open_items
    scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id.present?

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
